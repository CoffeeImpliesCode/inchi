# CHANGELOG — fork-only divergences

Upstream's release history lives in its own repository
(`INCHI-1-DOC/CHANGELOG.md`, and the release notes in `INCHI-1-DOC/RelNotes/`).
This file records **only** what this fork changed relative to InChI `v1.07.5`
(commit `11a87982bb518f57ac013f0b258c283655e1ea1d`), and nothing upstream did.

Every gate named here was run by the driver. Where a correction has not been
gated since it was made, that is said in the entry, and no green result is
claimed for it. Each entry keeps the receipts that were current when its claim
was made. **No entry below describes the tree as it stands.** §29 was the
current cutover until §36 landed; §36 changed the build graph, the installed
closure, the integrity record and the documentation, and nothing has been gated
over it since. The current matrix, with each row marked history or
`PENDING-VERIFICATION`, is in [`README.md`](README.md) § Current build, run and
test matrix; the full receipt table is in `README.zig.md` § Verification status.

## 1. Added the Zig 0.16 package

`build.zig`, `build.zig.zon`, `translate.h`, `zig/root.zig`, `zig/molecules.zig`,
`tests.zig`, `smoke.zig`, `consumer/` and `testdata/pubchem_known_answers.tsv`
are new files. Upstream has no Zig package and none is inherited; the
fingerprint was generated for this one.

`build.zig.zon` carries `.version = "1.7.5"` rather than `1.07.5`, because a
semantic version cannot hold the leading zero. `build.zig:204-209` refuses to
configure when that version stops matching the pin, so an InChI version bump is
a decision someone takes rather than a side effect of a merge.

## 2. Compiled upstream's whole `libinchi` target, including the IXA backend

**Condition.** Upstream can build the same sources as the `inchi-1` executable,
as `wInChI`, or as the API library, and its CMake target lists the units
explicitly.

**Decision.** Compile the API library's own list: all **60** `.c` files in
`INCHI-1-SRC/INCHI_BASE/src` and `INCHI-1-SRC/INCHI_API/libinchi/src`, written
out file by file in `build.zig:60-131` rather than globbed, with
`TARGET_API_LIB=1` and `COMPILE_ANSI_ONLY=1` (`src/CMakeLists.txt:154-158`),
`-std=c11` and `-fno-strict-aliasing` (upstream's own dialect, flags and
reasons, quoted in `build.zig:133-159`). The six `ixa/*.c` units are in that
list and are compiled: IXA is declared by `ixa.h`, which `inchi_api.h:1413`
includes, so a package that shipped the header without the backend would ship a
declaration it cannot honour. `fPIC` is deliberately not defined — it is inert
in the sources and this package builds a static archive.

**Target bound.** Any InChI release whose compile unit list moves. Step 4 of
the re-sync procedure in `UPSTREAM.md` exists for exactly this.

## 3. Chose the in-tree build as the default, and `-fsys=inchi` as the opt-in

**Condition.** `b.systemIntegrationOption` is fed by `-fsys=`/`-fno-sys=`, not
by a `-D` option, so `-Dsystem=true` would be an unknown option rather than a
mode.

**Decision.** `b.systemIntegrationOption("inchi", .{})`, so the bundled,
full, in-tree library is what a plain `zig build` produces, and a system
library is opt-in. In system mode the build translates the *installed*
`<inchi_api.h>` and adds no in-tree include path, because an in-tree header
would be found first and would silently bind this repository's 1.07.5
declarations to whatever `libinchi` is installed; it links `-linchi` by name
rather than through pkg-config, which upstream does not ship. `translate.h` and
the generated system wrapper both define the same two macros from the same
`core_macros` table, so the header and the compile cannot drift apart.

**Target bound.** The same for any C facade with a system-library mode. **No
run of `-fsys=inchi` has happened in this workspace and no result is claimed
for it.**

## 4. Made the six borrowed strings sentinel-typed

**Condition.** A C entry point returns NUL-terminated strings; a Zig binding
that re-declares the return type without the sentinel throws the terminator away
and every caller has to copy before it can call a `const char *` parameter.

**Symptom.** `smoke.zig:88:36: error: expected type '[:0]const u8', found
'[]const u8'` — `destination pointer requires '0' sentinel`
(`local://foundation-expansion-inchi-repaired-smoke-proof-69.log`).

**Fix.** `Output.identifier`, `Output.auxInfo`, `Output.message`, `Output.log`,
`Structure.message` and `Structure.log` now return `?[:0]const u8` /
`[:0]const u8`. The terminator is upstream's own, not a re-derivation: the
helper `spanOrNull` already computed `?[:0]const u8` through `std.mem.span`, so
no allocation and no copy was added to make it true — `szInChI`/`szAuxInfo` are
one string-stream buffer split in two (`inchi_dll.c:764-777`), `szMessage` is a
`strlen + 1` `strcpy` or a buffer `ReadWriteInChI` terminates
(`ichiread.c:715`), and `szLog`'s trailing line feeds are overwritten with
`'\0'` before handover (`inchi_dll.c:791-806`).

**Target bound.** Any InChI-style C facade over allocate-in-C, read-only-here
APIs; Zig 0.16.0.

## 5. Kept the C input struct mutable and its borrowed contents const

**Condition.** `GetStdINCHI`, `GetINCHI`, `GetINCHIfromINCHI` and both
`GetStructFrom*` entry points declare their input struct non-const
(`inchi_dll.c:242`, `inchi_dll.c:2114`), while `inputStruct`/`identifierInput`
return the struct by value and the call sites bound it with `const`.

**Symptom.** `zig/root.zig:572:36: error: expected type '[*c]T', found
'*const T'`, `T = translate.struct_tagINCHI_Input`, `cast discards const
qualifier` — the same receipt, `zig/root.zig`.

**Fix.** `var input` at all five call sites. The struct is a genuine mutable
local; no `@constCast` of the struct, no allocation, and no copy of the caller's
atoms. What is borrowed stays borrowed and stays unwritten: `GetStdINCHI` and
`GetINCHI` copy every field of the struct into a local `inchi_InputEx`
(`inchi_dll.c:252-256`), `ExtractOneStructure` copies the atoms into its own
`inp_ATOM` (`inchi_dll.c:1933-1936`) and only reads the 0D descriptors, and
`GetINCHIfromINCHI`/`GetStructFrom*` only read `szInChI`/`szOptions`. The one
entry point that writes through the atom array is `GetINCHIEx`
(`inchi_dll.c:330-336`), which is reachable through `pub const c` and
deliberately not wrapped — which is what keeps `Molecule.atoms` honestly
`[]const Atom`.

The same defect sat at four sites the smoke root never instantiated — Zig
analyses an unreferenced public function lazily — so `fromMolecule.full` and all
three `fromIdentifier.*` had it too.

**Target bound.** Same as §4.

## 6. Repaired a block comment in `translate.h` that closed itself

**Condition.** The comment explaining what the translation root pulls in
contained the text `the whole Get*/Free*/Check* surface`.

**Symptom.** Five gates red with `translate-c 231 errors` and
`error: translation failure`, the first error at `translate.h:9:25:
error: type specifier missing, defaults to 'int'`. The `*/` in `Get*/Free*/Check*`
terminated the comment, so the rest of the prose was fed to the C parser.
Receipts: `…-current-debug-49`, `…-current-smoke-59`, `…-current-install-60`,
`…-current-releasesafe-62`, `…-current-consumer-65`.

**Fix.** Reword the comment to say "the whole Get, Free and Check function
surface and the whole IXA_* handle API". Nothing about the header's behaviour
changed; `IXA_*` contains no `*/`.

**Target bound.** Any C translation root. This one is worth keeping because the
failure is 231 errors about the *wrong* file's prose and reads as a header
problem.

## 7. Repaired a file-scope `comptime` keyword and a shadowed local

**Condition.** Two Zig 0.16 scope rules, in two different files.

**Symptom and fix.**

* `build.zig:478:30: error: redundant comptime keyword in already comptime scope`
  and `build.zig:480:5: error: redundant inline keyword in comptime scope`
  (`…-repaired-debug-23.log`). A file-scope `const` initialiser is already
  comptime, so both keywords were errors, not hints. Dropped them; the `#define`
  text is still assembled at comptime out of the same `core_macros` table.
* `zig/molecules.zig:71:15: error: local constant shadows declaration of
  'index'` (`…-repaired-smoke-proof-69.log`). `Scratch.addAtom`'s local
  `index` shadowed the file's `fn index(atom: usize) i16`. Renamed the local to
  `slot`; the helper keeps its name and now has a doc comment recording that it
  is the `AT_NUM` narrowing helper (`inchi_api.h:124`).

**Target bound.** Zig 0.16.0.

## 8. Replaced slice `!=` with `std.mem.eql` in the tests

**Condition.** `!=` is not an operator for slices in Zig: the language reference
lists Equality for integers, floats, bool, type and packed struct only, and no
`==` on a slice appears anywhere in the pinned toolchain's `lib/`.

**Symptom.** Not reached — `tests.zig` had never been compiled. Found while
reading the file rather than by a gate.

**Fix.** `!std.mem.eql(u8, a.identifier().?, b.identifier().?)` at the three
sites that compared two identifiers, and `expectEqualStrings` in the helper that
compares an identifier with a published one. `std.mem.eql` is correct under
either reading of the language reference and strictly stronger, so nothing
depends on which reading is right.

**Target bound.** Zig 0.16.0; any test that compared two slices for inequality.

## 9. Applied the option-prefix substitution upstream does at run time

**Condition.** Upstream holds its strict option string as the template
`" ?FixedH ?RecMet ?SUU ?SLUUD"` and overwrites the four question marks with
`INCHI_OPTION_PREFX` before use (`inchi_dll.c:965`).

**Symptom.** The `.windows` arm of `zig/molecules.zig`'s
`strict_options`/`no_aux_options` carried the template unexpanded. The C
recognises an option only by its first byte (`ichiparm.c:1221`), which must be
the compiled-in prefix — `/` on `_WIN32`, `-` elsewhere (`mode.h:262-268`) — so
every `?`-prefixed token would have fallen through as unrecognised and
`FixedH`, `RecMet`, `SUU` and `SLUUD` would silently not have been applied.
Not observed on this host: the non-Windows arm was correct.

**Fix.** The arms are now that string with the substitution already applied,
`"/FixedH /RecMet /SUU /SLUUD"` and `"/AuxNone"` on Windows. The doc comment
says so and says why.

**Target bound.** Windows targets, and only reachable in this workspace by
`zig build check -Dtarget=x86_64-windows-gnu`, which is compile-only: the
round-trip behaviour of those options on a Windows host has never been executed
here.

## 10. Made `IdentifierVerdict` and `KeyVerdict` non-exhaustive

**Condition.** `CheckINCHI` and `CheckINCHIKey` return a plain `int`, and both
switches ended in `else => unreachable`.

**Decision.** Both became `enum(c_int)` with a `_` field, ending
`else => @enumFromInt(code)`, so a code this release does not name is reported
as an unnamed value instead of trapping in the middle of a report — exactly
what `Status`/`statusFrom` already did. The explicit `c_int` backing type is
required: a tag-typed non-exhaustive enum would make `@enumFromInt` a
safety-checked trap again. No fabricated mapping and no new error variant was
introduced; `KeyError.UnknownFailure` remains the landing place it already was.

**Target bound.** None observable. No `switch` over either enum exists in the
package, and the unnamed path is not exercised by anything.

## 11. Corrected the `doubleBondStereo` doc comment to describe what it writes

