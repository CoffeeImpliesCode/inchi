# CHANGELOG — fork-only divergences

Upstream's release history lives in its own repository
(`INCHI-1-DOC/CHANGELOG.md`, and the release notes in `INCHI-1-DOC/RelNotes/`).
This file records **only** what this fork changed relative to InChI `v1.07.5`
(commit `11a87982bb518f57ac013f0b258c283655e1ea1d`), and nothing upstream did.

Every gate named here was run by the driver. Where a correction has not been
gated since it was made, that is said in the entry, and no green result is
claimed for it. Each entry keeps the receipts that were current when its claim
was made; **§29 is the current cutover** — the receipts that describe the tree as
it stands — and the full table is in `README.zig.md` § Verification status.

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
the file as it ships. The 20 cells with a runner each executed the full 16-test
suite — 320 tests run, every one `Build Summary: 6/6 steps succeeded; 16/16
tests passed`, `reason: tests_complete`, `command_exit: 0` — and the other 33
stayed `build_only` with `reason: runtime_unavailable`, which is compile
coverage and is never counted as a pass. **No foreign BSD, macOS, Mac
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
native wave is unaffected and remains current on the same tree: 16/16 in Debug,
16/16 in ReleaseSafe, plus smoke, install and consumer, all exit 0.

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