**Condition.** The comment promised "double bond, allene or cumulene" and
described an allene's `central_atom`, while the body writes `central_atom =
no_atom` and `type = double_bond` unconditionally.

**Fix.** The comment now says only the `INCHI_StereoType_DoubleBond` form is
built here, and that the allene form — same quadruple,
`type = INCHI_StereoType_Allene`, the middle atom of the odd double-bond chain
in `central_atom` (`inchi_api.h:230-243`) — is written on the public `Stereo0D`
directly. No allene constructor was added; the struct is public and that is the
honest route.

## 12. Added the charge-warning fixture and the test that holds its identifier

**Condition.** `Status.warning` and `isWarning()` were exercised in neither
direction, so the module's headline contract — a warning carries its identifier
rather than becoming an error — had no test.

**Change.** `molecules.glycineZwitterion` builds NH3(+)-CH2-COO(-) with the two
charges on the raw `Atom.charge` field, and a new test asserts that the neutral
run is `.okay` with an empty message while the zwitterion run is `.warning`,
that `isWarning()` holds, that its identifier is the one PubChem publishes for
CID 750, and that it equals the neutral run's identifier. It is not a non-empty
check: the identifier is a specific published known answer, the same one the
glycine test already pins.

**Status: observed, with one assertion retired.** The test runs and passes in
the Debug suite (`…-native-Debug-borrowed-atoms-183.log`), so the claim that the
zwitterion's identifier comes back byte-identical to neutral glycine's is now an
observation rather than the inference from `ichi_bns.c:5451-5461` it was when
this entry was written. The assertion that the message names
`Proton(s) added/removed` was removed — see §23 — so what is pinned is the
status, `isWarning()`, the published identifier and the empty message of the
clean run, not upstream's English.

## 13. Restored a missing declaration in `tests.zig`

**Condition.** The but-2-ene stereobond test declared only `even` and then used
`odd` at three places, so the file did not compile — and `tests.zig` is
imported by the native test root and by all six cross `check` targets.

**Fix.** `var odd = try inchi.fromMolecule.standard(try molecules.but2ene(&scratch,
.odd)); defer odd.deinit();`. The file had never been compiled, so nothing
caught it.

## 14. Forwarded the system-integration choice to the nested consumer build

**Condition.** `consumer/` is built as its own `zig build`, because its manifest
points back at this package by path and a dependency cycle is not expressible.
That nested graph runs this package's `build()` again as a path dependency and
re-reads `b.systemIntegrationOption` there.

**Decision.** `runConsumer` takes the already-resolved `use_system` and adds
`-fsys=inchi` or `-fno-sys=inchi` to the nested command line, beside the target,
the CPU and the optimisation mode. Without it, `zig build consumer -fsys=inchi`
would install one configuration and then prove the consumer against another
without saying so.

## 15. Removed `continue-on-error` from the WASI cross job

**Condition.** The workflow carried `continue-on-error: true` on `wasm32-wasi`,
which turned a red compile-only check into a green job, and the adjacent comment
stated a failure as established fact with no run behind it. `aarch64-macos-none`
was not carried in the same boundary even though the source-level cause is
identical.

**Change.** `continue-on-error` removed. Each of the six targets is attempted
(`fail-fast: false`), the step captures the real exit status, writes it plus a
note into `$GITHUB_STEP_SUMMARY`, and then exits with it — so the job is red
when the check is red.

**Update, now that the six checks have run.** The source expectation was right
about one target and wrong about the other. `aarch64-macos-none` is **red** with
`ichicano.c:46:10: error: 'sys/timeb.h' file not found`
(`…-check-aarch64-macos-none-204.log`); `wasm32-wasi` **compiled**
(`…-check-wasm32-wasi-207.log`), same unconditional include, same absent header
in the sysroot survey. Four targets are green. Upstream's source is still not
modified to work around the macOS failure, and the boundary note in the workflow
still describes a source-level dependency — it is now a source-level dependency
with a receipt behind one of its two targets.

**Consequence, stated plainly.** The `cross` matrix is red on
`aarch64-macos-none` until that boundary is handled at the parent's level, and
the `native` job's ReleaseSafe step is red too (§24). Both are the requested
behaviour: the workflow does not hide them, and neither does this file.

**Updated after the patch (§29).** The six targets were re-run over the patched
tree, `-367` through `-372`: the same five green, and `aarch64-macos-none` still
red on the same `sys/timeb.h` diagnostic, which is upstream's file and untouched.
The `native` job's ReleaseSafe step is no longer red for this fork's own C.

## 16. Appended Zig entries to `.gitignore`

Upstream's 31 rules, ending `INCHI-1-SRC/INCHI_API/libinchi/src/build/`, are
kept verbatim and in place; none was removed to make room. The fork appended
`.zig-cache/`, `zig-out/`, `consumer/.zig-cache/` and `consumer/zig-out/`, none
of which swallows an upstream rule or a file the fork adds. `.gitignore` is
therefore deliberately **not** in `UPSTREAM.sha256`: it is not byte-identical to
upstream's.

## 17. Added the provenance and documentation set

`UPSTREAM.md`, `UPSTREAM.sha256` (109 records), `NOTICE.md`, `README.zig.md`,
`CHANGELOG.md` and `FORK-NOTES.md`. The integrity record covers only upstream
files plus the independent fixture, never this fork's own files, so it stays
valid across a re-sync.

**Status: observed.** The original 108 records were written and then re-derived
from the written file with the same raw-byte method — 108 re-derived, 0
mismatches — and `sha256sum -c UPSTREAM.sha256` has since been run here over all
**109**: exit 0, no failures
(`local://foundation-expansion-inchi-immutable-source-complete-legal-109-240.log`).
The earlier 108-record run
(`…-immutable-source-including-complete-Apache-license-221.log`) is kept as
history; §25 explains what changed between the two.
§29 records the patched `ichiparm.c` line verified over all 109 at the repository
root and again inside the re-fetched package.

## 18. Three things this fork's documentation could not make, and the parent did

1. **`build.zig.zon`'s `.paths` had to list `UPSTREAM.sha256`.** It did not, so
   the record did not travel with the package. **Closed**: `.paths` lists
   `UPSTREAM.sha256` beside the other records.
2. **`NOTICE.md` recorded an Apache-2.0 obligation this package did not
   discharge.** `INCHI-1-SRC/INCHI_BASE/src/tbb/tbbmalloc_proxy.h` is Intel's
   Apache-2.0 file and is inside `.paths` because `.paths` names
   `INCHI-1-SRC/INCHI_BASE/src`, and a dependent fetching the package received it
   without a copy of the Apache License 2.0. **Closed by the manifest, not by a
   documentation edit**: `.paths` now ships `INCHI-1-SRC/INCHI_API/tbb/LICENSE`,
   which is upstream's own full Apache-2.0 text already in the pinned tree. No
   licence text was authored or copied in from elsewhere, and the TBB header is
   still byte-identical to upstream's and still never compiled or included.
3. **`.github/workflows/verify.yml` had no step that ran `sha256sum -c
   UPSTREAM.sha256`.** **Closed**: the `native` job now runs the integrity step
   first, then the install, then a C gate that compiles against the installed
   `libinchi.a` and the installed headers, then the Debug tests, the
   ReleaseSafe tests and the smoke program.

## 19. Terminated each published fixture answer at its own length

**Condition.** The facade takes `[:0]const u8`, and a sentinel slice stops
*before* its terminator: the zero has to be the byte at `len`.

**Symptom.** **Observed**: `run test inchi-tests 2 pass, 13 fail, 1 crash (16
total)`, and the diff for water read `expected: InChI=1S/H2O/h1H2 ^ ('\x00')`
against `found: InChI=1S/H2O/h1H2 ^ (end of string)`
(`local://foundation-expansion-inchi-known-answer-debug-156.log`). Appending
`"\x00"` and keeping the result's own length put the sentinel one byte past the
answer, so every comparison was against a different string than the published
one — even though C reads both the same way.

**Fix.** `(value ++ "\x00")[0..value.len :0]`. The value is `comptime`, so this
is one static constant per answer: a thin sentinel slice, no copy into
fixed-size storage, and no NUL byte left inside the published string.

**Target bound.** Any C binding that hands a NUL-terminated buffer to a
sentinel-typed Zig API. The general form: a sentinel slice that includes its
terminator names a different string from the one it was meant to name, and the
difference is invisible to any tool that prints both.

**Status: observed.** All sixteen tests pass
(`…-native-Debug-borrowed-atoms-183.log`).

## 20. Borrowed the atom in the tests' element helper instead of copying it

**Condition.** `elementOf` read an atom's element symbol out of the fixed
`elname` field.

**Symptom.** Not a failure — a cost. `inchi_Atom` carries coordinates, a
twenty-entry adjacency list and a twenty-entry stereo list, so a by-value
parameter copied a large struct per atom on every call, and the helper existed
to read six bytes.

**Fix.** `elementOf(atom: *const inchi.Atom) []const u8`, borrowing. Nothing is
copied and nothing is written.

**Target bound.** Any Zig helper over a C struct much larger than the field it
reads.

## 21. Made a refused structure answer with empty arrays, not a cast of null

**Condition.** `GetStructFromStdINCHI` returns `inchi_Ret_ERROR` on a
non-standard identifier *without touching* `*outStruct`
(`inchi_dll.c:2464-2476`: the guard on the `S` at 2472, the return at 2475), so
the struct the facade holds afterwards is the one it zeroed — its atom pointer
is null and its count is zero.

**Symptom.** Not observed as a crash. The cast would have produced a slice whose
pointer is null and whose length is zero, and the only reason that is not
undefined behaviour is that nothing ever dereferences it.

**Fix.** `borrowedArray` returns an empty slice whenever the count is not
positive, before the pointer is cast at all. The non-standard-refusal test
asserts `atoms().len == 0` and `stereo0d().len == 0`, so the guard is compiled
and run rather than merely written.

**Target bound.** Any binding over a C API that signals "nothing" by leaving
its output struct untouched.

## 22. Corrected the consumer's strict-validation expectation

**Condition.** The consumer asserted that `checkIdentifier("InChI=1S/H2O/h1H2",
true)` returns `standard`.

**Symptom.** **Observed**: `InChI=1S/H2O/h1H2: wanted standard, got
conversion_failed`, exit 1
(`…-native-consumer-corrected-210.log`). Upstream's strict check regenerates
the identifier with the layer-keeping options and demands the input back
unchanged (`inchi_dll.c:954-981`), and `/FixedH` and `/RecMet` each clear the
standard flag while the options are parsed (`ichiparm.c:350-364`), so a `1S`
identifier cannot come back unchanged. The library was right; the consumer's
expectation was wrong.

**Fix.** The consumer checks the shallow form, which is the one that classifies
the layout, and the package's own test asserts both: `standard` at
`strict = false`, `conversion_failed` at `strict = true`. Nothing in the
library was loosened to make the consumer pass.

**Status: observed**, `…-native-consumer-validation-corrected-220.log`, exit 0.

## 23. Deleted two tests that pinned incidents rather than behaviour

**Change.** The extension-hash character count and the English wording of
upstream's "protons moved" message are no longer asserted.

**Why.** Both re-pinned a detail rather than a contract: a hash is 48
characters because upstream's buffer is, and a diagnostic is English because
upstream wrote it. The behaviours they stood next to are still asserted — for
the warning path, the status, `isWarning()`, the published identifier and its
equality with the neutral run; for the hashes, the published keys themselves. A
reworded message must not turn a green suite red.

**Status: observed** in the same run as §19.

## 24. Recorded two source boundaries as they came out, and suppressed nothing

**ReleaseSafe, native — RED, and left red.** `compile lib inchi ReleaseSafe
native 3 errors`: `ichiparm.c:2597:64: error: '/*' within block comment` (the
format string `"Timeout per structure: %lu/*.%03lu sec\n"` closes the comment it
sits in) and `ichiparm.c:2718:72` / `:82: error: expansion of date or time
macro is not reproducible` for `__DATE__` and `__TIME__`
(`…-native-ReleaseSafe-corrected-193.log`).

**`check -Dtarget=aarch64-macos-none` — RED.** `ichicano.c:46:10: error:
'sys/timeb.h' file not found` (`…-check-aarch64-macos-none-204.log`).

**`check -Dtarget=wasm32-wasi` — GREEN**, same unconditional include, same
absent-header reading (`…-check-wasm32-wasi-207.log`).

**Decision.** No warning switch, no `-Wno-` flag, no suppression conditional on
the optimisation mode, no edit to upstream's C, and no `continue-on-error` in
`.github/workflows/verify.yml`. Both red gates stay red and are named as
boundaries at the level that owns them: ReleaseSafe is unsupported for this
fork's bundled C core, and `aarch64-macos-none` is blocked by an upstream header
dependency that `COMPILE_ANSI_ONLY` does not guard — it gates the *use*, at
`ichicano.c:95`–`412`, not the `#include` at line 46. CI's `test (ReleaseSafe)`
step will fail for the same reason until that boundary is handled upstream; the
workflow does not hide it.

**Target bound.** Zig 0.16.0's ReleaseSafe C backend; any fork compiling an
unmodified vendored C core under it.

**Superseded in part by §28 and §29.** Both red receipts above stand as they
were observed, and `…-native-ReleaseSafe-corrected-193.log` is not restated as
anything but red: it compiled the file as it stood before the patch. Two clauses
of this entry no longer hold. The first is "no edit to upstream's C": the owner
authorised one narrow exception — a minimal edit to
`INCHI-1-SRC/INCHI_BASE/src/ichiparm.c` and to no other file, covering exactly the
`ichiparm.c:2597` comment and the `__DATE__`/`__TIME__` expansion of the usage
banner in `HelpCommandLineParms` named in this entry, **and it has landed**. The
second is the framing "ReleaseSafe is unsupported for this fork's bundled C
core": that described the tree at these receipts, and §29 records the patched
file building and running in ReleaseSafe, sixteen tests of sixteen, exit 0.
`ichicano.c` and the macOS boundary are outside the authorisation, keep upstream's
bytes, and this entry's account of them is unchanged. Nothing in this entry is
edited to accommodate the patch; the patch has its own entries.

## 25. Shipped upstream's Apache-2.0 text, and then pinned it

**Change.** `.paths` ships `INCHI-1-SRC/INCHI_API/tbb/LICENSE`, closing §18.2.
No upstream licence byte was altered to do it: the file is upstream's own, and
the digest added to `UPSTREAM.sha256` was taken from those bytes.

**The gap that opened when it shipped, and how it closed.** Shipping a file
without hashing it would have left the integrity record covering 108 paths while
the package travelled 109 upstream files — a green gate over a set smaller than
the package. The 109th line was added, and the gate re-run over the whole
record: `sha256sum -c UPSTREAM.sha256` reports 109 records and no failures, exit
0, with `INCHI-1-SRC/INCHI_API/tbb/LICENSE: OK` among them
(`local://foundation-expansion-inchi-immutable-source-complete-legal-109-240.log`).
The earlier 108-record receipts are not restated as covering it.

**The record's own header was corrected with it.** `UPSTREAM.sha256` states 109
records, names `INCHI-1-SRC/INCHI_API/tbb/LICENSE` as one of them with a line
explaining why, and excepts that path from its "deliberately absent" list. The
109 digest lines are unchanged by that, and no upstream licence byte changed at
any point in this sequence.

## 26. Withdrew the licence this fork claimed for its own files

**Change.** `NOTICE.md` no longer says the files this fork wrote are
"contributed under MIT". Nobody authorised this fork to grant them, and the
package is not MIT-only in any case — it now travels an Apache-2.0 file.

**Decision.** They are **unassigned**: no term is stated, and none may be
inferred from the absence. Upstream's terms are untouched — the MIT text, the
sha2 combination condition, stb_sprintf's dual grant, Intel's Apache-2.0 header
and both conflicting upstream copyright lines all stay exactly as they were.

## 27. The materialised package was an argument; now it has receipts

**Condition.** `.paths` is the packaging contract, but every receipt behind this
package's claims was taken either at the repository root or in `consumer/`, which
resolves `.path = ".."` and therefore resolves to this working tree. A dependent
never sees this tree — they see what `.paths` names. Whether all 109 digest lines
have a file behind them in *that* copy had been argued from the manifest.

**Fix.** Documentation only. Three receipts, run by the driver from a build root
outside this repository, are now in the gate table:

| Step | Observed | Receipt |
|---|---|---|
| `zig fetch --global-cache-dir <scratch> <this package path>` | exit 0, and an identity was printed | `…-inchi-external-driver-package-fetch-324.log` |
| `sha256sum -c UPSTREAM.sha256` inside the fetched package | exit 0, **109 of 109 `OK`** | `…-inchi-materialized-package-integrity-333.log` |
| `zig build run` in that package's `consumer/` | exit 0: four identifiers and keys, both checks, `consumer ok` | `…-inchi-materialized-package-consumer-340.log` |

**Every row here is history.** The fetched copy is a snapshot of the tree at
that moment and cannot contain a later edit to `ichiparm.c`, `ichicano.c` or
these documents, so none of the three identities is current. A fresh package
round follows the SDK documents settling.

The third row is the one that closes the gap rather than restating it: inside the
fetched tree, `.path = ".."` resolves to the **filtered copy**, so nothing in that
build could reach this working tree.

**What this does and does not say.** Source closure through `.paths` is now
observed rather than argued: the 105 native files this package ships from the two
upstream-owned source directories, the Apache-2.0 text that travels with the
Intel TBB header, the upstream MIT text, upstream's own `README.md` and the
independent fixture are all inside the copy a dependent receives. It is **not** a
registry or publication proof — the fetch was given a
local directory, nothing was published, pushed or resolved from a registry, and
the printed identity is that directory's rather than a `.url` hash.
`INCHI-1-TEST/` is still deliberately outside `.paths` and nothing here proposes
changing that.

**Debug, and nothing more.** The consumer row ran `zig build run` with the default
`-Doptimize`, i.e. **Debug**. It is not evidence about ReleaseSafe and it does not
repair §24's red row.

**All three receipts are pre-patch.** §29 supersedes all three with receipts over
the patched tree and the record as it now stands.

## 28. A landed `ichiparm.c` patch ends the "upstream is never edited" property

**Condition.** Every native receipt in this package — including all three of
§27's — was taken on a tree whose `INCHI-1-SRC` was byte-identical to upstream at
`11a87982bb518f57ac013f0b258c283655e1ea1d`. That was established separately and
cheaply by `git diff --exit-code 11a87982… -- INCHI-1-SRC LICENSE`, exit 0 with
empty output (`…-inchi-pinned-native-pristine-diff-267.log`), and §18.2 and §25's
accounting of the Apache-2.0 text both rest on it.

**Authorisation.** The owner authorised **one narrow exception**, and only that:
a minimal edit to `INCHI-1-SRC/INCHI_BASE/src/ichiparm.c` and to no other file.
**It has landed in this tree.** Explicitly **not authorised**: any algorithm, ABI,
signature or control-flow change; any warning suppression; any substitution of one
optimisation mode for another. The authorisation also carried obligations — an
explicit patch record, **updated integrity for the changed file**, and **new native
gates** run against the patched tree. Ownership of `ichiparm.c`, that patch record,
`UPSTREAM.sha256`, `UPSTREAM.md`, `NOTICE.md` and `FORK-NOTES.md` rests with
another owner, and nothing in this entry verified any of it. The obligations the
authorisation carried — the patch record, the updated integrity for the changed
file and new native gates over the patched tree — are discharged outside this
entry; **§29** carries the receipts, and no receipt over the patched tree is
claimed in this one.

**Scope, read out of the patched file rather than taken on report.** Two
constructs and nothing else. The comment correction at `ichiparm.c:2597`: the
format string `"Timeout per structure: %lu/*.%03lu sec\n"` lost the `/` and the
`*` became the `.` the sentence meant, inside the `/* … */` block at
`:2594-2599`, so no code path changed. And the `__DATE__`/`__TIME__` arguments of
the usage banner in `HelpCommandLineParms`, in **both** of its branches, replaced
by two string literals defined immediately above the function at `:2707-2708`,
`#define INCHI_BUILD_SOURCE_TAG "v1.07.5"` and `#define INCHI_BUILD_STAMP_WHEN
"(no build timestamp)"`. The banner's format strings are untouched: both
replacements land in exactly the `%s` / `%-s` conversions the macros filled, and
each branch keeps the same conversions and arguments in the same order and of the
same types. The `#ifdef TARGET_EXE_USING_API` branch is at `:2718` with its
arguments at `:2721`; the `#else` branch is at `:2724` with its arguments at
`:2727`. With those two literals in place the banner reads
`… Build (Linux 64-bit) of v1.07.5 (no build timestamp)`, worded so no build-time
date claim exists. §29 quotes the line as a run actually printed it, with this
host's own compiler field in it.

**Three further `__DATE__`/`__TIME__` uses are left exactly as upstream wrote
them** — `OpenFiles`, at `ichiparm.c:2910`, `:2919` and `:2928`. All three sit
inside `#ifndef TARGET_API_LIB`, which opens at `:2887` and which every build here
preprocesses away: `core_macros` at `build.zig:166-169` defines `TARGET_API_LIB`
as `1`, and `build.zig:456` applies it to the one C module. They are named so their
absence from the diagnostics is not read as a claim about the patched file.

**Line numbers moved, and only from `:2699` down.** The pre-existing `/****/`
separator stays at `:2699`; the patch adds **nine** lines at `:2700-2708` — the
explanatory comment and the two `#define`s — so `HelpCommandLineParms` moved from
`:2700` to `:2709` and every line below it shifted by nine. Everything above
`:2699`, `2597` included, is unmoved. The banner and `OpenFiles` numbers quoted
above are **post-patch**; every other `ichiparm.c` line number in this file —
including the `:2712` and `:2718` figures in §24 — is a **pre-patch** citation.

**The record.** `UPSTREAM.sha256` still holds **109 records** and now carries the
**patched** digest for that one file, with upstream's digest preserved in
`UPSTREAM.md` as the written baseline. That is the record's own account; it is
repeated here so a reader who meets a digest that differs from upstream's is not
surprised.

**Status: superseded by §29.** The patched file has since been built and run in
ReleaseSafe — `…-patched-native-releasesafe-durable-374.log`, exit 0, sixteen of
sixteen tests. `…-native-ReleaseSafe-corrected-193.log` is a **pre-patch** red
result and is not restated as anything else.

**Not covered, and not folded in.** `aarch64-macos-none` fails on
`#include <sys/timeb.h>` at `INCHI_BASE/src/ichicano.c:46`: a **different file**,
upstream bytes kept, **no repair authorised**, staying red on its own receipt
(`…-inchi-check-aarch64-macos-none-204.log`). §24's account of it is unchanged.

**Not a precedent.** Every other native file in every fork keeps its upstream
bytes. This exception is not generalised beyond this one file.

**Consequence, stated once so no other file has to be searched for it.** §24 is
superseded in two clauses — "no edit to upstream's C", and the framing "ReleaseSafe
is unsupported for this fork's bundled C core" — and nowhere else in that entry.
§29 carries the receipts that describe the patched tree: Debug and ReleaseSafe
native, the six cross targets, the installed C/IXA surface, the installed usage
banner, the integrity record at the repository root and inside the re-fetched
package, and a consumer built inside that package. Every receipt named above is
**history about the pre-patch tree**: `…-native-ReleaseSafe-corrected-193.log` is
and stays **red**; the 109-record counts it verified described a record whose
`ichiparm.c` line still held upstream's digest; the `git diff --exit-code` green
described an unmodified tree; and `ichiparm.c`'s line numbers moved when the patch
landed, so every citation of that file in this entry is a citation of its
pre-patch text. `README.zig.md` § Verification status says the same in the place a
reader lands on the table.

**Target bound.** Any fork that patches a vendored C file so that a mode compiles:
that mode's red gate stops being a property of upstream's source and becomes a
property of the patch, and every receipt taken before the patch has to be re-read
as pre-patch. Keep those receipts — they are real runs — and do not carry their
numbers forward silently.

## 29. Verified the patched tree, and stopped carrying the pre-patch receipts' numbers

**Condition.** §28 landed the patch and left, by its own terms, every receipt
taken before it describing history. This entry is the receipt set that closes
that gap. Every row below was run on the tree as it stood at the time, after
the patch, and the row-for-row detail is in `README.zig.md`
§ Verification status.

| What | Receipt | Observed |
|---|---|---|
| scoped diff against the pin | `…-authorized-single-native-file-deviation-363.log` | exit 0 with a diff over **one** path, `INCHI-1-SRC/INCHI_BASE/src/ichiparm.c`, in three hunks. It carries no `--exit-code`, so its status says only that the query ran, and it says nothing about paths outside `INCHI-1-SRC` and `LICENSE`: **not** a pristine proof |
| `sha256sum -c UPSTREAM.sha256`, repository root | `…-authorized-patch-integrity-109-364.log` | exit 0, **109 records, 109 `: OK`**, the patched `ichiparm.c` line among them |
| native Debug: test, smoke, install | `…-authorized-patch-native-debug-365.log` | exit 0, `Build Summary: 11/11 steps succeeded; 16/16 tests passed`, `smoke ok`, `install inchi success` |
| six cross targets | `…-authorized-patch-cross-…-367.log` through `…-372.log` | five green at 6/6 steps; `aarch64-macos-none` **red**, exit 1, `ichicano.c:46:10: error: 'sys/timeb.h' file not found`, `Build Summary: 2/6 steps succeeded (1 failed)` |
| native consumer | `…-authorized-patch-consumer-373.log` | exit 0, four identifiers and keys, both checks, `consumer ok`, `Build Summary: 6/6 steps succeeded` |
| native ReleaseSafe: test and smoke | `…-patched-native-releasesafe-durable-374.log` | exit 0, `Build Summary: 9/9 steps succeeded; 16/16 tests passed`, `run test inchi-tests 16 pass (16 total) 244ms`, `smoke ok` |
| filtered package fetch | `…-current-filtered-package-fetch-382.log` | exit 0, and an identity was printed — a fetch of a **local directory**, not a registry resolution. **HISTORICAL**: that identity covers a tree whose `ichicano.c` and documents have since changed, so it is not quoted as current and is not compared against any later one |
| installed usage banner | `…-patched-installed-banner-compile-384.log`, `…-banner-smoke-385.log` | exit 0 twice: the C program's own line `GetINCHI(empty): deterministic pinned-source help stamp observed`, then the banner read back out of the installed patched archive |
| installed C/IXA surface | `…-patched-installed-C-IXA-compile-386.log`, `…-C-IXA-smoke-387.log` | exit 0; no diagnostics at compile, then `installed InChI ethanol/key and IXA water agree with PubChem` |
| filtered package integrity | `…-current-filtered-package-integrity-388.log` | exit 0, **109 of 109 `OK`** inside the `.paths`-filtered copy |
| filtered package consumer | `…-current-filtered-package-consumer-389.log` | exit 0, `consumer ok`, `Build Summary: 6/6 steps succeeded`, Debug; `.path = ".."` resolved to the filtered copy, so the library came out of the package and not out of a checkout |

**What the banner reads, quoted rather than paraphrased.** The first two lines
the `-385` run printed, each ending in the single trailing space the `%s %-s`
conversion leaves:

```
InChI version 1, Software 1.07.5 (API Library) 
Linux 64-bit Build (gcc Clang 21.1.0) of v1.07.5 (no build timestamp) 
```

`Linux 64-bit` and `gcc Clang 21.1.0` are **that host's** `INCHI_BUILD_PLATFORM`
and `INCHI_BUILD_COMPILER`, reported by whichever compiler built that archive.
They are outside the patch's scope and would read differently on another
machine. `v1.07.5` and `(no build timestamp)` are the two literals this patch
substituted, in the very positions `__DATE__` and `__TIME__` filled, so the text
carries no build-time date claim at all.

**What did not change.** No algorithm, ABI, signature, allocator, option or
control-flow behaviour; no diagnostic suppressed, filtered or downgraded; no
optimisation mode substituted for another. Three further `__DATE__`/`__TIME__`
uses in `OpenFiles` remain untouched upstream text that every build here
preprocesses away (§28). `ichicano.c` kept upstream's bytes through this entry,
no repair was authorised for it here, and `aarch64-macos-none` stayed red on its
own receipt. §30 is what changed all three of those.

**Every row above is history now, in the same way.** They were taken after the
`ichiparm.c` patch and before the `ichicano.c` one, and §32 has since moved the
guard again, so §30's matrix and §32's entry are the current statements about
this file. §32 also names the two later waves that ran on the arrangement it
settled on.

**Not claimed.** No CI was executed and no workflow result is reported here. The
fetch was given a local directory: nothing was published, pushed, uploaded or
resolved from a registry, and the identity it printed is that directory's rather
than a `.url` hash. `zig build -fsys=inchi` is still unrun. No legal grant is
asserted for any of this fork's own files; they stay unassigned (§26).

**Pre-patch receipts, kept as history and carried no further.** `-193` (red,
ReleaseSafe), `-240` (109 records, over a record whose `ichiparm.c` line still
held upstream's digest), `-267` (`git diff --exit-code` green on an unmodified
tree), `-324` (the pre-patch fetch identity), `-333` and `-340` (the same record
and a consumer inside the **pre-patch** fetched copy — a snapshot, which cannot
contain a later edit), and the pre-patch Debug, install, cross, consumer and
installed-C rows `-183`, `-201`, `-202` … `-207`, `-209`, `-220`, `-225`. Each is
a real run and none is withdrawn; each describes the file state before the patch.
Since §30 they are additionally history for the `ichicano.c` line: every one of
them verified a digest this package no longer names.

**Target bound.** Any fork that patches a vendored C file. Once the patch lands,
the receipts that matter are the ones taken after it; the mode's red gate stops
being a property of upstream's source and becomes a property of the patch, and
the earlier counts must not be carried forward silently.

## 30. `ichicano.c`'s unused include is now guarded, and the matrix gate reaches 53 platforms

**Condition.** The six-target `check` matrix was the whole cross gate, and
`aarch64-macos-none` had been red on it since §28, with a named cause and no
authorised repair. The gate is now the published 53-platform `cross-test`
matrix, and macOS is two cells of it rather than one.

**The change.** Two lines, and they are the whole of it. In
`INCHI-1-SRC/INCHI_BASE/src/ichicano.c`, `#include <sys/timeb.h>` is now inside
`#ifndef COMPILE_ANSI_ONLY`:

```c
#include <time.h>
#ifndef COMPILE_ANSI_ONLY
#include <sys/timeb.h>
#endif
#include <limits.h>
```

That is where the guard **first landed**. §32 moves it, because the guard also
has to sit below `#include "mode.h"`; the three lines are unchanged, only their
position is.

Upstream's 107394 bytes became 107427. The 33 are exactly the two directive
lines the patch adds — `#ifndef COMPILE_ANSI_ONLY\n` and `#endif\n` — and the
later relocation in §32 adds none, being a move.

**Why it exists, with the receipt that named it.** §29's cross row is the
observed failure: `…-authorized-patch-cross-…-367.log` through `…-372.log`,
`aarch64-macos-none` exit 1,
`ichicano.c:46:10: error: 'sys/timeb.h' file not found`,
`Build Summary: 2/6 steps succeeded (1 failed)`, the other five green at 6/6.
The header is not missing by accident on this compiler, and the reason is read
out of it rather than guessed:
`std.zig.LibCDirs.detectFromBuilding` (`lib/std/zig/LibCDirs.zig:169-181`) gives
every target whose `Os.Tag.isDarwin()` is true — the list at
`lib/std/Target.zig:79-86` names `.maccatalyst` and `.macos` in the same arm —
exactly one libc include directory,
`lib/libc/include/any-darwin-any`, and that directory has no `sys/timeb.h`.
`generic-openbsd` and all ten `*-openbsd-*` architecture directories have none
either, while `generic-glibc`, `generic-musl`, `generic-freebsd`,
`generic-netbsd` and `any-windows-any` have it. `wasm-wasi-musl` does not, but a
wasi target's four-directory search path also includes `generic-musl`, which
does — which is why `wasm32-wasi` compiled and macOS did not. So the same single
line is the whole cause for the four Apple cells and the nine OpenBSD cells:
**thirteen of the fifty-three**.

**The same question, asked of the compiler instead of the directory**
(`local://foundation-cross-test-timeb-header-availability.json`, seven
`zig cc -E -H -include sys/timeb.h` probes, exit code and diagnostic recorded
per target). Present on `x86_64-linux-gnu`, `x86_64-linux-musl`,
`x86_64-netbsd` and `wasm32-wasi` with no diagnostic; present on
`aarch64-freebsd` with upstream's own `#warning "this file includes
<sys/timeb.h> which is deprecated"`; **absent on `aarch64-macos` and
`x86_64-openbsd`**, both exit 1. So the absent pair is macOS and OpenBSD, WASI
is not in it, and a target with no libc include directory of its own is not
therefore a target without the header.

**Why this guard and not a portability macro.** The guard is the condition the
guarded code is already behind, in the same file. In pre-patch numbering,
`ichicano.c:95` opens `#ifdef COMPILE_ANSI_ONLY` and `ichicano.c:325` opens the
`#else` that closes at `:412`. Both — and only — readers of the header's
declarations are inside that `#else`: `InchiTimeGet` at pre-patch 332-335 and
`bInchiTimeIsOver` at pre-patch 395-402. Those five lines are every occurrence
of `struct _timeb` and `_ftime` in the file. `ichitime.h:56` — which declares
`inchiTime` for the same file — already carries the same include commented out
under the same macro, so this is upstream's own arrangement and the guard only
makes the C file state what its own header already states.

**What did not change.** No declaration, expression, macro or token in any
configuration: with `COMPILE_ANSI_ONLY` undefined the preprocessed output is
upstream's, and with it defined — which is how `core_macros`
(`build.zig:166-169`) builds every translation unit in this package, matching
upstream's own `CMakeLists.txt:154-158` and `gcc/makefile:129` — the region the
guard wraps was already excluded. No canonicalisation step, ABI, allocator,
option, default, flag or build mode is touched, no source file is removed, no
diagnostic is suppressed, and `module.c`-style loader or filesystem substitutes
were not introduced anywhere.

**Disclosure and integrity, in the same change.** `UPSTREAM.md` § The two
patched source files writes the patch out in full against upstream's digest
`5c031a2b441dc08509f75fe22e4b6ecddf285ada625b4a69cf77d2920d42f891` and states
the line-number shift; `NOTICE.md` § What this fork changed names it as the
second patched path; `UPSTREAM.sha256` names both paths in its header. Its
`ichicano.c` record was re-derived from the patched file's own bytes as
`8e9950da10efff7afb581138c77c471ed7c0fb66d1cac26679493c9aad3f6bfb`, **which is
now superseded**: that digest belongs to the first placement of the guard, and
§32 records what replaced it. The record count is unchanged at 109: this fork
patched two files upstream ships, it did not add, remove or rename one.

**Observed since this entry was written, and how far it goes.** The full
53-platform `cross-test` run is done: 53 cells, `pass 20`, `fail 0`,
`build_only 33`, harness `exit_code: 0`
(`local://foundation-cross-test-matrix-inchi.json`, run
`20261002-040235-43019-14341`, generated `2026-10-02T04:02:35Z`). The 20
executed cells ran 16 tests each — **320 test executions** — and the other 33
compiled only, every one exit 0. **No BSD, macOS, Mac Catalyst, Windows or WASI
binary was executed anywhere in it**; those cells are `build_only` and are
reported as compiles. `bash -n cross-test.profile.sh`, `cross-test --list` and
`cross-test --no-profile --list` all exited 0, the last two listing the same 53
targets. `sha256sum -c UPSTREAM.sha256` over the current record **still has not
been run**, and §32 has since moved the guard, so the matrix above compiled the
first placement: this entry is current evidence for §30's arrangement and
history for §32's. `aarch64-macos-none` has not itself been re-run and stays red
on its own receipt, superseded for the macOS family by the four Apple cells that
compiled, not by itself.

**Target bound.** Any C file that includes a header its own preprocessor guard
has already made dead, on any target whose libc dropped that header. The
failure surfaces on the widest matrix first and on the narrow one last: the
six-target `check` saw it on exactly one target, and the 53-cell matrix covers
four Apple and nine OpenBSD cells — **thirteen**, not eleven.

## 31. A settings-only `cross-test.profile.sh`, in both this package and LMDB

**Condition.** The matrix gate is run by `~/.local/bin/cross-test`, which
discovers `./cross-test.profile.sh` at the project root and otherwise keeps its
own defaults. Neither package had one, so the gate was driven by defaults
nobody in the package had chosen, and the package could not say anything about
how it wanted to be measured.

**The change.** Two new files, one per package, and nothing else in either
build graph. Each is ordinary Bash variable definitions and comments:

```bash
CROSS_BUILD_STEP=test
```

is the single assignment. Everything else is a comment saying what is
deliberately absent and why:

* no `CROSS_MATRIX` and no `TARGETS`, so the published 53-platform table stays
  whole — including, for LMDB, the platforms `refuseTarget` refuses and for
  both packages the platforms with no detected runner;
* no `cross_build_command`, `cross_artifact`, `cross_run_command` or
  `cross_count_tests`, so `cross-test` keeps its own native/QEMU/Wine/Wasmtime
  detection and keeps reporting a runner-less target as build-only rather than
  as a pass;
* no `CROSS_BUILD_ARGS`, so the gate is the ordinary `zig build test` in each
  package's own default Debug mode, with no `-Dtarget`, no `-Doptimize` and no
  added flag;
* no host path and no resource limit, because the package does not know the
  machine it will be measured on and `cross-test`'s own host policy
  (`lib/host-scratch.sh`) has already placed scratch and cache before it reads
  any name in the file.

Both files are listed in their package's `build.zig.zon` `.paths`, because they
are Bash that `cross-test` sources and not documentation, and a dependent should
receive the same gate the tree was measured with. Both are recorded in
`NOTICE.md` among this fork's own files, which carry no licence asserted.

**What did not change.** No step, no target, no flag and no source file in
either build graph. Both packages already exposed `test` as real `addTest` +
`addRunArtifact` work for the selected target — LMDB at `build.zig:788` and
InChI at `build.zig:246` — so the profile configures what was already there
and adds no work of its own. The six-target `check` matrices are untouched and
still compile what they compiled before.

**Not claimed, then observed.** As written this entry reported no gate at all.
For this package three have since run, all exit 0: `bash -n
cross-test.profile.sh` (`local://foundation-cross-test-profile-inchi-syntax.log`),
`cross-test --list` (53 targets, `…-profile-inchi-list_profile.log`) and
`cross-test --no-profile --list` (**the same 53 targets**,
`…-profile-inchi-list_no_profile.log`). The profile therefore narrows nothing,
which is what §30's matrix needed it not to do. The full matrix run is recorded
in §30 for the placement that entry settled on, and in §33 for the one this
package now ships. LMDB's own profile checks are not this package's receipts and
are not restated here.

## 32. The §30 guard moved below `#include "mode.h"`, because `mode.h` is what defines the macro

**Condition.** §30 guarded the include with `COMPILE_ANSI_ONLY` and left the
guard where upstream's include stood — above `#include "mode.h"`. That works in
this package only because the build *also* passes `-DCOMPILE_ANSI_ONLY=1` on
the command line. The guard reads a macro the file has not yet defined for
itself, and the reason it appeared to work was an argument this package
supplies rather than a property of the source.

**The change.** A move, not an edit: the same three lines, relocated inside
`INCHI-1-SRC/INCHI_BASE/src/ichicano.c` to sit immediately after
`#include "mode.h"` and immediately before `#include "ichicano.h"`, at
`ichicano.c:49-51`:

```c
#include <limits.h>

#include "mode.h"
#ifndef COMPILE_ANSI_ONLY
#include <sys/timeb.h>
#endif
#include "ichicano.h"
```

No comment was added, no line's text changed, and the file is **107427 bytes
and 2744 lines** — byte for byte §30's file, because a move adds no bytes and
removes none. So no line number shifted *between the two placements* either:
everything at or after `:53` reads exactly as §30 left it, and the three guard
lines changed only their position inside `:45-52` — `:46-48` in §30's
arrangement, `:49-51` in this one, immediately after `#include "mode.h"`,
which reads at `:48` here and at `:51` there. What did move is every citation
**measured against upstream**: the two inserted directive lines sit above `:50`,
so from `:50` to the end of the file this package cites everything two lines
higher than upstream does. On that basis the readers of the header's
declarations are at `:97`, the `#else` at `:327` and its `#endif` at `:414`,
with `struct _timeb` and `_ftime` at `:334-335` and `:397`/`:402`, against
upstream's `:95`, `:325`, `:412`, `:332-335` and `:395-402`; the clock
constants `FullMaxClock` and `HalfMaxClock` are at `:126-127`; and the guard is
at `:49-51`, after `mode.h` at `:48`.

**Why `mode.h` and not the command line.** `mode.h:197-201` is upstream's own
definition:

```c
#if ( !defined(_MSC_VER) || defined(TARGET_API_LIB) || defined(TARGET_EXE_USING_API))
#ifndef COMPILE_ANSI_ONLY
#define COMPILE_ANSI_ONLY
#endif
#endif
```

So for every configuration this package builds, and for every non-MSVC build
upstream ships, the macro is defined by that header. Put the guard below it and
the guard becomes **upstream's own condition, self-satisfied inside the file**;
put it above and it is a bet on a `-D`. Under MSVC, where the macro is left
undefined, the include is taken exactly as upstream wrote it — the non-ANSI
build §30 was written to protect still gets its header.

**What did not change.** No chemistry, algorithm, ABI, signature, allocator,
canonicalisation step, option, default, flag or build mode, on any target, in
any optimisation mode. The same three preprocessor lines are present; only the
file offset of the block differs, and the block's *meaning* is unchanged for
every configuration this package compiles. No source file is removed, no
diagnostic is suppressed, no substitute header or loader is introduced, and
the `-DCOMPILE_ANSI_ONLY=1` this package already passed is left exactly where
it was — the move makes the source correct on its own, it does not withdraw the
argument.

**Provenance and integrity.** `UPSTREAM.sha256`'s `ichicano.c` record is
re-derived from this file's own bytes as
`9a0998a3a41f62508e755d9411bf3c78b2b7b1ae63edcea7a40c55307130d98b`;
§30's `8e9950da…` is the superseded digest of the first placement and is
retained only as history. Upstream's own digest for the path is unchanged at
`5c031a2b441dc08509f75fe22e4b6ecddf285ada625b4a69cf77d2920d42f891` — re-derived
by deleting the two directive lines and restoring the include at upstream's own
position 46, which hashes to exactly that value and measures **107394 bytes**
(upstream's 107395 was off by one; §32 corrects it). The record count is
unchanged at 109. `UPSTREAM.md` and `NOTICE.md` carry the placement, the line
map and the corrected `ichitime.h:56` citation.

**Observed since this entry was written, on this arrangement.** Two waves ran
after the move and both are green. The six-target `check` baseline is **6 of 6**,
exit 0 on every cell, `Build Summary: 6/6 steps succeeded` on every cell,
between `2026-10-02T06:22:14Z` and `2026-10-02T06:22:49Z` — including
`aarch64-macos-none`, the cell §29 records as red, which is green at its own
target for the first time in this package's history
(`local://foundation-cross-test-baseline-before-sdk-corrections.json`, per-cell
`local://foundation-cross-test-baseline-inchi-<target>.log`). The stable native
wave is green in both modes on the same tree: `zig build test smoke install
-Doptimize=Debug -j8 --summary all --color off`, exit 0, 1.152 s, `Build
Summary: 11/11 steps succeeded; 16/16 tests passed`; `zig build test smoke
-Doptimize=ReleaseSafe -j8 --summary all --color off`, exit 0, 18.584 s,
`Build Summary: 9/9 steps succeeded; 16/16 tests passed`; and `zig build run`
in `consumer/`, exit 0, 0.968 s, `Build Summary: 6/6 steps succeeded`
(`local://foundation-cross-test-stable-native.json`).

**What those runs do not change.** No declaration, algorithm, expression or ABI
moved, and none of them was re-derived by them: they are builds and tests of
the behaviour §30 and §32 already described, over a file whose only difference
is where three preprocessor lines sit.

**Not claimed.** §30's 53-cell matrix had **not** been re-run over this
arrangement when this entry was written, and no result was claimed for it here;
§33 has since run it over the arrangement §32 settled on, which makes §30's
run history for it. The whole-record `sha256sum -c UPSTREAM.sha256` over this
digest is **not asserted by this package either**: the line was re-derived from
the file's own bytes, every integrity receipt above is history for it, and the
current replay is the driver's to run and to record beside this package rather
than in it. A fresh filtered package round is the driver's in the same way, and
`zig build -fsys=inchi` is unrun. **No CI was executed for this entry, no
workflow result is reported here, and no SDK runner outside this workspace ran
a foreign binary.**

**Target bound.** Any vendored C file whose own portability macro is defined by
a header it includes *after* the site it wants to test. The narrow six-target
matrix cannot see the difference — both placements give the same result under a
`-D` — so only reading `mode.h` finds it, and no target in either matrix ever
did.

## 33. Re-ran the 53-cell matrix over the arrangement §32 settled, and handed the package round to the ledger

**Condition.** §32 moved the guard below `#include "mode.h"` and left three
things open over the arrangement it settled on: the 53-cell `cross-test`
matrix, the whole-record `sha256sum -c UPSTREAM.sha256` replay, and a fresh
filtered package round. The first is a build gate this package can be measured
by. The second and third are the driver's, and the third is a function of these
very documents.

**The matrix, re-run on the shipped arrangement.** `cross-test`, run
`20261002-071259-33035-20483`, generated `2026-10-02T07:12:59Z`, Zig 0.16.0,
`mode: zig-build`, `target_jobs: 2`, `jobs_per_build: 4`,
`build_timeout_seconds: 3600`, `run_timeout_seconds: 300`,
`bookkeeping_failure: false`, harness `exit_code: 0`, `target_count: 53`,
counts `pass 20`, `fail 0`, `build_only 33`, `partial 0`. All 53 cells compiled
the file as it stood at `2026-10-02T07:12:59Z`; **§38** is what says why that is
not the same statement as "the file as it ships". The 20 cells with a runner
each executed the then-full 16-test suite — 320 tests run, every one
`Build Summary: 6/6 steps succeeded; 16/16 tests passed`,
`reason: tests_complete`, `command_exit: 0` — and the other 33 stayed
`build_only` with `reason: runtime_unavailable`, which is compile coverage and
is never counted as a pass. **No foreign BSD, macOS, Mac
Catalyst, Windows or WASI binary was executed in any cell.** Receipt
`local://foundation-cross-test-final-current-inchi.json`, per-cell
`local://foundation-cross-test-final-current-inchi-<target>.log`.

**The earlier matrix is history, and stays.** Run
`20261002-040235-43019-14341` (`local://foundation-cross-test-matrix-inchi.json`)
carried the same counts and the same 320 executed tests, and compiled §30's
placement of the guard. It is not withdrawn, none of its numbers is carried
forward, and §30's and §32's own text already say which tree it describes.

**The baseline, re-run in the workspace's 48-cell round.** The six explicit
`-Dtarget=` cells are **6 of 6 green** in
`local://foundation-cross-test-final-baseline.json`, each `Build Summary: 6/6
steps succeeded`, exit 0, between `2026-10-02T07:23:30.237Z` and
`2026-10-02T07:23:32.431Z`, `complete: true`, `unrun_cells: []`, per-cell
`local://foundation-cross-test-final-baseline-inchi-<target>.log`. The §32
native wave is unaffected by that round: 16/16 in Debug, 16/16 in ReleaseSafe,
plus smoke, install and consumer, all exit 0. **Superseded as current by §38:**
those sixteen are the tests the file declared when the wave ran, and the file
as it ships declares twenty-two.

**What this entry does not change.** No source byte, declaration, algorithm,
ABI, line number or digest moved with any of these runs. The deviation is the
one `NOTICE.md` itemises and `UPSTREAM.md` writes out in full: the
`ichiparm.c` comment and banner patch, and the `ichicano.c` include relocated
below `mode.h` and inside `#ifndef COMPILE_ANSI_ONLY`, which leaves the
`#ifdef` at `:97`, the `#else` at `:327` and its `#endif` at `:414`, with
`FullMaxClock` and `HalfMaxClock` at `:126-127`.

**Two closures handed over rather than claimed.** The whole-record replay of
`sha256sum -c UPSTREAM.sha256` over the re-derived `ichicano.c` line, and the
final filtered fetch with its source, fetched-integrity and fetched-consumer
checks over the settled documents, are the driver's to run and to record, and
they are recorded outside this package: in the root ledger's `FORKS.json`, under
`cross_test_wave` and `cross_test_wave.materialized_packages.inchi`, and in
`local://foundation-cross-test-package-regression.json`. This file states no
result and no identity for either, because a package hash over a copy of these
documents cannot be the identity of the package they are written into.

**Still not claimed.** `zig build -fsys=inchi` has not been run in this
workspace and is claimed by nothing above. No CI was executed for this entry
and no workflow result is reported here.

**Target bound.** Unchanged from §32: any vendored C file whose own
portability macro is defined by a header it includes after the site it wants to
test.

## 34. Clarified the native disclosure without changing executable input

Three existing lines in the inserted `ichiparm.c` comment now name the
separate `ichicano.c` portability edit and the actual "The two patched source
files" section. No directive, expression, literal or source-line count
changes. The current file is 111263 bytes with SHA-256
`74302e26597450060b8341a569f4fd8a07813aadce1f05e9b3507c34980cdd3a`.
`UPSTREAM.sha256` keeps the same 109 paths and updates that one data record;
the earlier 111277-byte comment state stays historical. Fresh native/API and
fetched-package proof is driver-owned outside these identity inputs.

## 35. The consumer step asks whether this host can execute the target, and QEMU without libc runtimes installs only

**Condition.** §14 made the nested `zig build` receive the system-integration
choice. The step still chose `run` or `install` from `Target.Query.isNative()`,
which answers a question nobody asked. `isNative()`
(`lib/std/Target/Query.zig:396-398`) is `isNativeTriple() and ofmt == null`, and
`isNativeTriple()` (`:392-394`) is `isNativeCpu() and isNativeOs() and
isNativeAbi()`, of which `isNativeAbi()` (`:388-390`) is `os_tag == null and
abi == null`. Writing a triple names all three, so `-Dtarget=x86_64-linux-gnu`
on an x86_64 Linux GNU host was never "native" and the step took the `install`
branch — built the consumer, printed nothing, and exited 0, on the exact
invocation whose point is to run it. The predicate describes how the target was
spelled; the question is whether the host can execute it.

**Symptom, observed.** `zig build consumer -Dtarget=x86_64-linux-gnu`, before
this change: `Build Summary: 2/2 steps succeeded`, `consumer package success
10s`, exit 0, and **no program output at all** — no `inchi consumer` banner, no
identifier, no `consumer ok`. The step succeeded at being a build step. This is
an observation the parent made in the session; **no `local://` receipt file
exists for it**, so the argv and the output lines are quoted here and no receipt
is named.

**Decision.** `hostCanExecute` (`build.zig:632-672`) asks
`std.zig.system.getExternalExecutor` (`lib/std/zig/system.zig:42`), which is
the function `std.Build.Step.Run` itself calls about the artifact it is about to
spawn (`lib/std/Build/Step/Run.zig:1268`), and `runConsumer`
(`build.zig:566`) passes its answer as the nested step. Both option fields `Run`
fills in from that artifact are filled in here from the same facts:
`.link_libc = true`, because the consumer executable links libc through the
library module it imports and `Compile` computes `is_linking_libc` over every
module in the graph (`lib/std/Build/Step/Compile.zig:1054-1057`), not just the
root one; and `.qemu_fixes_dl = candidate.isGnuLibC() and
b.libc_runtimes_dir != null`. One target serves both roles, because
`rootModuleTarget` (`lib/std/Build/Step/Compile.zig:2067-2070`) *is* the root
module's resolved target — the one `getExternalExecutor` is handed.

`Run` allows every executor in the predicate and then gates the answer on this
build's own switches (`lib/std/Build/Step/Run.zig:1277` wine, `:1291` qemu,
`:1317` darling, `:1325` wasmtime). Carrying those same switches in `allow_*`
asks the identical question and answers it without a second gate, which is why
the two cannot disagree.
`-fwasmtime`, `-fqemu`, `-fwine` and `-fdarling` are the build runner's own
options (`lib/compiler/build_runner.zig:388-407`, exposed as
`b.enable_wasmtime` and friends at `lib/std/Build.zig:71-79`), each naming a
separate program whose presence on `PATH` this script cannot know, and each is
forwarded to the nested build together with `--libc-runtimes`
(`lib/compiler/build_runner.zig:323-325`) so the decision and the nested run
agree on one executor. `-frosetta` is forwarded for fidelity and never gates
anything: `std.Build.Step.Run` reads `enable_rosetta` nowhere, and on an Apple
Silicon host it is the operating system that runs the binary rather than a
program this build would have to find.

**The QEMU second gate.** QEMU is the one executor where the predicate and
`Run`'s gate disagree, and the `.qemu` arm
(`lib/std/Build/Step/Run.zig:1290-1314`) is where it shows. For a
cross libc target, `Run` appends `-L <runtime triple>` (`:1294-1308`) and, with
`b.libc_runtimes_dir` unset, calls `failForeign` on `--libc-runtimes` (`:1310`)
— the step **fails**, it does not skip the run and it does not install.
`qemu_fixes_dl` cannot carry that: `getExternalExecutor` enters the QEMU arm
for a foreign CPU on `!cpu_ok` alone (`lib/std/zig/system.zig:95`), whatever
that option says, so the returned executor is `.qemu` in exactly the case the
option stops describing. `.qemu` therefore answers
`!candidate.isGnuLibC() or b.libc_runtimes_dir != null` (`build.zig:664`), which
is `Run`'s own `need_cross_libc` half for this artifact
(`lib/std/Build/Step/Run.zig:1264-1266`): the musl half additionally asks for
`exe.linkage == .dynamic`, and `consumer/` builds with `b.addExecutable` and no
linkage, so that field is null there and the half never contributes. The two
now test the same fact.

**What this changes, and where it does not.** An explicitly spelled native
triple now runs. A foreign target whose executor was enabled runs under it. A
target with no executor on this host, and a foreign GNU libc target under
`-fqemu` with no `--libc-runtimes` directory, build and install — compile
evidence, and `build.zig:546-547` says so in the same words. `isNative()` is not
removed from the file: `build.zig:276` still uses it, correctly, to choose
between the six-target `check` matrix and one selected target, which is a
question about *this build's* matrix and not about executability.

**After, observed.** The same `zig build consumer -Dtarget=x86_64-linux-gnu`
printed `inchi consumer`, `water = InChI=1S/H2O/h1H2
XLYOFNOQVPJJNP-UHFFFAOYSA-N`, `methane = InChI=1S/CH4/h1H4
VNWKTOKETHGBQD-UHFFFAOYSA-N`, `ethanol = InChI=1S/C2H6O/c1-2-3/h3H,2H2,1H3
LFQSCWFLJHTTHZ-UHFFFAOYSA-N`, `heavy water = InChI=1S/H2O/h1H2/i/hD2
XLYOFNOQVPJJNP-ZSJDYOACSA-N`, `check XLYOFNOQVPJJNP-UHFFFAOYSA-N = standard`,
`check InChI=1S/H2O/h1H2 = standard`, `consumer ok`, `Build Summary: 2/2 steps
succeeded`, exit 0 — the four PubChem answers built through `dep.module("inchi")`
from outside the package. Those are the same published identifiers and keys
`consumer/src/main.zig:18-24` pins, and they are not new answers: this
package's consumer has been run as its own `cd consumer && zig build run` in
every wave §33 records. What is new is only that this package's own `consumer`
step, from the package root and with an explicit target, reaches them at all.
Again: **no `local://` receipt file exists for this run.**

**Not observed, and not claimed.** The QEMU branch is **unexercised**. No
foreign-architecture consumer has been executed in this workspace, so the
`.qemu` answer, the `--libc-runtimes` refusal, and the `-fwasmtime`,
`-fwine` and `-fdarling` arms rest on the pinned `lib/std` sources cited above
and on nothing that ran. The mechanism is `SOURCE-CONFIRMED`; the behaviour is
`PENDING-VERIFICATION`. No fresh native wave, six-target `check` baseline,
53-cell matrix or package round has been run over this change, so every receipt
§33 names remains current for the arrangement that entry describes and states
nothing about this one. `zig build -fsys=inchi` is still unrun, and §14's
forwarding of that choice is unchanged by this entry.

**Target bound.** Any build step that has to decide between *running* a nested
program and *building* it, where the decision can be taken by asking the
artifact's own spawn logic rather than by a hand-written test for the target.
The bound is the artifact's shape: a consumer that links libc, builds with no
linkage, and runs from its own package. A consumer that declared a linkage, or
that used a libc `Run` classifies differently, would need its own
`need_cross_libc`.

## Gates

The current gate table, with a receipt for every row, is in
[`README.zig.md`](README.zig.md) § Verification status. It is the only place
this package states one; the entries above carry their own receipts for the
moment each claim was made.

§29 is the summary of which of those receipts are still current and which are
pre-patch history, and §30 moved the `ichiparm.c`-era receipts one step further
into history: none of them verified the `ichicano.c` line this package now
names. §31 adds no gate result of its own. §32 moves the §30 guard and leaves
every receipt above it one step further into history, and then records the two
waves that ran on the arrangement it settled on: the six-target `check`
baseline, green in all six cells, and the stable native wave, 16/16 in Debug
and 16/16 in ReleaseSafe plus smoke, install and consumer. §33 then re-runs the
53-cell matrix over that same arrangement and names the 48-cell round that
repeats the six-target baseline. The gate table names all three, and names the
two closures this package hands to the driver instead of claiming them.

§34 changes three lines of disclosure prose and §35 changes the predicate the
`consumer` step runs on. Between them they move **no** receipt into history:
§34's change is inside a C comment, and §35's is in `build.zig`, which
`UPSTREAM.sha256:87-90` records as deliberately absent from the integrity
record, so neither moved a pinned source byte. `build.zig` *is* configured by
every one of those waves, so the new function runs during configuration in all
of them; what none of them did is **invoke** the `consumer` step — the stable
native wave reached the consumer by `cd consumer && zig build run`, which does
not go through this predicate at all. What §35 adds is therefore two observed
`consumer`-step runs and **no receipt file for either**: the `argv` and the
output lines are quoted in §35 and nothing else. Its QEMU branch, its
foreign-architecture answers and every fresh native, baseline, matrix and
package wave over it are unrun here and are named `PENDING-VERIFICATION` there,
not green. The gate table is where the driver records that closure; this file
states no result for it.

## Zig API contract alignment — 2026-10-03

**Condition.** Native output allocations have one owner. Warning flags have
two distinct dimensions and do not by themselves equal the return status.

**Fix.** State Output/Structure/AuxInfo ownership, alias copies, borrowed
views and matching releases. Correct warning dimensions and bit-definition
citations. Document reachable construction enums and raw fields, atom-symbol
termination and interior-NUL duties, bond counts, input lifetimes, option
handling, diagnostic emptiness and unknown key-code information loss. Replace
the module fragment with a complete executable sequence.

**Verification and bound.** Zig 0.16.0, native Linux x86-64: install,
Debug/ReleaseSafe tests, smoke, package consumer and module example pass.
The published compile-only `check` matrix passes. No new system-provider or
foreign runtime result is claimed. Native bytes and pins are unchanged.

## 36. Standalone Nix packaging, devenv as the canonical shell, and an owner-authorized fork licence

**Condition.** Three problems. The package had no way to be consumed off this
workspace: no derivation, no flake, no development shell, and nothing that
pinned a nixpkgs. The installed closure was a bare archive and two headers —
no link metadata, no licence text beside them. And this fork's own files had no
licence at all, because nobody had authorised this fork to grant them.

**Fix, in five parts.**

* **`package.nix` is one source-only derivation**: an ordinary uncurried
  function over `lib`, `stdenv`, `zig` and an optional `linkage` defaulting to
  `static`, returning one derivation. Both entry points call it identically,
  `pkgs.callPackage ./package.nix { zig = pkgs.zig_0_16; inherit linkage; }`, so
  the flake and the development shell cannot describe two different builds. It
  reads the version out of `INCHI-1-SRC/INCHI_BASE/src/bcf_s.h:52` rather than
  repeating it and throws rather than guessing if that line is gone; it names
  its inputs as an explicit `lib.fileset`, which also excludes `.git`,
  `.zig-cache`, `zig-out`, `zig-pkg`, `.devenv*`, `.direnv` and `result*` from
  the source hash; and it installs only, invoking
  `zig build install -j"…NIX_BUILD_CORES…" -Doptimize=ReleaseSafe -Dcpu=baseline
  -Dlinkage=<variant> --prefix "$out"` exactly once, with both Zig caches
  exported under the Nix-provided `TMPDIR`. `dontInstall` is deliberately not
  set. `linkage` takes `static` or `dynamic` — the `build.zig` option values.
  Nothing else is owned here: the source list, C flags, header configuration
  and the installation of the library, headers, `.pc` and licence material all
  belong to `build.zig`.
* **The variants are made by the entry points.** `flake.nix` exposes
  `packages.<system>.static` and `packages.<system>.shared` (mapping to
  `linkage = "static"` and `"dynamic"`), with `.default` preserving the SDK's
  static policy and no prefixed aliases. One fixed nixpkgs input,
  `github:NixOS/nixpkgs/c7def046b9a883d46974757852106483d741586f`. Its
  `devShells.default` is tools-only. Nothing in the file calls
  `builtins.getEnv`, because an impure read forces `--impure` on every consumer
  of the flake.
* **`devenv.nix`, `devenv.yaml` and `.envrc` make devenv the canonical
  interface.** Its `packages` is tools only — `zig_0_16` and the C toolchain —
  and the same two derivations are exposed **lazily** as `outputs.static` and
  `outputs.shared`, built with `devenv build outputs.static` /
  `outputs.shared`, so entering the shell does not build the SDK. Scripts live
  under one `sdk` namespace and carry real commands. The input is pinned to
  `github:cachix/devenv-nixpkgs/c2f38fe7f9e04d9aadd354d380f2bd40531d9737`
  rather than `rolling`. `devenv.yaml`'s `clean` list names only devenv's own
  `generated state and deliberately not `.zig-cache/` or `zig-out/`. **§39
  supersedes what this entry said about lock files**: `flake.lock` is committed
  here and is a `.paths` entry, and `devenv.lock` still does not exist in this
  repository.
* **The integrity record gained a line and moved a name.** `UPSTREAM.sha256`'s
  record for upstream's README now names `README.upstream.md`, the path those
  exact bytes are preserved at; the digest `90c885da…` is unchanged, because
  the bytes are. `INCHI-1-SRC/INCHI_API/libinchi/gcc/libinchi.map`, upstream's
  own ELF version script, was promoted out of "carried for provenance" into
  `.paths` — a shared build passes it to the linker, and a build cannot read a
  file the package does not ship — and is hashed as the record's **110th** line,
  `9c90980efa8c3310b624b334dc9e5c384e83d9790214746c80fc59f7fc4b16c2`. It is
  upstream's file, unmodified, and read only on ELF targets under
  `-Dlinkage=dynamic`.
* **This fork's own files now have a grant, with the owner's authorization
  behind it.** `FORK-LICENSE.md` defines **`LicenseRef-InChI-MIT-Conditional`**:
  the MIT text verbatim, plus the two obligations upstream's own files carry —
  the InChI attribution notice travels, and the version banner identifies the
  software — plus upstream's own coupling condition from `sha2.h:12-13`, that
  these files are redistributed and modified as a part of the InChI software
  package. It is `LicenseRef-` and not `MIT` because a scanner that stops at the
  permission grant misses all three. **No personal or corporate copyright
  identity is asserted anywhere**: none was supplied and none is invented, so
  the grant says a holder exists and does not name one, and the owner must
  substitute that line before publication. The earlier record — these files
  **unassigned**, and the "contributed under MIT" claim withdrawn — is what it
  was, and the grant does not reach back to a copy fetched before it existed.

**`README.md` is now this fork's document**, in the required order: current
source deviations, current build deviations plus this history link, the current
build/run/test matrix, then consumption. Upstream's own README is preserved
unchanged beside it as `README.upstream.md`, byte for byte, and is upstream's
file under upstream's terms. `README.zig.md` keeps the Zig interface and the
full receipt table and says so at the top.

**Verification and bound.** **Nothing in this entry has been gated.** Every
receipt anywhere in this package was taken before it. No shared library, no
`inchi.pc`, no Nix evaluation, no devenv shell and no `sha256sum -c` over the
110-line record exists. All of it is `PENDING-VERIFICATION` in the matrix in
`README.md`, and the driver owns the runs. **Bound:** a host with Zig 0.16.0,
`nix` and `devenv`; the derivation builds for its own platform only and claims
no cross-compilation, no hermeticity beyond the nixpkgs pin, and no wholly
static executable — `libinchi` links libc and libm, so a `.shared` consumer
needs a dynamic loader and a `.static` archive still needs its libc at run time.

## 37. Runtime loading, documented from the landed source

**Condition.** The package had no way to state the runtime route at all, and an
earlier pass in this same wave removed the rows that mentioned it as staged
incompleteness. That was wrong twice over: the route is landing now, and
describing a feature as absent is not the same as not claiming it.

**Fix.** `-Druntime=true`, default `false`. When set, `build.zig` replaces
exactly one call in the bundled arm — `module.linkLibrary(artifact.?)` — with
`runtime/graph.zig createModule(b, translate_c, target, optimize)`, and the
facade's `c` import becomes the generated dispatch. The C artifact is built
and installed either way. The four pieces and their owners are in
`README.zig.md` § Runtime loading: the driver's reviewed core in
`runtime/loader.zig`, `generate.zig`, `sync.c` and `sync.h`; this SDK's
descriptor in `runtime/library.zig`; the dispatch generated from the actual
translation output; and the two consumer-behaviour test roots.

The option is `-Druntime=true|false`, default `false` — settled, with no
alternative offered. It is orthogonal to `-Dlinkage`: which artifact, and which
dispatch. `-Druntime=true` together with `-fsys=inchi` **panics at configure
time** with a message saying why, because system mode's contract is to bind to
an installed `libinchi` and a runtime build does not bind to one; it is refused
rather than resolved in favour of either side, because silently dropping one
would build something the caller did not ask for under a name that says they
did.

**The two runtime steps, as they are.** `runtime-test` exists **only** under
`-Druntime=true` — `addTest` plus `addRunArtifact` on
`runtime/load_tests.zig` — and it needs both `INCHI_TEST_PROVIDER` and
`INCHI_TEST_ALIEN`, skipping nothing when either is missing, so it cannot be run
where both cannot be named. It is deliberately not in CI: `INCHI_TEST_ALIEN`
must be a loadable object that is not `libinchi`, and inventing one would be
fabricating a fixture this repository does not have. `misuse` is built and
installed by `zig build` in **every** configuration, and **no step runs it and
asserts an exit status**, because two of its three modes are supposed to stop
and which two depends on the configuration; `zig build` owes that it produces
the program and running the three commands is the caller's. The executable is
installed as `misuse`, matching the header in `runtime/misuse.zig` that
documents `pre-load`, `after-load <path>` and `linked-load`.

**The cross gate is explicit, not incidental.** `cross-test.profile.sh`'s
`CROSS_BUILD_ARGS` and the CI `cross` job both name `-Dlinkage=static
-Druntime=false`, so the 53-cell matrix is the static linked closure by
construction rather than by omission.

**What else this wave settled.** `consumer/build.zig` forwards `b.args` to the
run step, so `zig build consumer -Druntime=true -- --provider <path>` is a real
command; before that the documented command line would have silently done
nothing and the environment variable was the only way to name a provider.
`runtime/` is in `build.zig.zon` `.paths` whole.

**What is now documented rather than assumed.** `LoadSource` is a two-arm
union — `.path` for an absolute file path, `.system` for a named library, both
passed to the platform loader unchanged, with no path-to-system fallback. The
`LoadError` set is named in full. The provider requirements are read out of
`runtime/library.zig`: every `extern` the translated header declares, with
`FreeInChIExtInput` the single deliberate exception because upstream's own
`libinchi.map` does not export it; the same `inchi_api.h`/`ixa.h` with the same
`MAXVAL`, `ATOM_EL_LEN`, `NUM_H_ISOTOPES`, `STR_ERR_LEN`,
`MAX_NUM_STEREO_ATOM_NEIGH`, `MAX_NUM_STEREO_BONDS`, `INCHI_NUM` and
`FIND_RING_SYSTEMS` settings, because those fix the struct layouts the facade
itself hands across; a plain C calling convention with no variadics and no
exported data; and upstream's own allocator, which is also why a Zig leak
oracle cannot see it. The load-time check is `CheckINCHIKey` against a
published InChIKey and a non-key, and the document says plainly what that is —
a check that two routed entry points behave, not a compatibility verdict.

**Verification and bound.** **Nothing here has been gated.** No runtime build
and no load has been performed in this workspace, and the 53-cell matrix does
not cover this route: its cells are named without `-Druntime` and are the static
linked closure. Every runtime row is `PENDING-VERIFICATION` in the matrix in
`README.md`. **Bound:** a target with a dynamic library loader; the loader's own
`UnsupportedTarget` is the honest refusal where there is none, and no fallback
to a linked copy stands behind it.

## 38. Every "as it ships" test total in this file was a count of an earlier file

**Condition.** §32 and §33 recorded three green waves and summarised them as
current: the stable native wave at `expected_tests: 16`,
`observed_tests_passed: 16`, `verification_status: success` under "stable wave,
on the shipped arrangement", and `16/16` again at "remains current on the same
tree". Six further top-level test blocks then landed in `tests.zig` on their own
migration wave, adding directions that file did not have when those waves ran.

**What is wrong, and what is not.** **No receipt is falsified.** Those waves
really did execute sixteen tests and really did exit 0, on the tree they were
run against; every number stays. The defect is the *currency* word. `tests.zig`
as it ships declares **twenty-two** top-level `^test "` blocks — read out of
the file, and the only thing in this entry that was not already recorded
elsewhere — so no receipt in this package has executed the six
migration-wave additions, including both extended polymer/V3000 routes and the
two error-residue paths. A row labelled current for the file as it ships, whose
numbers cannot be produced by the file as it ships, is the shape of the
failure; nothing failed.

**The correction, and where it lands.** The receipts are kept and the
*currency* is withdrawn. §33's two load-bearing sentences now say "the file as
it stood at `2026-10-02T07:12:59Z`" and "superseded as current by §38" rather
than "the file as it ships" and "remains current on the same tree".
`FORK-NOTES.md` carries the same correction at decision 19's observed block,
at L9's "Resolved, and where" and at L17's "Resolved, and how", and the lesson
is **L29**. Historical rows elsewhere in this file that quote `16/16` as what
their own run printed are left exactly as they are: a receipt reports what a run
said. §33 already declared the *earlier* matrix run history, and §32 already
declared its own arrangement superseded by §33; the stable wave was the one row
left still claiming to be current, and this entry is what withdraws it.

**Compile coverage is untouched, and deliberately so.** The six-target `check`
baseline and every `build_only` matrix cell stay current, because compile
coverage does not move when a test is added. Only test totals moved.

**No test is added for this.** A permanent test asserting how many tests the
file declares would fail on the next test anyone adds and would pin a number
rather than a behaviour. The count is recorded here instead, and the next wave
that runs this suite is the gate that settles it.

**Status: `PENDING-VERIFICATION`.** The count is `SOURCE-CONFIRMED` from
`tests.zig`. No wave has yet executed the twenty-two-test suite, so this entry
states a correction landed, not a result observed; the driver's next native
wave is what moves it. `FORK-NOTES.md` **L29** is the transferable form.

## 39. A committed `flake.lock` is shipped, because `flake.nix` is

**Condition.** The entry above recorded the position as "no lock file is
written here; `flake.lock` and `devenv.lock` belong to the operator". That was
true when it was written and is no longer. `flake.lock` is now committed in
this package and `build.zig.zon` lists it in `.paths` beside `flake.nix`. The
manifest is not this entry's file; the record of it is, because a change to the
package's contents with no numbered entry leaves the two disagreeing.

**What is in the lock, read out of the file.** `version 7`, one node,
`nixpkgs`, `owner: NixOS`, `repo: nixpkgs`, `type: github`, locked and original
both at rev `c7def046b9a883d46974757852106483d741586f`, `lastModified`
1789370336, `narHash`
`sha256-6RSEDHIWQtesQKWSu5qRai8L2h4KgCgMEfJHstW99G4=`. That rev is the same one
`flake.nix` puts in `inputs.nixpkgs.url`, so the file pins the input the flake
already names rather than introducing a second one.

**Why shipping it is the rule and not a preference.** `.paths` is a hard
filter, so a consumer that received `flake.nix` without the lock would
re-resolve nixpkgs and write a lock into their own copy — the one thing a lock
exists to prevent. The package is meant to be standalone and reproducible for
a dependent, and a dependent is exactly the case where reproducibility is paid
for.

**`devenv.lock` stays absent, deliberately.** No such file exists in this
repository and none is invented to fill the slot. `devenv.yaml` pins its own
input by revision, so the shell resolves without one. An absent lock is a
different fact from a shipped one, and the two are recorded separately for that
reason.

**`package.nix` is a different axis and is unaffected.** Its `lib.fileset`
allow-list is exactly what `zig build install` reads, and a Nix derivation may
exclude locks from its native build source *after* the flake frontend has
resolved locked inputs — which is what it does. Nothing here changes which
files a native build compiles.

**Status: `PENDING-VERIFICATION`.** The lock's contents are `SOURCE-CONFIRMED`
from `flake.lock` and `build.zig.zon` as they now stand. No filtered fetch,
package-identity or provenance gate has run over this tree since the `.paths`
change, so any package identity recorded before it is stale and is to be
re-derived by the driver once, after source and documentation freeze — not once
per edit.

## 40. A raw signed count was being cast, not checked, and the answer depended on `-Doptimize`

**Condition.** `Atom` is upstream's `inchi_Atom` unchanged and `Atom.num_bonds`
is the raw count that bounds `neighbor`, `bond_type` and `bond_stereo` together
(`inchi_api.h:165-171`). It is an `AT_NUM` — a `signed short`
(`inchi_api.h:124`) — on a caller-writable struct, so a negative value is
representable. The private reader `used()` converted it with a bare
`@intCast`, and `connect` called that reader *before* its capacity test.

**What one call did.** With `num_bonds = -1` written by hand and `connect`
called, the answer was chosen by the optimisation mode rather than by the
contract:

- **Debug / ReleaseSafe** — the checked `@intCast` traps. Observed by the
  driver: `bg719`, **ABRT**, "integer does not fit" at `zig/root.zig:1721`,
  reached from `connect` at `:1136`.
- **ReleaseFast / ReleaseSmall** — the unchecked cast wraps the value, so the
  input to everything downstream is one the language does not define. Observed
  by the driver: `bg721` **did not terminate** and was still running, single
  threaded, on the same frozen probe; no exit status and no output were
  obtained, and no "passes" is claimed for it.

The module header promised the opposite: each bound is "checked where a caller
can act on it, with an ordinary comparison rather than an assertion". The
sibling reader `borrowedArray` already did exactly that, with `count <= 0`.

**The change.** Three statements, and no new error:

- `used()` is total: a non-positive count is 0, mirroring `borrowedArray`. It
  can no longer trap on a value the field is declared to hold.
- A new private `countOutOfRange` refuses any count outside
  `0..max_bonds_per_atom`, and `connect` calls it for both atoms before either
  list is written.
- The refusal reuses the **existing** `error.TooManyNeighbors`, whose
  documentation now states the whole range instead of only its ceiling. The
  module's error set is unchanged, `connect`'s signature is unchanged, and
  there is no shim and no second error for the same kind of refusal.

**Why a negative count is "no room", not "a shorter list".** The API states the
range itself at `inchi_api.h:171` — "Index j is in the range 0 <= j <=
(atom[i].num_bonds-1)" — and the compiled closure reads the field as
`for (j = 0; j < num_bonds; j++)`, at
`INCHI-1-SRC/INCHI_API/libinchi/src/ichilnct.c:297`. A negative count therefore
reads nothing at all, which means a bond appended at index 0 would overwrite
entries upstream never promised to read but that the caller did write. The
record is refused rather than repaired, and the caller's bytes are left exactly
as they were.

**What a citation this entry does not use.** An earlier draft of this entry
cited `e_0dstereo.c:983` for that loop. That file is not part of this library's
compile closure — it is `INCHI-1-SRC/INCHI_API/demos/inchi_main/src/`, a demo —
so naming it would have cited a demo as the library's own reader.
`runichi2.c:940` is left out for the other reason: it appeared in a grep and was
never opened.

**Cost.** One private helper added, one reader made total, one guard widened,
four documentation sites corrected (`Error.TooManyNeighbors`, `Atom`, `connect`,
`used` and `countOutOfRange`), and one regression added to the existing test
`"the facade refuses input it cannot pass on faithfully"` rather than as a new
top-level block — which is why §38's count is unaffected by this entry. No error
was added, no signature changed, no caller changed, and no native byte moved.

**Status: `PENDING-VERIFICATION`, with the before half observed.** `bg719` is a
driver observation of the defect and is recorded as such. Nothing here has been
re-run after the change: the probe at
`/home/tmp2/gertullj/scratch/foundation-libs/contract-physics-lua/api-repros/inchi`
is unchanged and expects, in both modes, the same refusal in Debug and in
ReleaseFast with a bounded exit. `zig/root.zig`'s own test suite and the native
waves are the driver's to run. `FORK-NOTES.md` **L30** is the transferable form.

## 41. The devenv scripts name this tree, and build and install outside it

**Condition.** §36 made devenv the canonical interface and gave this shell six
scripts, and left four properties the acceptance recipe depends on unstated.
A devenv script is materialised as a generated program that inherits the
caller's working directory, so `sdk:build` and `sdk:test` ran `zig build`
against whatever directory the caller happened to be standing in, and the
driver enters this shell from a scratch project directory that holds no
`build.zig`. Both install bodies defaulted their prefix to `$PWD/zig-out`,
which after that `cd` is this checkout — the tree `UPSTREAM.sha256` and the
driver's source digest cover. And all four bodies reached the build runner with
no job flag, no `--summary all` and no `--cache-dir`, so a canonical command
gave the runner whatever the host's core count happened to be and left its
caches to defaults — one of which is this checkout's own `.zig-cache`.

**Fix, in four parts, all inside `devenv.nix`.**

- **Every script body begins by changing into this SDK's own directory.** It
  is `./.` in the module rendered once as `builtins.toString ./.` through
  `lib.escapeShellArg`, with `exit 1` on a failed `cd`, so no two bodies can
  drift on it and none of them builds or checks in a directory that has no
  `build.zig`. `builtins.toString` rather than an interpolated `${./.}`:
  interpolating the path asks Nix for the store copy of this whole tree, and
  that copy is read-only and is not the working tree `sha256sum -c` describes.
  `$DEVENV_ROOT` was never the variable to trust; it names the project
  directory `devenv --from path:<this SDK>` creates beside this tree. All six
  scripts carry the line, the two `devenv build` ones included, because
  `devenv build` reads the project it is standing in.
- **The two installing scripts pass `--prefix` themselves.** `zig build
  install`'s own default is `zig-out` beside the build root. The prefix is
  `$INCHI_PREFIX` when the caller exported one — the name these bodies already
  read, and the only prefix variable this shell has — else
  `$ZIG_LOCAL_CACHE_DIR/inchi/zig-out`, which the cache rule below has already
  filled and exported, or the body already stopped. `$PWD/zig-out` is gone,
  because after the `cd` above it named this checkout. `sdk:test` and
  `sdk:check` install nothing: `build.zig:671` hangs the smoke program's
  compile step under the install step and never the reverse (`build.zig:662`,
  `build.zig:675`), so a prefix there would be a flag that changes nothing.
- **Every `zig build` names its cache.** The four bodies pass a `--cache-dir`
  holding `$cacheDir`, which is `$ZIG_LOCAL_CACHE_DIR/inchi` — this SDK's own
  name under the local root, the way box2d names its own — and a missing cache
  variable is filled first, from `$XDG_CACHE_HOME`, else `$TMPDIR`, else
  nothing: with none of the four set the body names what is missing and exits
  non-zero **before the compiler starts**. A caller that exported
  `ZIG_LOCAL_CACHE_DIR` or `ZIG_GLOBAL_CACHE_DIR` keeps both, exactly as
  exported; this never unsets and never overwrites one, and it never falls back
  to this checkout's own `.zig-cache`. The fill is in the bodies and not in
  `enterShell` because `devenv tasks run --mode single <name>` reaches a body
  without the shell hooks. The global cache is the root's `zig-global`, shared
  by every SDK on the mount and so not this file's to name per SDK; no flag
  carries it, so no flag is written twice.
- **Every `zig build` carries a fixed `-j8` and `--summary all`**: `install` in
  both installers, after `-Dlinkage=dynamic` in the shared one so that variant's
  default is unchanged; `test smoke` in `sdk:test`; `check` in `sdk:check`. No
  step name, description, default, linkage, `packages` or `outputs` entry
  changed, and no `"$@"` was added to a body that never carried one.
  `sdk:package-static` and `sdk:package-shared` are Nix builds, where the job
  count is the caller's `--max-jobs`/`--cores` and `-j8` is not the flag that
  governs it.

**Source-confirmed, `PENDING-VERIFICATION`.** Every line above is read out of
`devenv.nix` and `build.zig`; no devenv, Nix, `zig`, test or formatter was run
to produce it, and nothing here is a receipt. The `devenv shell`, script and
packaged-output rows in [`README.md`](README.md) §3 keep their status, and the
driver owns the runs. §36's statements stand: the scripts live under the `sdk`
namespace, they carry real commands, and `packages` is still tools only.

## 42. Corrected the molfile status producer contract

**Condition.** `MolfileStatus` preserves the whole `RetValMol2INCHI` header
namespace, but its documentation claimed that the molfile entry point reports
read and generation failures separately.

**Source-confirmed correction.** In the pinned v1.07.5 producer,
`MakeINCHIFromMolfileText` maps both `_IS_FATAL` and `_IS_ERROR` from reading to
`mol2inchi_Ret_ERROR` (`inchi_dll_b.c:184-197`), and maps generation failures to
that same code (`inchi_dll_b.c:229-232`). Both arrive as `.rejected` (2).
`.structure_failed` (4) and `.generation_failed` (5) remain named because the
type represents the complete header namespace, not only the reachable output
of one producer. They do not distinguish these failure stages in this release.
No extra API, stage inference, native change or enum removal was added.

**Status: `SOURCE-CONFIRMED`, with a scoped observed control.** Corrected the
type and arm comments in `zig/root.zig` and the contract in `README.zig.md`.
The existing unreadable counts-line semantic test is intentionally unchanged.
On 2026-10-04, the driver's `bg1114` after wave observed the malformed-molfile
control return raw 2 and typed `.rejected` serialized as 2, exit 0, in
Debug/ReleaseSafe with static/dynamic linkage. The exact Debug/static command
was the after epoch's `prefixes/Debug-static/bin/inchi-consumer
molfile-read-rejected`; receipts:
`/home/tmp2/gertullj/scratch/foundation-libs/text-contract-probes/inchi/epochs/key-verdict-native-codes/after/summary.json`
and its `Debug-static-molfile-read-rejected.json`.
Generation-failure collapse and unreachable producer codes 4/5 remain
source-confirmed; this control does not execute those paths. No worker gate
ran. The boundary is also recorded in `FORK-NOTES.md` L31.

## 43. Completed the nested consumer command contract

**Condition.** The outer `consumer` helper did not pass its trailing arguments
to the child build, although the child already passed its own `b.args` to the
program. The published `-- --provider <path>` route therefore lost the provider
at the outer hop. The helper also omitted explicit global-cache selection,
job width and summary mode.

**Source-only correction.** `runConsumer` in `build.zig` now emits `-j8`,
two-token `--summary all` and two-token `--global-cache-dir` using the inherited
global cache path. The existing two-token local cache and its `consumer`
subdirectory stay unchanged. Last, it emits `--` followed by the caller's
`b.args` verbatim. The target query, CPU, optimize, linkage, runtime, resolved
system mode in both directions, executor switches, `--libc-runtimes` and
`hostCanExecute` run/install policy remain unchanged. No new SDK option,
consumer default, signature or permanent forwarding test was added.

**Status: `PENDING-VERIFICATION`.** The build owner supplied the source-only
change record; this entry integrates it with the corrected argument description
in `README.zig.md` and the boundary in `FORK-NOTES.md` L32. No compiler, build,
test or formatter ran for this change. The driver owns native and explicitly
named target consumers, linked/shared/runtime modes, system mode, enabled
executors and the actual provider argument route.

## 44. Preserved native signed key-verdict codes

**Condition.** `KeyVerdict` used `enum(c_int)` but left its named values
implicit. `RetValCheckINCHIKeyv` instead defines 0, -1, 1, 2 and 3
(`inchi_api.h:1062-1066`). Symbolic comparisons hid the difference:
`checkKey` selected `.non_standard`, but serializing that returned value
produced 1, the native code for invalid length.

**Observed before, driver report.** The parent's `bg1082` before wave covered
Debug and ReleaseSafe with static and dynamic linkage, producing 24 rows:
16 expected numeric mismatches for non-standard and invalid verdicts, and
8 passing standard-key or malformed-molfile rows. The Debug/static non-standard
sample returned native -1, tag `non_standard`, and serialized 1 instead of -1,
ending in `TypedSerializationMismatch`. This establishes the prior defect;
it does not establish a result after this correction.

Before receipts:
`/home/tmp2/gertullj/scratch/foundation-libs/text-contract-probes/inchi/epochs/key-verdict-native-codes/before/summary.json`
and the exact non-standard sample
`/home/tmp2/gertullj/scratch/foundation-libs/text-contract-probes/inchi/epochs/key-verdict-native-codes/before/Debug-static-nonstandard.json`.

**Fix.** Give every named `KeyVerdict` its explicit native signed code:
`standard = 0`, `non_standard = -1`, `invalid_length = 1`,
`invalid_layout = 2`, `invalid_version = 3`. Keep `c_int`, the unnamed `_`
channel and the existing `checkKey` mapping. Extend the existing semantic key
tests to serialize actual returned verdicts for a generated non-standard key,
the published water key and malformed length/layout/version inputs. No test
merely compares enum declarations to copied constants or raw forwarding calls.
All existing symbolic callers remain valid; no compatibility alias or extra
API was added.

**Status: `OBSERVED`, scoped semantic after probe.** On 2026-10-04, the parent's
`bg1114` after wave reported all 24 rows passing across Debug/ReleaseSafe,
static/dynamic linkage and the six semantic cases. All returned native and
typed-serialized key codes match 0, -1, 1, 2 and 3; the malformed-molfile
control remains `.rejected` (2). The exact Debug/static non-standard command,
the after epoch's `prefixes/Debug-static/bin/inchi-consumer nonstandard`,
exited 0 with raw -1 and serialized -1. Receipts:
`/home/tmp2/gertullj/scratch/foundation-libs/text-contract-probes/inchi/epochs/key-verdict-native-codes/after/summary.json`
and its `Debug-static-nonstandard.json`. This does not establish the current
full SDK suite, 53-target matrix, runtime loader or new nested-helper/prefix
proof. No worker gate ran; API and tests remain frozen.
`README.zig.md` records the numeric contract; `FORK-NOTES.md` L33 records scope.

## 45. Relayed a non-default prefix to the nested consumer

**Condition.** The nested consumer changes directory before it configures its
own install step, so an outer install prefix must be relayed in the build
runner's option channel, not as a program argument.

**Source-only correction.** The build owner updated `runConsumer` to emit
two-token `--prefix` with the actual `b.install_prefix` when it differs from
the outer build's default `zig-out`. Relative prefixes are made absolute
against `b.graph.cache.cwd` before the child runs in `consumer/`. The option
follows the global-cache block and precedes `--` plus `b.args`. No prefix is
emitted for the default. All target, CPU, SDK, executor, cache, job and summary
choices and the `hostCanExecute` run/install policy remain unchanged.

**Status: `PENDING-VERIFICATION`.** Integrated the prefix build owner's
source-only record into `README.zig.md` and `FORK-NOTES.md` L32. No build,
compiler, test or formatter was run by this worker; the driver owns observing
the nested installation under absolute and relative non-default prefixes.

## 46. The system mode's resolved metadata is stated, and four source-bound gates are recorded

**Condition.** The records named `-fsys=inchi` as a mode and nothing about how
it resolves an installed library, while four driver runs had already produced
current numbers that no entry carried.

**What the graph resolves, `SOURCE-CONFIRMED` from `build.zig` and verified by
no run.** Which installed flavour: an omitted `-Dlinkage` means the
distribution's shared object, so `system_linkage` defaults to `.dynamic`, and an
explicit `-Dlinkage` names which installed flavour `-l` asks for
(`build.zig:514-521`); the field is kept apart from `linkage`, because in this
mode the graph builds no artifact and `linkage` describes nothing. Which
metadata: the translation step and the published module ask pkg-config for the
installed tree's own `inchi.pc` with the same options — `.use_pkg_config = .yes`
and that `preferred_link_mode` (`build.zig:963-967`, `:1052-1055`) — so the
header the declarations came from and the `-linchi` they bind to are one answer.
`.yes` is the deliberate choice here and `.force` is not: the fallback is the
bare `-linchi` the file itself publishes, and this mode degrades to a name
rather than stopping. Which executor: the nested `consumer` build inherits the
switches this build resolved — `-fdarling`, `-fqemu`, `-frosetta`, `-fwasmtime`,
`-fwine` — and `--libc-runtimes` (`build.zig:1473-1483`), and the `-fsys=inchi`
or `-fno-sys=inchi` spelling is forwarded verbatim (`build.zig:1465-1471`), so
the nested build runs under the executor `hostCanExecute` decided with instead
of resolving its own. **No run of `-fsys=inchi` has happened in this workspace,
so no result is claimed for the mode.**

**Four source-bound gates, each read out of a receipt the driver wrote.**

* `zig build check` over the six declared compile targets, 2026-10-05: exit 0,
  `Build Summary: 31/31 steps succeeded`, no failing step, all six targets seen.
  Label `baseline-inchi-check`, baseline run `20261005T014547Z-797a73f2`. Compile
  and link only.
* `cross-test --jobs 8 --build-jobs 8` over the published 53-platform table,
  2026-10-04: run `20261004T221720228710Z-45046`, receipt
  `inchi-53-target-8.json`, source stamp `bc5a479718…` identical before and
  after, exit 1. **12 pass, 33 build-only, 0 build failures, 8 run failures**, 20
  cells executed at 22 tests each. The eight failures are the big-endian family
  — `aarch64_be-linux`, `armeb-linux`, `mips-linux`, `mips64-linux`,
  `powerpc-linux`, `powerpc64-linux`, `s390x-linux`, `thumbeb-linux` — and in
  each one test of 22 fails: `tests.test.the molfile route produces PubChem's
  published identifier and key` returns `error.MissingIdentifier` at
  `tests.zig:734` with `molfile: status rejected, message` and an empty message,
  under `qemu-mips` and its siblings. The other 14 tests pass in every one of
  them. That is one upstream molfile route under foreign big-endian emulation.
* Native final wave, `native-final-evidence/20261004T233628757747Z-69351`: eight
  cells, both linkages × four modes, `zig build test smoke install
  -Druntime=false`, eight `exit 0`, each `30/30 steps succeeded` and `22/22 tests
  passed`.
* Own-loaded wave, `loaded-final-evidence/20261004T232823091897Z-23133`: the same
  eight shapes under `-Druntime=true`, eight `pass`, each `31/31 steps succeeded`
  and `22/22 tests passed`, every cell loading a provider of kind `own` — the
  `libinchi.so.1.7.5` the native wave installed — named by absolute path through
  `INCHI_TEST_PROVIDER`, with nothing read from the ambient environment and no
  fallback.

**What these runs retire and what they do not.** The file as it ships declares
22 tests, and these runs executed it; the older `16/16` rows stay history for
the tree they were taken on. They also settle the two std spellings
`Step.Compile.setVersionScript` and `Build.installFile` that earlier rows carried
as unconfirmed, because sixteen configurations used them. Each run holds one
source stamp, so every build-graph, header, helper and normalisation edit made
afterwards — including entries 42 to 45 — is outside all four. The
whole-record `sha256sum -c UPSTREAM.sha256`, the final filtered package round,
`zig build -fsys=inchi`, the Nix derivations, the devenv shell, a
foreign-compatible provider and the loader's failure paths keep no receipt, and
this entry claims none.

**Files.** `README.md`, `README.zig.md`, `CHANGELOG.md`, `FORK-NOTES.md`. No
upstream C byte, header, fixture, data file or licence file changed, and no
algorithm, declaration, option, default, step or target changed. No build, test,
matrix, Nix, devenv, formatter or git command was run for this entry.
