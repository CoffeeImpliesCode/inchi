# FORK-NOTES — what was decided, and what it cost

This file records the decisions taken while building this Zig package over
InChI 1.07.5, and the lessons that came out of the gates the driver ran. It is
the reasoning behind [`CHANGELOG.md`](CHANGELOG.md); where they disagree, the
changelog records what changed and this one records why.

The condition/symptom/fix/target-bound shape is used throughout so that a later
wave — in another directory, or against another toolchain version — can apply a
lesson without re-deriving it. A lesson whose symptom was **not observed** says
so; that is a real distinction here, because two of the most expensive items in
this package's history were found by reading, not by a gate.

## Decisions

### 1. What the integrity record covers, and what it does not

**Decision, as it now stands.** `UPSTREAM.sha256` hashes the 105 upstream files
in the two directories `build.zig.zon` `.paths` names, plus upstream's
`INCHI-1-SRC/INCHI_API/tbb/LICENSE`, plus upstream's ELF version script
`INCHI-1-SRC/INCHI_API/libinchi/gcc/libinchi.map`, plus `LICENSE`, plus
upstream's README — now under the preserved path `README.upstream.md` — plus
the one independent fixture the tests embed: **110 records**. It hashes no file
this fork wrote *except* the two upstream files this fork patched on purpose,
`ichiparm.c` and `ichicano.c`, which are the subjects of decisions 13 and 17
and are named here only so the "never" in the original wording of this entry is
not read as still standing.

**Why that set.** It is exactly the set a dependent receives and the build
compiles, so `sha256sum -c UPSTREAM.sha256` works in a clone *and* in an
unpacked package. It covers the fixture as well as the sources because
`tests.zig` `@embedFile`s it and a silent edit to it would move every published
expectation in the package at once — which is exactly the edit the integrity
record exists to make loud.

**Why `.gitignore` is absent.** Upstream's rules are kept verbatim and the fork
appends four entries below them, so the file is not byte-identical to upstream's
and a record of it would be a record of the fork's own change.

**The two numbers are not comparable, and this file says so where both are
printed.** The archive digest
`55382c70314a01a9d2f3a18f0833a44c352d7332884f614f28cbb1d40c17d5f6` is the
parent's `git archive` of the **whole upstream tree** at the pinned commit.
The 109 records are this working tree's subset.
Re-deriving the archive digest needs a re-fetch; re-deriving the records does
not. A re-sync should assert the second, and expect the first to be a different
number rather than treating a difference as corruption.

**One of the 109 is now this fork's bytes, and upstream's are kept beside it.**
After `ichiparm.c` was patched (decision 13) the record names this fork's
digest for that one path, and upstream's own
`eb3516115a1d25776f823de800d1c61cf0161e5bedbecac3511cd21ec0de2478` is written
out in `UPSTREAM.md` as the baseline the patch is measured against. The record
still covers the same 109 paths and still travels with the package; what it no
longer establishes is that the tree is upstream's byte for byte, and that
claim is not made anywhere now.

### 2. The compile unit list is written out, not globbed

**Decision.** All 60 `.c` files are listed by name in `build.zig:60-131`, split
into the three groups upstream's own CMake block uses (`${P_CURRENT}`,
`${P_IXA}`, `${P_BASE}`).

**Why.** A glob would let an upstream release add a translation unit — or drop
one — with no decision recorded anywhere. The list is upstream's, so it should
move when upstream moves and not otherwise.

**Cost, honestly.** When the list has to move, someone has to notice. That is
step 4 of the re-sync procedure in `UPSTREAM.md`, and it is a real obligation,
not a formality. The list was checked against the directories while this was
written: the sixty names in `build.zig` and the sixty `.c` files on disk are the
same set.

### 3. The IXA backend ships even though nothing wraps it

**Decision.** Compile `ixa/*.c` and ship `ixa/*.h`, and reach IXA through
`pub const c` rather than through a Zig wrapper.

**Why not drop it.** `inchi_api.h:1413` ends with `#include "ixa.h"`, so the
IXA handle API is part of the public header of the library this package builds.
A package that installed the header without the backend would ship a
declaration it cannot honour, and `consumer/` would fail to link against `c`
for anyone who used it.

**Why not wrap it.** A wrapper would mean owning four handle lifetimes and a
status-handle error convention that the facade's contracts do not describe. The
honest thing is to say so and leave `c` reachable.

**Cost, honestly.** A caller who wants IXA gets upstream's behaviour and none
of this package's ownership or sentinel guarantees. That is stated in
`README.zig.md`, not papered over.

### 4. Upstream's flags and macros are quoted; `-O1` and `-Wno-all` are not

**Decision.** `-std=c11`, `-fno-strict-aliasing`, `TARGET_API_LIB=1`,
`COMPILE_ANSI_ONLY=1`. Upstream's `-O1` and `-Wno-all` are not copied: the
optimisation level is the build's own `-Doptimize`, and warnings stay on so a
real defect in a future re-sync is visible.

**Why `-fno-strict-aliasing` is kept** even though it is a warning-shaped
flag: the core compiles stb_sprintf, whose formatter reads its arguments with
`va_arg` as several different pointer types, and the InChIKey code carries
SHA-256 digests in `unsigned char` buffers. Those are precisely the accesses
strict aliasing permits a compiler to reorder or discard, and the symptom would
be a wrong InChI string with no diagnostic anywhere.

**Why `fPIC` is not.** It is in upstream's CMake list, it is inert in the
sources, and this package builds a static archive; position-independent code is
a property of the link, not of this C.

### 5. A warning is a value, and it keeps its identifier

**Decision.** `Status` is `enum(c_int)` with a `_` field, and `message` is
non-optional, so `inchi_Ret_WARNING` arrives as a status a caller can branch on
with the identifier still in hand. Nothing in the facade converts a warning into
an error, and a rejection arrives with upstream's own words attached rather than
as a bare status.

**Why it is worth its own entry.** The most common way to lose a correct
identifier is to treat `1` as a failure. Glycine's zwitterion is the worked
example: upstream neutralizes NH3(+)/COO(-) to exactly the neutral skeleton,
reports that it moved protons, and hands back PubChem's published CID 750
identifier. The test asserts the status, `isWarning()`, that identifier and its
equality with the neutral run at once, because any one of them alone would pass
on a broken binding.

**The boundary, then and now.** When this entry was written the claim that the
identifier comes out byte-identical was an inference from
`ichi_bns.c:5451-5461` rather than an observation, and the test had never run.
It has run: the Debug suite passes (`…-native-Debug-borrowed-atoms-183.log`), so
that claim is observed now. What is *not* asserted is upstream's English — the
message text is not a contract, and pinning it would have made a reworded
diagnostic a red suite (`CHANGELOG.md` §23). The status is derived from
`ichi_bns.c:5451-5461` and `ichimak2.c:1162-1168`; the identifier is a published
answer.

### 6. The option string is upstream's, passed through untouched

**Decision.** `Molecule.options` is `?[:0]const u8]` and goes to C verbatim.
This package adds no option, removes none, and does not validate the string.

**Why.** Option parsing is upstream's, it is documented in `inchi_api.h`, and
a wrapper that second-guessed it would be a second, divergent specification of
the same thing. The one thing the wrapper does do is make the *prefix* a
compile-time fact of the target rather than a guess — see lesson L8.

### 7. `c` is the escape hatch, and one entry point stays unwrapped on purpose

**Decision.** `pub const c` is public and complete. `GetINCHIEx` is reachable
through it and is deliberately **not** wrapped.

**Why.** `GetINCHIEx` rewrites `*` element names to `Zz` **in the caller's
atom array** (`inchi_dll.c:330-336`). If it were wrapped over a `[]const Atom`,
the const would be a lie. Leaving it out is what lets `Molecule.atoms` be
`[]const Atom` truthfully, and that in turn is what lets a structure rebuilt
from an identifier go back in with no copy at all.

**The narrow `@constCast` that remains.** `inchi_Input.atom` is declared
`inchi_Atom *`, not `const inchi_Atom *`. The facade casts the borrowed slice
to hand it over, and the cast is sound only because the entry points it does
wrap copy every field out before using any of it (`inchi_dll.c:252-256`,
`inchi_dll.c:1933-1936`) and write none of it back. That is a claim about
upstream's code; the line numbers it rests on are in `zig/root.zig` so a future
re-sync can re-check it.

### 8. Bounds are ordinary comparisons at the boundaries a caller can act on

**Decision.** Six bounds are checked in Zig, each with a named error: element
symbol length, atom and neighbour index, adjacency-list capacity on **both**
atoms before either is written, atom count against `AT_NUM`, and — by fixing
the key and hash buffer sizes in `KeyResult` rather than by checking — the key
and hash buffers.

**Why a comparison and not an assertion.** The package's house rule is that a
public bound survives an optimized build. `@panic` does not; `if (…) return
error.X` does.

**What is deliberately not tested.** `Error.TooManyAtoms` needs more than 32767
atoms and `KeyError.NotEnoughMemory` needs a real allocation failure. Neither is
mocked here, and neither is claimed as covered. A test that faked the allocator
to reach them would prove that the mock works.

### 9. There is exactly one allocator and it is upstream's

**Decision.** No Zig allocator appears anywhere in the facade. Output strings
and the structure's arrays come from `inchi_malloc` and go back to it through
`Free*`; `deinit` dispatches on `Origin` so the free always pairs with the
creator.

**Why `Origin` survives when it changes nothing today.** `FreeStdINCHI` is
literally `FreeINCHI` (`inchi_dll.c:183-186`) and `FreeStructFromStdINCHI` is
literally `FreeStructFromINCHI` (`inchi_dll.c:195-198`). The tag is kept
because the pairing that matters is the one the header promised at creation
time, and a future upstream release is free to make the two differ.

**The null-pointer decision.** This module never hands C a null `szOptions`: an
absent option becomes the empty string, which `parse_options_string` turns into
the same single empty argument a null would (`inchi_dll.c:1046-1062`). That
keeps one code path instead of two and removes a class of null dereference
without adding a branch.

### 10. The system mode translates the installed header, not this repository's

**Decision.** In `-fsys=inchi` mode no in-tree include path is added at all,
and the wrapper includes `<inchi_api.h>` by angle brackets.

**Why it matters.** If the in-tree header were reachable, it would be found
first, and this repository's 1.07.5 declarations would be silently bound to
whatever `libinchi` happens to be installed. That is a mismatch that compiles,
links and then produces wrong answers — the worst shape of bug there is.

**What is claimed.** The mode is real: the declarations translated are the
installed header's and the library linked is the installed one. **No run of it
has happened in this workspace**, so no proof is claimed for it.

### 11. The tests are published answers, not round trips

**Decision.** Every expected identifier and key in `tests.zig` comes from
`testdata/pubchem_known_answers.tsv`, which was read out of PubChem's own
compound records one CID at a time through the PUG REST endpoint, as the file's
header records. Two round trips exist — L-alanine's rebuilt structure, and
`fromIdentifier.converted` — and both are labelled supplements. The conversion
is asserted twice over: seven published identifiers with **no** options, each
compared against PubChem's string rather than against its own input, and water
with upstream's **layer-keeping** string, whose answer is `InChI=1/H2O/h1H2`
whereas the same input with no options returns the published `1S` form. That
pair is the reason the facade is described as a forwarder rather than a
normalizer: it reports what upstream made of the options it was handed.

**Why a round trip is not an oracle.** It proves the library agrees with itself.
A binding can be perfectly self-consistent and systematically wrong: a wrong
option prefix, a mis-transcribed struct field, a wrong implicit-hydrogen count
— every one of those round-trips perfectly and every one of them fails against
PubChem.

**Why the stereo pairs are asserted as a pair.** A 0D parity is defined
relative to `Stereo0D.neighbor`'s order, and which parity a given order means is
decided by the canonical ranking InChI computes from it
(`inchi_api.h:255-256`). A test cannot predict it. It can assert that the two
parities of one skeleton produce exactly the two identifiers published for that
pair of compounds, and that each one's key is the key published beside it — a
complete known-answer statement that does not require the prediction.

### 12. Debug stays Debug

**Decision.** `-Doptimize` is forwarded verbatim into the C core, the facade,
the test root, the smoke root, the six cross checks and the nested consumer.
No step maps Debug to ReleaseSafe.

**Why this was nearly wrong.** A Debug gate and a ReleaseSafe gate are different
evidence, and quietly substituting one for the other makes the first gate
meaningless while looking like it passed. The builder had been asked to make that
mapping; it refused, and this fork keeps the refusal.

### 13. ReleaseSafe was red on purpose; then the cause was fixed, in one file

**Decision, in two stages.** The first was to record ReleaseSafe red and leave
it red: `ichiparm.c:2597` nests `/*` inside a block comment and
`ichiparm.c:2718` expands the compiler's build-date and build-time macros, and
Zig's ReleaseSafe C backend refuses both. Nothing was suppressed — no `-Wno-`,
no mode-conditional flag, no source edit — because each of those turns a red
cell green while removing the only evidence a consumer has that this C core is
not ReleaseSafe-clean upstream. That red receipt is
`local://foundation-expansion-inchi-native-ReleaseSafe-corrected-193.log`, taken
on the **pre-patch** tree; it stays red under its own name and is history for the
patched bytes, whose ReleaseSafe result is the `-374` row below.

**The second stage was authorised by the user, and it is one file.** The
boundary is worth less than the defect behind it once the defect has a fix that
changes no behaviour. `INCHI-1-SRC/INCHI_BASE/src/ichiparm.c` is patched, with
the scope fixed at two constructs: the accidental nested-comment delimiter in a
disabled block at `2597`, and the two mutually exclusive branches of the usage
banner in `HelpCommandLineParms` at `2712` and `2718` — the
`#ifdef TARGET_EXE_USING_API` branch and the ordinary one — which both expanded
the wall clock. They now pass the pinned tag `v1.07.5` and the literal
`(no build timestamp)`. No algorithm, ABI, allocator, option, timeout, compiler
flag or build mode is in it; `ichicano.c`, the `aarch64-macos-none` boundary, was
explicitly outside it and is handled by decision 17 below. The three
`__DATE__`/`__TIME__` sites in `OpenFiles` are
left as upstream wrote them, inside the `#ifndef TARGET_API_LIB` block that
every configuration this package builds preprocesses away. The patch, its two
contexts and both digests are written out in [`UPSTREAM.md`](UPSTREAM.md) § The
two patched source files.

**Both named constructs are addressed, and that is a reading of the source
rather than a gate.** A scan of the file finds no `/*` inside a block comment
anywhere in it, and no build-date or build-time macro expanded outside that
`#ifndef TARGET_API_LIB` block. The format strings are untouched: the two
replacements land in the `%s` and `%-s` conversions the macros filled, so the
argument count, order and types are as upstream left them.

**Why it did not become a silent edit.** Patching upstream means the integrity
record stops being a proof that the tree is upstream's, and every receipt taken
before the patch stops being current verification. So the record's `ichiparm.c`
line was re-derived from the patched file, upstream's digest is preserved as a
written baseline beside it, and the red receipts stay red under their own names
as history. The `-267` clean-diff receipt stays in `README.zig.md` as a statement
about the pre-patch tree and nothing else. The deviated scope is stated from the
`363` diff itself, which prints three hunks over the one path and carries no
`--exit-code`, so it is a scoped diff and not a pristine proof.

**What the patched tree has been observed to do.** Every gate below ran against
these bytes; host `gruenau8`, 2026-10-02. **All of it is history**: the
`ichicano.c` patch and then the guard move both landed after these receipts.

| Gate | Result | Receipt |
|---|---|---|
| Integrity, this repository | 109 records, 109 `: OK`, exit 0 | `-364` |
| Native Debug, test + smoke + install | 11/11 steps, 16/16 tests, `smoke ok` | `-365` |
| Native ReleaseSafe, test + smoke | 9/9 steps, 16/16 tests, `smoke ok` | `-374` |
| Live consumer | 6/6 steps, `consumer ok` | `-373` |
| Cross, x86_64-linux / aarch64-linux / riscv64-linux / x86_64-windows-gnu / wasm32-wasi | 6/6 steps each, exit 0 | `-367`, `-368`, `-371`, `-370`, `-372` |
| Cross, aarch64-macos-none | **red**, exit 1, `ichicano.c:46: error: 'sys/timeb.h' file not found` | `-369` |
| Filtered package fetch | exit 0, and an identity was printed | `-382` |
| Integrity in that fetched copy | 109 records, 109 `: OK`, exit 0 | `-388` |
| Consumer against that copy | 6/6 steps, `consumer ok` | `-389` |
| Installed banner, compile + run | exit 0; `GetINCHI(empty)` prints `Linux 64-bit Build (gcc Clang 21.1.0) of v1.07.5 (no build timestamp)` | `-384`, `-385` |
| Installed C + IXA surface, compile + run | exit 0, `installed InChI ethanol/key and IXA water agree with PubChem` | `-386`, `-387` |

**The one red cell is upstream's, and is not this patch.** `aarch64-macos-none`
fails on an unconditional `#include <sys/timeb.h>` at `ichicano.c:46`, outside
the guard that would have needed it — L9 and L17. `ichicano.c` is outside the
authorised scope and is untouched by the patch, and the other five targets
compile it.

That was true when this entry was written and is kept as it stood: the
authorisation for `ichiparm.c` did not then extend to `ichicano.c`. A second,
separately scoped authorisation followed — decision 17 guards the include and
decision 19 moves the guard — and the 53-cell matrix compiled the file with
decision 17's placement on all 53 of its targets, `aarch64-macos` and
`x86_64-macos` among them, at exit 0. `zig build check -Dtarget=aarch64-macos-none`
has since been **re-run at its own target and is green there** —
`Build Summary: 6/6 steps succeeded`, exit 0, in the workspace's 48-cell
explicit-target round — so the red receipt above is now history twice over.

`taskset` appears in the argv of the newer receipts because the driver pins a
project-scoped CPU set; it is a launcher around the same compiler, not a
different one, and the full argv is recorded with each receipt.

**Cost, stated.** The patch bought ReleaseSafe compiling where it refused, and
bought it at the price recorded in L18: one upstream file is no longer
byte-identical to the pin, and the receipts that predate it describe a tree that
no longer exists. Every one of those stays named rather than deleted. The lesson
is L18.

### 14. `CheckINCHI`'s strict flag is not a normalizer switch

**Decision.** `checkIdentifier(text, false)` and `checkIdentifier(text, true)`
are both exposed with upstream's own meaning and are asserted separately: a
well-formed `1S` identifier is `standard` under the first and
`conversion_failed` under the second. `fromIdentifier.converted` forwards the
caller's option string untouched; with `-FixedH -RecMet -SUU -SLUUD`, water comes
back as `InChI=1/H2O/h1H2`, and with no options it comes back as the published
`1S` string.

**Why.** Upstream's strict check regenerates and compares
(`inchi_dll.c:954-981`), and those options clear the standard flag as they are
parsed (`ichiparm.c:350-364`). A facade that "helpfully" normalised the answer
back to `1S` would be a second, divergent specification of the same contract.
It would also have hidden a real failure: the consumer that expected `standard`
from the strict call was wrong about upstream, and the fix belonged there.

### 15. `.paths` decides what ships, so a licence gap is closed in the manifest

**Decision.** The Apache-2.0 obligation on the Intel TBB header was closed by
adding `INCHI-1-SRC/INCHI_API/tbb/LICENSE` — upstream's own text, already in the
pinned tree — to `build.zig.zon` `.paths`, not by editing `NOTICE.md` to sound
reassured and not by dropping the header from the package.

**Why.** The obligation attaches to what a dependent receives. A dependency's
content is decided by `.paths`, so a documentation edit could only have changed
the description of the gap.

**Cost, and how it was paid.** Adding a shipped file without adding a record
line would have moved the gap rather than closed it: the record would have
covered 108 paths while the package travelled 109 upstream files, and the gate
would have stayed green over the smaller set. That state existed for one record
and is written down in `CHANGELOG.md` §25; the 109th digest was then added from
the file's own bytes — no upstream byte changed — and the gate re-run over the
whole record: 109 records, no failures, exit 0
(`…-immutable-source-complete-legal-109-240.log`), taken before the
`ichiparm.c` patch and history for that one line since — `-364` and `-388`
covered all 109 as of that patch and are history for the `ichicano.c` line since
decision 17. The lesson is kept as L15.

### 16. No licence was asserted for this fork's own files — superseded by 21

**Decision, as it was.** `build.zig`, `zig/*.zig`, `tests.zig`, `smoke.zig`,
`consumer/`, the workflow and these five documents were recorded as
**unassigned**, and the earlier sentence claiming they were contributed under
MIT was withdrawn.

**Why.** Nobody authorised this fork to grant its own files, and the package is
not MIT-only — it travels an Apache-2.0 file, so "the rest of the package is
MIT" was never a true premise for the inference. Silence is not a grant, and a
reader was told so rather than left to supply one.

**Superseded by decision 21, which is not a retraction.** The owner authorised
a licence for the fork-authored additions. What this entry said about the state
*before* that authorization is history and stays true of that state; what it
claimed about the present no longer holds.

**Target bound.** Any fork created inside a workspace where nobody asked for a
licence grant. Upstream's own terms are untouched by this entry and by 21.

### 17. The dead include is guarded, not deleted and not replaced

**Decision.** `INCHI-1-SRC/INCHI_BASE/src/ichicano.c` carries
`#ifndef COMPILE_ANSI_ONLY` around its `#include <sys/timeb.h>`, and nothing
else in that file changes. The gate is the published 53-platform `cross-test`
matrix and a settings-only `cross-test.profile.sh` that keeps it whole.
Decision 19 moves those same three lines below `#include "mode.h"`; that is a
placement change and nothing more.

**Why this and not the alternatives.** Three were available. Deleting the
include would break the non-ANSI build, which is the configuration upstream
still ships and the one its own `ichitime.h` is written around. Stubbing
`_ftime` would replace a real dependency with a fake. Adding a configure probe
or a `-D` would move a decision this package can read out of the source. The
guard is not a portability macro invented here: the code the header serves is
already behind this file's own `#ifdef COMPILE_ANSI_ONLY` — upstream `:95`,
patched `:97` — whose `#else` runs to `:412` upstream and `:414` patched, with
both readers of `struct _timeb` and `_ftime` inside it (upstream `:332-335` and
`:395-402`; patched `:334-335` and `:397`/`:402`). `ichitime.h:56` already
carries the same include commented out under the same macro, so the C file and
its own header now say the same thing.

**Why one line is the whole cause for thirteen of the 53 cells.** Read out of
the compiler rather than assumed: `lib/std/zig/LibCDirs.zig:169-181` gives every
`isDarwin()` target — `.maccatalyst` included — the single directory
`lib/libc/include/any-darwin-any`, which has no `sys/timeb.h`, and
`generic-openbsd` and all ten `*-openbsd-*` architecture directories have none
either, while `generic-musl` and `generic-glibc` do. Four Apple cells and nine
OpenBSD cells, and no second line has to change for any of them.
`wasm32-wasi` is not among them, and the reason is worth keeping: its own
`wasm-wasi-musl` directory has no header either, but its four-directory search
path also carries `generic-musl`, which does.

**The same question, asked of the compiler rather than of the directory.**
Seven `zig cc -E -H -include sys/timeb.h` probes, exit code and diagnostic
recorded per target (`local://foundation-cross-test-timeb-header-availability.json`):
present on `x86_64-linux-gnu`, `x86_64-linux-musl`, `x86_64-netbsd` and
`wasm32-wasi` with no diagnostic; present on `aarch64-freebsd` with upstream's
own `#warning "this file includes <sys/timeb.h> which is deprecated"`; **absent
on `aarch64-macos` and `x86_64-openbsd`**, both exit 1. So the absent pair is
macOS and OpenBSD and WASI is not in it — and a target that owns no libc include
directory of its own is not a target without the header, which is the OpenBSD
case exactly. This is L20's fix, run.

**Why the record moved rather than shrank.** `UPSTREAM.sha256` keeps all 109
records and re-derives one line, from the patched file's own bytes. Dropping the
path, or leaving the old digest beside a patched file, would have made the
record quiet about exactly the divergence this patch exists to fix — the L15
lesson again. Every receipt that verified the old `ichicano.c` line is now
history for it, and none is carried forward.

**Cost, and what was not paid.** Two inserted lines in one C file, two new
records' worth of prose, one new Bash file, and — as written — no compile of any
kind. That has since closed **for this placement**: the 53-cell matrix and the
first `2026-10-02` native wave both compiled the file exactly as decision 17
left it, 20 cells executing 16 tests each and 33 compiling only, every cell
exit 0 (`local://foundation-cross-test-matrix-inchi.json`), and that wave 16/16
in Debug and 16/16 in ReleaseSafe plus smoke, install and consumer. Both are
**history for the file as it ships**, because decision 19 moved the guard after
them; what the shipped arrangement has of its own is in decision 19 below. What
was not paid, then or now: no chemistry, algorithm, ABI, allocator, option,
default, flag or build mode; no suppressed diagnostic; no removed source; no
substitute header; no narrowed matrix.

**Target bound.** Any vendored C file that includes a header its own guard has
already made dead, on any libc that dropped that header. The narrow six-target
matrix sees it on one target; the full 53 covers thirteen — four Apple and nine
OpenBSD — so widening the gate changed the size of this fix and not its shape.

### 18. The profile names the build step and nothing else

**Decision.** `cross-test.profile.sh` sets `CROSS_BUILD_STEP=test` and sets
nothing else: no `CROSS_MATRIX`, no `TARGETS`, no hook functions, no
`CROSS_BUILD_ARGS`, no host path, no resource limit.

**Why.** A profile is trusted Bash the harness sources, and a package that
adds one is choosing how it is measured. Choosing *less* is the honest form of
that choice here. The matrix is published and must stay whole, including the
cells this package refuses; the runners are the harness's policy and must stay
harness-owned, so a target with no runner is reported as build-only rather than
as a pass; and `-Doptimize` is the package's own default Debug mode, which the
gate for this wave states. Anything a profile added here would be a decision the
package has no evidence for, made in the one file that is executed.

**Why it is in `.paths`.** It is Bash the harness runs, not documentation.
A dependent that fetched the package should get the same gate the tree was
measured through, which is the same reasoning decision 15 used for the
Apache-2.0 text.

**Target bound.** Any package measured by a harness that discovers a root
profile. The lesson is kept as L19.

### 19. The guard goes where the macro is defined, not where the include is

**Decision.** The `#ifndef COMPILE_ANSI_ONLY` block from decision 17 now sits
immediately after `#include "mode.h"` and immediately before `#include
"ichicano.h"`, at `INCHI-1-SRC/INCHI_BASE/src/ichicano.c:49-51`. The three
lines are byte-identical and in the same order; only their position moved. The
file is still 107427 bytes and 2744 lines — byte for byte decision 17's file —
so no line number shifted between the two placements: everything at or after
`:53` reads as it did, and the three lines changed position only inside
`:45-52`, where they read at `:46-48` before and at `:49-51` now, with
`#include "mode.h"` at `:48` here and at `:51` there. What did shift is every
line **against upstream**, which has no guard: the two inserted directive lines
sit above `:50`, so from there to the end this package cites everything two
higher than upstream does.

**Why the position was wrong.** `mode.h:197-201` is where that macro comes
from:

```c
#if ( !defined(_MSC_VER) || defined(TARGET_API_LIB) || defined(TARGET_EXE_USING_API))
#ifndef COMPILE_ANSI_ONLY
#define COMPILE_ANSI_ONLY
#endif
#endif
```

A guard above that header tests a macro the file has not defined for itself. It
appeared to work here because `core_macros` also puts `-DCOMPILE_ANSI_ONLY=1`
on the command line — **an argument this package supplies, not a property of
the source**, which is L11's distinction applied to a placement rather than a
flag. Below `mode.h` the guard is upstream's own condition, self-satisfied
inside the file: defined, the include is skipped; undefined, as under MSVC, the
include is taken exactly as upstream wrote it and the non-ANSI build decision
17 was written to protect still gets its header.

**Why it was not visible sooner.** **Both placements compile identically under
a `-D`, so no target in either matrix could ever have found it.** The six-target
`check` baseline and the 53-cell `cross-test` matrix both passed on the first
placement; only reading `mode.h` shows the difference. That is the shape of a
finding that a gate cannot produce, and it is why the lesson is kept as L21
rather than folded into decision 17.

**Cost, and what was not paid.** A move of three lines inside one file, one
re-derived record line, and no cross-platform compile.

**What has been observed on this arrangement.** Three waves. The six-target
`check` baseline is **6 of 6 green** in the workspace's 48-cell explicit-target
round, exit 0 on every cell, `Build Summary: 6/6 steps succeeded` on every cell,
between `2026-10-02T07:23:30.237Z` and `2026-10-02T07:23:32.431Z`,
`complete: true`, `unrun_cells: []` — and `aarch64-macos-none`, the target
decision 17 existed for, is green at its own target for the first time in this
package's history (`local://foundation-cross-test-final-baseline.json`, per-cell
`local://foundation-cross-test-final-baseline-inchi-<target>.log`). The stable
native wave is green in both modes on the same tree: `test smoke install
-Doptimize=Debug`, 16/16, 11/11 steps, exit 0; `test smoke
-Doptimize=ReleaseSafe`, 16/16, 9/9 steps, exit 0; and the `consumer` build
through `dep.module("inchi")`, 6/6 steps, exit 0
(`local://foundation-cross-test-stable-native.json`). And the 53-cell
`cross-test` matrix has been re-run **on this placement**: run
`20261002-071259-33035-20483`, generated `2026-10-02T07:12:59Z`, harness
`exit_code: 0`, `target_count: 53`, counts `pass 20`, `fail 0`, `build_only 33`,
`partial 0` — 20 cells executing the full 16-test suite, 320 tests actually run,
and 33 compiled only with `reason: runtime_unavailable`, so **no foreign BSD,
macOS, Mac Catalyst, Windows or WASI binary was executed anywhere in it**
(`local://foundation-cross-test-final-current-inchi.json`, per-cell
`local://foundation-cross-test-final-current-inchi-<target>.log`). The earlier
53-cell run over decision 17's placement — `local://foundation-cross-test-matrix-inchi.json`,
run `20261002-040235-43019-14341`, the same counts and the same 320 executed
tests — is history for this placement and stays history.

**Superseded as current, and by what.** Every `16` above is the suite the file
declared on `2026-10-02`; `tests.zig` as it ships declares **twenty-two**
top-level test blocks, six of them added by the migration waves after those
waves ran. All three receipts are therefore **history for the file as it
ships** — the `check` baseline still describes the guard placement, because
compile coverage does not move when a test is added, but the wave's and the
mattery's test totals do not describe this file. L29 carries the correction.

**Handed over rather than claimed.** Two closures belong to the driver, and this
package states no result for either. The first is the whole-record
`sha256sum -c UPSTREAM.sha256` replay over the re-derived `ichicano.c` line:
the earlier package-local receipts are history for that arrangement; the
current source/fetched replay belongs to the external driver closure. The
second is the final filtered `zig fetch` with its source, fetched-integrity and
fetched-consumer checks over the settled documents, whose result and identity
are recorded outside this package, in the root ledger's `FORKS.json` under
`cross_test_wave` and `cross_test_wave.materialized_packages.inchi`, and in
`local://foundation-cross-test-package-regression.json` — this file's own bytes
are an input to that identity, so it cannot also be where the identity is
recorded. `zig build -fsys=inchi` is genuinely unrun and stays that way: it
needs an installed `libinchi` carrying its own matching `inchi_api.h` and
`ixa.h`, and no such pair was available here. **No CI was executed for any of
this, and no workflow result is reported anywhere in this file.**

**What was not paid, either way.** No chemistry, algorithm, ABI, signature,
allocator, canonicalisation step, option, default, flag or build mode, on any
target in any optimisation mode; no source file removed; no diagnostic
suppressed; no substitute header; and the `-DCOMPILE_ANSI_ONLY=1` the build
already passed is left exactly where it was — the move makes the source correct
on its own, it does not withdraw the argument. The move is not something any
gate can confirm either: see L21.

**Target bound.** Any vendored C file whose own portability macro is defined by
a header it includes *after* the site it wants to test. The bound is a file
layout, not a target: it is present on every platform at once and invisible to
all of them.

### 20. "Run or install" is a question about the host, asked of the artifact

**Decision.** `runConsumer` (`build.zig:566`) takes its step from
`hostCanExecute` (`build.zig:632-672`), which asks
`std.zig.system.getExternalExecutor` (`lib/std/zig/system.zig:42`) — the
predicate `std.Build.Step.Run` asks about the artifact it is about to spawn
(`lib/std/Build/Step/Run.zig:1268`). The options that predicate is handed are
filled in from the same two facts `Run` fills them in from, `.link_libc` and
`.qemu_fixes_dl`; the build runner's `-fqemu`, `-fwasmtime`, `-fwine`,
`-fdarling`, `-frosetta` and `--libc-runtimes` travel to the nested build so
the decision here and the execution there resolve one executor; and `.qemu`
answers `!candidate.isGnuLibC() or b.libc_runtimes_dir != null`
(`build.zig:664`) because that is the one arm where the predicate and `Run` can
disagree.

**Why the old predicate could not answer it.** `Target.Query.isNative()`
(`lib/std/Target/Query.zig:396-398`) is a question about *spelling*: it is
`isNativeTriple() and ofmt == null`, and `isNativeTriple()` (`:392-394`) is
`isNativeCpu() and isNativeOs() and isNativeAbi()`, with `isNativeAbi()`
(`:388-390`) demanding `os_tag == null and abi == null`. Naming a triple fills
those fields, so on this x86_64 Linux GNU host `-Dtarget=x86_64-linux-gnu` was
not "native" and the step installed. It never asked whether anything here could
execute the binary; it asked whether the user had declined to type a target.
An answer that depends on how the question was spelled is not an answer, and it
is worse than useless here: the step is named for running, and it succeeded
quietly at not running.

**Why this predicate and not a hand-written one.** There is a second decision
inside the nested build — `Run` asks again, about the artifact it holds — and a
build script that answered the question differently from `Run` would produce a
step that says "run" and then fails, or one that installs when the user enabled
an executor. Filling the same options from the same facts collapses the two into
one question asked identically, so they cannot disagree by construction. That
is the same discipline as decision 9 (one allocator, and it is upstream's) and
L11 (a flag is an argument, not an inference), applied to a build step.

**The one place they still differ, and why it is carried explicitly.** `Run`
gates each executor on this build's own switches after the predicate allows it
(`lib/std/Build/Step/Run.zig:1277`, `:1291`, `:1317`, `:1325`); carrying the same
switches in `allow_*` asks the identical question without the second gate. QEMU
is the exception. For a cross libc target `Run` appends `-L <runtime triple>`
(`:1294-1308`) and, with `b.libc_runtimes_dir` unset, calls `failForeign` on
`--libc-runtimes` (`:1310`) — it does not skip and it does not install.
`qemu_fixes_dl` cannot express that, because `getExternalExecutor` enters the
QEMU arm for a foreign CPU on `!cpu_ok` alone (`lib/std/zig/system.zig:95`),
whatever that option says, so it returns `.qemu` in exactly the case where the
option stops describing the situation. Hence the explicit `.qemu` arm. `Run`'s
`need_cross_libc` (`lib/std/Build/Step/Run.zig:1264-1266`) is
`is_linking_libc and (isGnuLibC() or (isMuslLibC() and linkage == .dynamic))`;
the musl half needs `linkage == .dynamic`, and `consumer/` sets no linkage, so
for this artifact the half is false and the `.qemu` arm tests the same fact.
**This branch has never been exercised here** — see L22.

**What it cost.** One function, one call site, and the forwarding of five
switches and one directory onto the nested command line (`build.zig:587-592`).
No chemistry, ABI, algorithm, option, default or build mode moved, and no
upstream source file was touched.

**What was observed, and how far.** Two runs of
`zig build consumer -Dtarget=x86_64-linux-gnu`, both by the parent in this
session and **neither with a `local://` receipt file** — the argv and the
output lines are quoted in §35 and no receipt is named, because inventing one
would be a fabricated identifier.

* **Before.** `Build Summary: 2/2 steps succeeded`, `consumer package success
  10s`, exit 0, and no program output at all.
* **After.** The `inchi consumer` banner, the four PubChem answers — water,
  methane, ethanol and heavy water with their published identifiers and keys —
  both `check` verdicts, `consumer ok`, `Build Summary: 2/2 steps succeeded`,
  exit 0.

Those four answers are not new evidence about the library: `consumer/` has been
run as its own `zig build run` through the whole of this package's history, and
§33's stable native wave is one of those runs. What is new is that *this
package's own step* reaches them, from the package root, with an explicit
target.

**Not claimed.** The QEMU arm, every foreign-architecture answer, and every
fresh native, six-target baseline, 53-cell matrix and package wave over this
change. The mechanism behind them is read out of the pinned compiler's own
`lib/std` and is `SOURCE-CONFIRMED`; the behaviour is `PENDING-VERIFICATION` and
no gate here has moved it.

**Target bound.** Any build step deciding between *running* a nested program and
*building* it, where the artifact's own spawn logic already answers the question.
The bound is the artifact's shape: it links libc through an imported module,
declares no linkage of its own, and is run from its own package. A consumer that
declared a linkage would need its own `need_cross_libc`, and the musl half
would start contributing.

The lesson is L22.

### 21. The fork grant is MIT plus upstream's own two conditions, and no identity

**Decision.** [`FORK-LICENSE.md`](FORK-LICENSE.md) defines
`LicenseRef-InChI-MIT-Conditional` for every file this fork adds or edits: the
MIT text verbatim, **plus** (a) the InChI attribution-notice obligation and the
compulsory project banner, both quoted from upstream's own bytes, and (b)
upstream's coupling condition from `sha2.h:12-13` — redistribute and modify
only as a part of the InChI software package. The copyright line reads "the
authors of this `inchi` Zig SDK package", because **no personal or corporate
identity was supplied and none is invented**; the owner substitutes that line
before publication.

**Why `LicenseRef-` and not `MIT`.** L13 already established that this package
is not single-licensed. Adding to that, a scanner that finds `MIT` stops at the
permission grant and misses both conditions. A `LicenseRef-` identifier is
SPDX's own mechanism for exactly this, and it is defined in full in this
repository, so the identifier is self-contained rather than a lookup.

**Why the banner condition is not decoration.** It is the reason the
authorised `ichiparm.c` patch substitutes the pinned source tag for
`__DATE__`/`__TIME__` instead of deleting the banner. A patch that removed the
version stamp from the usage text would satisfy reproducibility by breaking
identification. The two requirements agree, and the licence record is where
that agreement is written down.

**Target bound.** Any fork whose upstream ships a permissive licence *plus*
file-level obligations. The general form: a fork's own grant should match the
**primary** upstream term including its conditions, not the shortest common
denominator of the permissions involved. Where no copyright holder is
established, an identity placeholder plus an explicit statement that none is
asserted beats inventing one.

## Lessons

### L1 — A `*/` inside a C comment ends the comment, and the rest becomes code

* **Condition.** A block comment that names C constructs, written as
  `the whole Get*/Free*/Check* surface`.
* **Symptom.** **Observed**, five times over: `translate-c 231 errors`,
  `error: translation failure`, first error at `translate.h:9:25: error: type
  specifier missing, defaults to 'int'`. Receipts
  `…-current-debug-49`, `…-current-smoke-59`, `…-current-install-60`,
  `…-current-releasesafe-62`, `…-current-consumer-65`.
* **Fix.** Reword the prose; do not escape it. The fix that does not work is
  breaking the token up in a way the reader has to decode.
* **Target bound.** Any C or C++ header that a translator reads, and any
  comment that quotes a pointer-declaration pattern. The failure reads as a
  header problem, not a comment problem, which is why it costs a full gate
  cycle to diagnose.
* **The mirror.** A `/*` inside a block comment is the other half of the same
  trap. The comment does not nest, so nothing is miscompiled, but a compiler
  that looks for nested openers warns about it and Zig's ReleaseSafe C backend
  promotes that warning to an error. It is what `ichiparm.c:2597` carried, and
  what the patch in decision 13 removed.
* **Not observed.** Whether `IXA_*` in the reworded text is safe was *checked*
  rather than assumed — `_*` is not a terminator — but it was not proven by a
  failing-then-passing pair of runs.

### L2 — A binding that drops a C string's sentinel makes every caller copy

* **Condition.** `addTranslateC` publishes `[*c]u8` for a `char *` return, and
  the binding re-declares the accessor as `[]const u8`.
* **Symptom.** **Observed** at the call site, not the accessor:
  `smoke.zig:88:36: error: expected type '[:0]const u8', found '[]const u8'`,
  `note: destination pointer requires '0' sentinel`
  (`…-repaired-smoke-proof-69.log`).
* **Fix.** Return the sentinel the helper already computed. Here
  `spanOrNull` returned `?[:0]const u8` through `std.mem.span` and the six
  accessors re-declared the type without it, so the terminator cost nothing to
  keep and everything to lose.
* **Target bound.** Any C facade over allocate-in-C, read-only-here APIs.
* **The general form.** When a binding must erase a terminator, every caller
  downstream pays a copy. Fix it at the accessor, once, or pay for it at every
  call site forever.

### L3 — The translated declaration is the C declaration, not the one you meant

* **Condition.** A C entry point takes a non-const struct pointer
  (`inchi_dll.c:242`, `inchi_dll.c:2114`) and the binding's helper returns that
  struct by value, which the call site then bound with `const`.
* **Symptom.** **Observed**: `zig/root.zig:572:36: error: expected type '[*c]T',
  found '*const T'`, `T = translate.struct_tagINCHI_Input`, `cast discards const
  qualifier` (`…-repaired-smoke-proof-69.log`).
* **Fix.** A mutable local for the struct; keep the borrowed contents const and
  uncopied. Do **not** reach for `@constCast` on the struct — it would silence
  the error by discarding the distinction the C declaration is making.
* **Target bound.** Same as L2.
* **The honest form of the contract.** This one is only sound because the
  wrapped entry points copy every field out before using any of it and write
  none of it back. That is a claim about upstream, it is checkable, and the line
  numbers are in the source so a re-sync can re-check it.

### L4 — A green smoke root proves only what the smoke root called

* **Condition.** Zig analyses a public function's body lazily: if nothing calls
  it, it is not compiled.
* **Symptom.** **Not observed as a failure** — the observation is its absence.
  `fromMolecule.full` and all three `fromIdentifier.*` carried the same `const
  input` defect as `fromMolecule.standard` and would have failed the moment
  `tests.zig` instantiated them; `smoke.zig` calls one of the five.
* **Fix.** A `check` step that compiles the test root and the smoke root for
  every target, so the coverage comes from what the roots reference rather than
  from what happened to be reached.
* **Target bound.** Zig 0.16.0; any Zig package whose public surface is wider
  than its demo.
* **The corollary that cost real time.** `tests.zig` had **never been compiled**
  at all: it used an undeclared `odd` variable at three places and compared two
  slices with `!=`. Both are hard errors. Neither was caught, because the only
  gate that ran was `smoke`, which does not import `tests.zig`.

### L5 — A file-scope `const` initialiser is already comptime

* **Condition.** `const x = comptime blk: { … inline for … };` at file scope.
* **Symptom.** **Observed**: `build.zig:478:30: error: redundant comptime keyword
  in already comptime scope` and `build.zig:480:5: error: redundant inline
  keyword in comptime scope` (`…-repaired-debug-23.log`).
* **Fix.** Drop both keywords. The block stays a comptime expression; it just
  does not need to say so twice.
* **Target bound.** Zig 0.16.0. The keywords are correct inside a function body
  and wrong at file scope, which is why the same line can be right in one
  function and wrong in another.

### L6 — A local that shadows a file-level function is an error

* **Condition.** `Scratch.addAtom` bound `const index = self.atom_count;` in a
  file that also declares `fn index(atom: usize) i16`.
* **Symptom.** **Observed**:
  `zig/molecules.zig:71:15: error: local constant shadows declaration of
  'index'`, `note: declared here: fn index(atom: usize) i16`
  (`…-repaired-smoke-proof-69.log`).
* **Fix.** Rename the local to `slot`, and give the surviving helper a doc
  comment saying what it converts. A rename plus a comment is better than a
  rename alone: the next reader learns which of the two `index`-shaped things
  they are looking at.
* **Target bound.** Zig 0.16.0.

### L7 — `==` and `!=` do not exist for slices

* **Condition.** Comparing two `[]const u8` for inequality in a test.
* **Symptom.** **Not observed** — found by reading. The language reference lists
  Equality for integers, floats, bool, type and packed struct only, no `==` on a
  slice appears anywhere in the pinned toolchain's `lib/`, and the standard
  library routes slice comparison through `expectEqualSlices`.
* **Fix.** `!std.mem.eql(u8, a, b)`. It is correct under either reading of the
  reference and strictly stronger than `==` would be, so nothing depends on
  which reading is right.
* **Target bound.** Zig 0.16.0; any test comparing two slices.
* **Worth separating from L4.** L4 is about a gate not running; this is about
  reading being the only detector. The two together are the argument for
  compiling the test root in the cross matrix even when nothing can execute it
  there.

### L8 — Upstream holds option strings as templates and substitutes the prefix at run time

* **Condition.** Upstream's strict option string is the template
  `" ?FixedH ?RecMet ?SUU ?SLUUD"`, and `CheckINCHI` overwrites the four
  question marks with `INCHI_OPTION_PREFX` before using it
  (`inchi_dll.c:965`). The prefix is `/` under `_WIN32` and `-` elsewhere
  (`mode.h:262-268`), and `ichiparm.c:1221` recognises an option only by its
  first byte.
* **Symptom.** **Not observed.** The non-Windows arm was correct; only the
  `.windows` arm carried the unexpanded template, and the Windows arm is
  reachable here only through a compile-only `check`.
* **Fix.** Apply the substitution at comptime per target, and say in the comment
  that it has been applied and why.
* **Target bound.** Windows targets.
* **Why it matters beyond Windows.** This is the general shape of a silent
  misconfiguration: a value that is correct on the machine that tested it and
  wrong on the one that did not, with no diagnostic on either.

### L9 — A platform header outside the guard that needs it is still a dependency

* **Condition.** `INCHI_BASE/src/ichicano.c:46` includes `<sys/timeb.h>` with no
  `#ifdef`. The code that uses it — `struct _timeb` and `_ftime` at lines
  325-412 — is inside the `#else` of `#ifdef COMPILE_ANSI_ONLY`
  (`ichicano.c:95`, `#endif` at `ichicano.c:412`), and this build defines
  `COMPILE_ANSI_ONLY=1`, so that branch is not compiled here. The
  **include** is not conditional, so the header is required on every target.
* **Symptom.** **Observed, on one target and not the other.**
  `zig build check -Dtarget=aarch64-macos-none` fails with
  `ichicano.c:46:10: error: 'sys/timeb.h' file not found`
  (`…-check-aarch64-macos-none-204.log`), exactly as the header reading said.
  `zig build check -Dtarget=wasm32-wasi` **succeeds** — `compile lib inchi Debug
  wasm32-wasi success`, 6/6 steps
  (`…-check-wasm32-wasi-207.log`) — on a sysroot whose headers read the same way.
  The other four targets are green.
* **Decision.** Do not modify upstream's source to work around it. Record the
  boundary, attempt all six targets, report each outcome as it came out, and
  carry no `continue-on-error`.
* **Target bound.** `aarch64-macos-none`, and any future Zig whose libc sysroot
  drops `timeb.h` for a target upstream's sources also build on.
* **What the pair of runs is worth.** The header survey was right about macOS
  and wrong about WASI, and neither the survey nor a prediction could have told
  us which. A source-level dependency is a hypothesis about a toolchain; only a
  compile settles it, which is why all six are attempted and only the receipts
  are reported.
* **Resolved, and where.** Decision 17 guarded the include and decision 19 moved
  that guard below `#include "mode.h"`, which is the header that defines the
  macro. The observed outcome for decision 17's placement is the 53-cell matrix:
  53 cells, 20 executed at 16 tests each, 33 compiled only, every cell exit 0
  (`local://foundation-cross-test-matrix-inchi.json`) — history for the shipped
  file, because decision 19 moved the guard after that run. Decision 19's
  placement has its own receipts: the six-target `check` baseline green in all
  six cells including this one, in that 48-cell round
  (`local://foundation-cross-test-final-baseline.json`); the stable native wave
  16/16 in Debug and 16/16 in ReleaseSafe plus smoke, install and consumer
  (`local://foundation-cross-test-stable-native.json`); and the 53-cell matrix
  re-run on the shipped placement — 53 cells, 20 executed at 16 tests each, 33
  compiled only, every cell exit 0
  (`local://foundation-cross-test-final-current-inchi.json`). The paragraphs
  above are kept as what was decided *at the time*, on the evidence available
  then.

  Every "shipped placement" above is history for the file as it ships in that
  second sense too: the file declared sixteen tests then and declares
  twenty-two now (L29). The guard placement these receipts cover is still the
  one in the tree; their test totals are not this file's test totals, and no
  test pins a count.

### L10 — An integrity record over a subset and an archive digest over the whole tree are different numbers

* **Condition.** The parent recorded a `git archive` SHA-256 of the full
  upstream tree at the pinned commit; this fork records per-file digests over the
  109 paths it hashes, which is a subset of what it ships.
* **Symptom.** **Not a failure.** The two will never match, and treating a
  difference as corruption is the mistake this note exists to prevent.
* **Fix.** Record both, say what each is over, and state which one a re-sync can
  check without a network. The per-file record can be re-derived from the tree
  alone; the archive digest needs a re-fetch.
* **Target bound.** Any fork that publishes both a parent-supplied archive
  receipt and its own per-file record.

### L11 — A sanitizer setting is an argument, not an inference

* **Condition.** `build.zig:453` creates the C core module with
  `.sanitize_c = .off` written out explicitly.
* **Why it is there.** A null `sanitize_c` already means no `-fsanitize` flag,
  so the explicit `.off` is defence in depth, and the Debug behaviour a C
  sanitizer changes is the behaviour the core's own wraparound and narrowing
  arithmetic expect — `FullMaxClock` and `HalfMaxClock` are built from
  `(clock_t)(-1)` at `ichicano.c:126-127` — the shipped post-patch numbering
  (`UPSTREAM.md` carries the upstream baseline for the same two lines).
* **The distinction worth keeping.** This package passes `.off`. That is an
  argument it supplies. It is *not* the claim "this toolchain defaults to off",
  and a nullable build field that happens to be null is not evidence of a
  default either way. Record the argument, not the inference.
* **Target bound.** Zig 0.16.0's `Module.sanitize_c`.

### L12 — `.paths` decides what a dependent receives, and it is a hard configure error

* **Condition.** A package that ships provenance documents. `.paths` is what the
  package manager hashes and ships.
* **Symptom.** Not observed here — but a `.paths` entry naming a file that does
  not exist is a hard configure error, so writing documents and adding them to
  `.paths` has to be one change, not two.
* **The live instance, closed.** `build.zig.zon` `.paths` did **not** list
  `UPSTREAM.sha256`, so the integrity record did not travel with the package.
  `.paths` lists it now, beside the documents, so `sha256sum -c UPSTREAM.sha256`
  works in an unpacked package and not only in a clone. The same edit also added
  `INCHI-1-SRC/INCHI_API/tbb/LICENSE`, which is the other half of this lesson:
  a licence text a dependent receives must be *listed*, and a file that is listed
  must be *hashed*.
* **Target bound.** Zig 0.16.0 package manager; any package adding a file after
  its manifest was written.

### L13 — "The package is MIT" can be wrong three ways at once

* **Condition.** A C library whose own sources bundle a SHA-256 implementation,
  a formatting library and a vendor allocator header.
* **Symptom.** **Not a failure** — a documentation hazard, found by reading
  rather than by a gate. Of the 105 shipped native files, 100 carry the MIT
  notice. The five that do not are `sha2.c`, `sha2.h`,
  `tbb/tbbmalloc_proxy.h`, `CMakeLists.txt` and `readme.txt` — and of those,
  `sha2.h` qualifies its own MIT grant as valid *only in combination with the
  InChI package*, and `tbbmalloc_proxy.h` is Intel's **Apache-2.0**.
* **Fix.** Enumerate the exceptions by file with their own terms quoted, and
  record the obligation each one creates. The `tbb/tbbmalloc_proxy.h` obligation
  is now discharged — `.paths` ships upstream's own
  `INCHI-1-SRC/INCHI_API/tbb/LICENSE` beside it — and it was discharged in the
  manifest rather than in `NOTICE.md`, because a dependency's content is decided
  by `.paths` and a documentation edit could only have redescribed the gap.
  Enumerating the exceptions is still the work: the count (100 of 105 carrying
  the notice, and which five do not) is what tells a reader which sentence in
  their SBOM to trust.
* **Target bound.** Any bundled-vendor-dependency C library. The counting is
  cheap — one pass over the shipped set looking for the notice — and it is the
  difference between a licence claim and a licence fact.

### L14 — A sentinel slice that includes its terminator names a different string

* **Condition.** A fixture field turned into `[:0]const u8` by appending
  `"\x00"` and keeping the concatenation's length.
* **Symptom.** **Observed**: 13 of 16 tests failing and one crashing, with a
  diff that reads `expected: InChI=1S/H2O/h1H2 ^ ('\x00')` against
  `found: InChI=1S/H2O/h1H2 ^ (end of string)`
  (`…-known-answer-debug-156.log`). C reads both strings the same way; Zig does
  not, and `std.testing` prints the difference as a stray NUL rather than as a
  length mismatch.
* **Fix.** Terminate at the value's own length — `(value ++ "\x00")[0..value.len
  :0]` — so the zero sits *at* `len` instead of inside the slice. Because the
  value is `comptime`, that is a static constant, not a copy into a fixed-size
  buffer.
* **Target bound.** Every C-to-Zig binding whose accessors return
  `[:0]const u8`. The cheap check: the byte at `slice.len` must be the NUL, and
  `slice.len` must be the answer's length.
* **General form.** When a sentinel is synthesised, ask whether the terminator is
  *in* the slice or *at* its end. The first is a one-character bug that compiles.

### L15 — A file that `.paths` ships and the integrity record does not hash is unpinned

* **Condition.** A licence gap closed by adding an upstream file to `.paths`
  after `UPSTREAM.sha256` had been written.
* **Symptom.** **Not a failure, and not a warning either.** For one record,
  `sha256sum -c UPSTREAM.sha256` was green over the 108 records it held while the
  package shipped one more upstream file than that. Nothing announces it: the
  two lists simply stop matching.
* **Fix.** Read the record's path set from `.paths` on every re-sync rather than
  from memory, and write the line for anything new. Here that meant hashing
  `INCHI-1-SRC/INCHI_API/tbb/LICENSE` as the 109th record from its own bytes —
  no upstream file was edited — and re-running the gate over the whole record:
  109 records, no failures, exit 0
  (`…-immutable-source-complete-legal-109-240.log`). That receipt was taken
  before the `ichiparm.c` patch of decision 13, and its `ichiparm.c` line is
  history for the same reason L18 sets out; the same 109 are green on the patched
  tree at `-364` and in a fetched copy at `-388`. While the line was missing, the
  documentation said so in the same paragraph that said the gate was green,
  because a reader who sees only the green cell will believe a file nobody
  hashed is pinned.
* **Target bound.** Any integrity record defined as "every file this package
  ships". The record's scope and the manifest's scope are the same set, and they
  drift apart silently.
* **The same change has to fix the prose.** A digest list's header is part of
  the record: it states the count, names what each group is, and lists what is
  deliberately absent. When the 109th line landed, the count line and the
  exclusion line were updated with it, so a reader who trusts the prose and a
  reader who trusts the lines are reading the same set. A header that
  under-counts is worse than no header, because it is the part people quote.

### L16 — An English diagnostic is not a contract, and neither is a buffer length

* **Condition.** Two tests asserting upstream's own incidental detail: the exact
  prose of the proton-move warning, and the character count of an extension
  hash.
* **Symptom.** Not a failure — a liability. Both would turn a green suite red
  for a reworded message or a resized buffer while every behaviour they stood
  next to still held.
* **Fix.** Delete them, and assert what a caller acts on instead: the status, the
  `isWarning()` predicate, the published identifier, its equality with the
  neutral run, and the published keys. Deleted, not re-pinned in weaker form.
* **Target bound.** Any test over a vendored library's wording or internal buffer
  geometry. Upstream's English is a courtesy to a human reading a log; the
  status code is the interface.

### L17 — The flag a vendored library honours is not always the one that owns the dependency

* **Condition.** `COMPILE_ANSI_ONLY=1` removes the *use* of `struct _timeb` and
  `_ftime` from the compile — the `#else` at `ichicano.c:95`–`412` — while the
  `#include <sys/timeb.h>` at line 46 stays outside every guard.
* **Symptom.** **Observed on one target only**: `aarch64-macos-none` fails with
  `'sys/timeb.h' file not found`; `wasm32-wasi`, with the same include and the
  same header survey, compiles.
* **Fix (the decision, not the workaround).** Do not edit upstream's source, do
  not add a build flag, do not hide the include. Attempt every target, report
  what came out, and name the boundary at the level that owns it — here, the
  parent project that carries this package.
* **Target bound.** Any vendored C library whose platform includes are
  unconditional while the code behind them is conditional. Reading the source
  tells you a dependency exists; only a compile tells you which targets it
  breaks.
* **Resolved, and how.** The owner authorised a bounded portability fix and
  decision 17 applied it: the include is now inside `#ifndef
  COMPILE_ANSI_ONLY`, the same macro that already excluded both of its readers.
  The "fix" paragraph above is kept as what was decided *at the time*, on the
  evidence available then; the resolution is recorded beside it rather than by
  rewriting the decision. Decision 19 then found that the guard sat above the
  header that *defines* that macro and moved it below `mode.h:48`, so the guard
  is upstream's own condition rather than a bet on this package's `-D`. That
  placement has since been compiled — the six-target `check` baseline green in
  all six cells including this one, and the stable native wave 16/16 in Debug
  and 16/16 in ReleaseSafe plus smoke, install and consumer — **history for the
  file as it ships**, since the file declares twenty-two tests now and those
  sixteen are the ones it declared then (L29) — while the
  53-cell matrix, which compiled the first placement, stays history for it. L20
  records what the original header survey got wrong.

### L18 — Patching a file you also pin changes what every earlier receipt means

* **Condition.** A vendored C file edited once, on purpose, so that a mode
  compiles: `INCHI-1-SRC/INCHI_BASE/src/ichiparm.c` for Zig's ReleaseSafe C
  backend, under decision 13.
* **Symptom.** **Not a failure, and nothing announces it.** The integrity record
  still validates and no gate turns red, so the edit silently invalidates three
  things a reader would otherwise take at face value: one of the pinned digests
  is no longer the vendor's, a clean `git diff` against the upstream commit no
  longer describes the tree, and every receipt in the package now describes a
  tree that is no longer in the repository.
* **Fix.** Re-derive the one record that changed and write the vendor's old
  digest down as a baseline, so the divergence is inside the record instead of
  outside it. Leave every earlier receipt named and dated as it was observed —
  it is still evidence about the tree it was taken on — and say, in the one
  place a reader lands on the table, which receipts cover the patched tree now
  and which are history.
* **Target bound.** Any fork that edits a file it also pins. The two things an
  integrity record normally buys — that the bytes are the vendor's, and that
  they have not moved since the receipt — are separate properties, and the edit
  costs the first one for exactly the paths it touches.
* **The general form.** The edit is cheap and the bookkeeping is the work.
  Budget the record, the preserved baseline and the receipts that just became
  history as part of the patch, not after it.

### L19 — A settings-only harness profile is the honest default, not an empty one

* **Condition.** A harness discovers `./cross-test.profile.sh` at the project
  root and sources it as trusted Bash, before it reads any matrix or runner
  name.
* **Symptom.** **Not a failure.** The package cannot say how it wanted to be
  measured, and a package that *does* ship a profile has a new way to be wrong:
  it can quietly narrow the matrix, install an artifact hook, force a runner, or
  hard-code a path that exists only on the machine that wrote it.
* **Fix.** Write the one decision the package actually owns —
  `CROSS_BUILD_STEP=test` — and put every non-decision in a comment that says
  why it is absent: no `CROSS_MATRIX`, no `TARGETS`, no hooks, no
  `CROSS_BUILD_ARGS`, no host path, no resource limit. Ship it in `.paths` and
  record it in `NOTICE.md` with no licence asserted, because it is executed code
  and not documentation.
* **Target bound.** Any package measured by a harness that discovers a root
  profile. Runner policy stays with the harness, and that is what makes a
  runner-less target report as build-only instead of as a pass.

### L20 — A header can be absent from a target's own directory and still present on its path

* **Condition.** Asking "does `lib/libc/include/<arch>-<os>-<abi>/sys/timeb.h`
  exist?" as the portability question.
* **Symptom.** **The wrong answer, twice.** `wasm-wasi-musl` has no
  `sys/timeb.h` and `wasm32-wasi` compiles anyway, because a non-Darwin target
  gets a *four* directory search path and `generic-musl` carries the header;
  and `any-linux-any` has none while every Linux target compiles, because
  `generic-glibc` or `generic-musl` has it first. A survey of one directory
  would have named WASI broken and Linux broken.
* **Fix.** Read the include-path assembly itself — `lib/std/zig/LibCDirs.zig`
  `:169-181` for Darwin's single directory and `:183-236` for the four-directory
  list — and survey every directory a target actually searches, in order. **Or
  stop surveying and ask the compiler**: seven `zig cc -E -H -include
  sys/timeb.h -x c /dev/null` probes, one per target, settle the whole question
  with an exit code each (`local://foundation-cross-test-timeb-header-availability.json`).
  That run also corrects the broad form of this lesson in both directions — the
  header is **absent only on `aarch64-macos` and `x86_64-openbsd`**, present with
  no diagnostic on `x86_64-linux-gnu`, `x86_64-linux-musl`, `x86_64-netbsd` and
  `wasm32-wasi`, and present on `aarch64-freebsd` with upstream's own
  deprecation `#warning`. It is not "absent everywhere but Windows", and it is
  not "absent on every non-glibc libc" either.
* **Target bound.** Any cross-platform C gate decided by asking whether a
  header exists. The same rule holds for every `zig cc` target, and it is the
  reason this fix is 13 cells wide rather than 1 or 12.

### L21 — A guard that tests a macro the file has not included yet is a bet on a flag

* **Condition.** `#ifndef COMPILE_ANSI_ONLY` placed above `#include "mode.h"`,
  where `mode.h:197-201` is what defines `COMPILE_ANSI_ONLY`. The build also
  passed `-DCOMPILE_ANSI_ONLY=1`, so the two agreed by coincidence.
* **Symptom.** **None, anywhere, ever.** Every configuration that agrees with
  the `-D` compiles identically with the guard above or below `mode.h`; every
  configuration that disagrees compiles identically too, because the header
  defines the macro itself. **No gate on any target can distinguish the two
  placements**, which is exactly why the first placement survived a 53-cell
  matrix and a green native wave.
* **Fix.** Put the guard after the include that defines the macro it tests
  (`ichicano.c:49-51`, after `mode.h` at `:48`). Three lines moved and no bytes
  added, so no line number shifted between the two placements; measured against
  upstream, which has no guard, every line from `:50` down reads two higher.
* **Target bound.** Any vendored C file whose portability macro is defined by a
  header it includes *after* the site it wants to test. The bound is file
  layout, not target: it is present on every platform at once and invisible to
  all of them.
* **The general form.** L11 says a build flag is an argument, not an inference.
  This is the same trap in the source: a guard that only works because the
  command line agrees with the header is borrowing correctness from the build
  system. Read the macro's `#define` — `grep -rn COMPILE_ANSI_ONLY` finds
  `mode.h:199`, and it is upstream's — before believing a guard's position.

### L22 — A step that should run can succeed at not running, and the evidence looks green

* **Condition.** A build step that branches between *running* a nested program
  and *building* it, deciding from `Target.Query.isNative()`
  (`lib/std/Target/Query.zig:396-398`) rather than from a question about the
  host. `isNative()` is `isNativeTriple() and ofmt == null`; `isNativeTriple()`
  (`:392-394`) is `isNativeCpu() and isNativeOs() and isNativeAbi()`, and
  `isNativeAbi()` (`:388-390`) is `os_tag == null and abi == null`.
* **Symptom.** **Observed**, and it is worse than a failure because there is
  none. `zig build consumer -Dtarget=x86_64-linux-gnu` — on an x86_64 Linux GNU
  host, naming its own architecture — took the `install` branch, and reported
  `Build Summary: 2/2 steps succeeded`, `consumer package success 10s`, exit 0,
  **with no program output at all**. A gate that reads exit status, the summary
  line, or the absence of diagnostics records that run as a pass. The failure is
  in what the step did not print, and no failure-shaped signal exists. Naming a
  triple fills the fields `isNativeAbi()` requires to be null, so the more
  explicit the invocation, the more certainly the step installs.
* **Fix.** Ask `std.zig.system.getExternalExecutor`
  (`lib/std/zig/system.zig:42`) — the predicate `std.Build.Step.Run` itself calls
  about the artifact it is about to spawn (`lib/std/Build/Step/Run.zig:1268`) —
  and hand the options `Run` fills in from that artifact: `.link_libc` from the
  graph (`lib/std/Build/Step/Compile.zig:1054-1057` computes `is_linking_libc`
  over every module, not just the root one) and `.qemu_fixes_dl` from the
  target's libc and `b.libc_runtimes_dir`. Carry the build runner's `-fqemu`,
  `-fwasmtime`, `-fwine`, `-fdarling` and `--libc-runtimes` onto the nested
  command line so both graphs resolve one executor. Carry the one gate
  explicitly: `.qemu` answers `!candidate.isGnuLibC() or b.libc_runtimes_dir !=
  null`, because `Run`'s QEMU arm calls `failForeign` on `--libc-runtimes`
  (`lib/std/Build/Step/Run.zig:1310`) — a **failure**, not a skip and not an
  install — while `getExternalExecutor` has already returned `.qemu` on `!cpu_ok`
  alone (`lib/std/zig/system.zig:95`), so the option cannot carry the refusal.
* **Target bound.** Any build step that chooses between running and building a
  nested program, in any build system where the artifact's own spawn logic
  already answers the question. The bound is the artifact's shape, not the
  platform: a consumer that links libc through an imported module and declares
  no linkage of its own needs exactly this `need_cross_libc`; one that declares
  a linkage needs its own, and the `isMuslLibC() and linkage == .dynamic` half
  of `Run`'s test (`lib/std/Build/Step/Run.zig:1264-1266`) starts contributing.
* **The general form.** A predicate that describes **how the question was
  spelled** cannot answer it, and a step whose expected output is the *absence*
  of output converts "did not do the thing" into "succeeded". Ask what the
  component that will actually perform the action already knows, and read it
  from there rather than re-deriving it; a step whose job is to run something
  should answer "can this host execute it", not "did the user type a target".
  The general trap is L11's: the old predicate was not a considered rule but an
  inference standing in for one, and it read as reasonable because a bare `zig
  build consumer` genuinely did run.
* **The proof boundary, stated plainly.** Only the explicit-native path was run,
  by the parent, twice, with no receipt file for either. The QEMU arm, the
  `--libc-runtimes` refusal and the `-fwasmtime`/`-fwine`/`-fdarling` paths are
  `SOURCE-CONFIRMED` from the pinned `lib/std` cited above and have **never been
  executed in this workspace** — no foreign-architecture consumer has run here,
  and no fresh native, matrix or package gate covers this change. Treat the
  mechanism as read and the behaviour as unproven.

### L23 — Relocating a pinned file keeps the digest and changes the path, and only one of those is free

* **Condition.** An integrity record pins upstream's `README.md` by digest. The
  package then needs a `README.md` of its own at that same path, so upstream's
  bytes move to `README.upstream.md`.
* **Symptom.** **Not observed** — no gate has run over the record since. The
  failure mode is visible on inspection: a record line naming a path that no
  longer holds those bytes fails, and a record that is *silently* re-hashed
  against the new file pins the wrong document and looks green.
* **Fix.** Move the bytes, then rename the **record line** to the path the bytes
  are read from and leave its digest exactly as it was. The digest is a
  property of the content; the path is a property of the layout. Say in the
  record's header why the path moved and that the digest did not, and say in
  the prose that every older receipt showing `README.md: OK` is a receipt about
  those same bytes under their old name. Then put the new fork `README.md` on
  the **absent** list, because it is a file the fork writes and every other
  fork-written file is already there.
* **Target bound.** Any integrity or provenance record over a vendored tree
  where a file has to change name. The general form is L15's one step further
  on: renaming a pinned file is a record edit, and the edit that keeps the
  digest is the one that touches only the path.

### L24 — A development shell that contains the package is a build step you pay to open a terminal

* **Condition.** Adding `callPackage ./package.nix { }` to a devenv or flake
  shell's `packages`, next to the toolchain.
* **Symptom.** **Not observed.** The cost is structural: entering the shell
  builds the library, on first entry and again after every cache eviction, and
  it does so *before* the developer has asked to build anything.
* **Fix.** `packages` carries tools. The library is built by `zig build` from
  the repository's own sources inside the shell, which is what a developer
  wants on iteration, and by `nix build` when they want the packaged output.
  Declare the scripts (`build`, `test`, `check`) so the intended commands are
  one word each and cannot drift from what the shell can actually do.
* **Target bound.** Any language whose development loop is "compile the
  sources in this working tree", which is most of them. The general form: a
  shell is an environment; making it also a product means the environment is
  unavailable whenever the product cannot be built.

### L25 — One `builtins.getEnv` in a flake forces `--impure` on everyone downstream

* **Condition.** A devShell that reads `ZIG_GLOBAL_CACHE_DIR` or any other
  environment variable at evaluation time to "helpfully" default a cache path.
* **Symptom.** **Not observed here.** The effect is at the consumer: every
  `nix build` and every other flake that pulls this one in now needs
  `--impure`, or fails, and a build that needs a flag is not hermetic.
* **Fix.** Set nothing. A committed flake must not read the environment of the
  machine that evaluates it; cache locations belong to the caller, who already
  has them exported. The same applies to a Nix derivation: point its caches at
  `$TMPDIR` inside the build rather than at a path the developer's shell
  happens to have.
* **Target bound.** Any committed Nix expression that will be evaluated by
  someone else. The general form: an impure read is cheap to add and makes the
  whole output unusable as a pinned input.

### L26 — A step that forwards an option into a nested build must accept the option too

* **Condition.** A `consumer` step that runs `zig build … -Dlinkage=<v>` as a
  subprocess, where the consumer package's own `build.zig` has never heard of
  `-Dlinkage`.
* **Symptom.** **Not observed.** Either failure is silent in the same way: the
  nested build rejects the unknown `-D` and the run stops, or it ignores the
  flag and the gate **passes against the wrong artifact** — the outer graph
  builds a shared library while the consumer links the static one, and the
  green result is about a build nobody asked for.
* **Fix.** The nested package's `build.zig` declares the same option and passes
  it through to `b.dependency(…, .{ …, .linkage = … })`. Forwarding an option
  is an API: whoever receives it must be able to name it.
* **Target bound.** Any parent build that shells out to a child build with
  `-D` options. The general form is L22's one level up: a gate proves the
  artifact the *innermost* build made, and every layer between the flag and the
  artifact has to carry it.

### L27 — A file the linker reads is a shipped file, whether or not anyone decided that

* **Condition.** A build starts passing a linker version script — here
  upstream's own `INCHI-1-SRC/INCHI_API/libinchi/gcc/libinchi.map` — to control
  the exported symbol set of a shared library. The file lives in a directory
  that the package's `.paths` treats as "carried for provenance".
* **Symptom.** **Not observed** — the packaging and integrity gates for this
  change have not run. The defect is a configure-time one: `.paths` is a hard
  filter (L12), so a build that reads a file the package does not ship works in
  a checkout and fails for the first dependent.
* **Fix.** Promote the file into `.paths` and hash it in the integrity record,
  with a header line saying which linkage and which targets read it. Then move
  it out of the "carried but not part of the package" table and into the
  shipped one, and update the record's own count in the same change.
* **Target bound.** Any vendored tree where a build reads a file that was
  previously kept only for provenance. The general form: "we ship it because
  the build reads it" is a stronger statement than "we ship it because a
  licence obliges us to", and it has to be checked every time the build graph
  starts reading a new input.

### L28 — A shell `${…}` inside a Nix indented string is a Nix expression until you escape it

* **Condition.** `installPhase = '' … -j"${NIX_BUILD_CORES:-1}" … ''`. Inside a
  Nix indented string, `${` opens a Nix interpolation, so the shell's default
  expansion is parsed as Nix.
* **Symptom.** **Observed in this workspace, on a sibling SDK, not here.** A real
  canonical `devenv` evaluation of BLAKE3 failed on exactly this line; it was
  reported to this package's owner while this line existed here too.
* **Fix.** Write the Nix escape for a literal dollar-brace: `-j"''${NIX_BUILD_CORES:-1}"`.
  Nix collapses `''${` to `'${` and the shell sees what it expects. The
  counterpart trap is a **comment** that contains the escape sequence: inside
  `''…''`, writing `''${` to describe the escape terminates the string. Describe
  the escape in words instead of reproducing it.
* **Target bound.** Any Nix string that contains a shell expansion — a job
  count, a cache path, a hook-provided variable. The general form: Nix and the
  shell share `${…}` syntax and disagree about what it means, so every
  occurrence in an indented string must be read as Nix until proven otherwise.

### L29 — A receipt labelled "the file as it ships" stops being that the first time a test is added

* **Condition.** A package's evidence table records a native wave as
  `expected_tests: 16`, `observed_tests_passed: 16`,
  `verification_status: success`, under the label "stable wave, on the shipped
  arrangement", and a later prose entry repeats it as "remains current on the
  same tree". Six further test blocks then land in the same file, on their own
  wave, for reasons that have nothing to do with the recorded run.
* **Symptom.** **No failure, anywhere — which is the problem.** Every recorded
  number stays exactly as true as it was: those waves really did execute
  sixteen tests and really did exit 0, and nothing in the receipts is wrong.
  What is wrong is the *currency*. `tests.zig` as it ships declares
  twenty-two top-level test blocks, so no receipt in this package has ever
  executed the six migration-wave additions, and the six most recently added
  behaviours — the two extended polymer/V3000 routes and the two error-residue
  paths among them — are treated as gated by a run that never reached them.
  A reader checking the file against the table finds the gap; a reader checking
  the table alone finds a green suite one entry shorter than the source.
* **Fix.** Keep the receipts and stop claiming they are current. State the
  count that was actually run as *the count the file declared on that date*,
  point at the entry that carries the correction, and say plainly which
  directions no run has covered. Do not restate a historical row as a
  `SYMPTOM` or a failure: it was a real green run of a real tree, and calling
  it red would be the same error in the other direction. The correction is
  `SOURCE-CONFIRMED` — the count is read out of `tests.zig` — and stays
  `PENDING-VERIFICATION` until a wave runs the suite the file ships.
* **Target bound.** Any package that grows its test file after its evidence
  table was written, in any language and any build system, where the table
  reports test totals rather than a pass/fail bit. The bound is not the
  platform; it is the length of the gap between "the suite as it stood" and
  "the suite as it ships". The general form is L18's, one axis further on:
  patching a pinned file invalidates the digests recorded against it, and
  adding a test invalidates the totals recorded against the suite — and
  neither edit is visible in the receipt that recorded it.
* **No test for this.** The count is recorded in prose, on purpose. A
  permanent test that asserts how many tests the file declares would fail on
  the next test anyone adds, and it would prove nothing about the library: it
  pins a number, not a behaviour. The one test that does belong here is the
  one that exercises the behaviour the added test blocks cover, and those exist
  already.

### L30 — A checked cast on a caller-writable signed field makes one call's answer depend on `-Doptimize`

* **Condition.** A public struct re-exported unchanged from a C header, so its
  count fields keep their C types: an `AT_NUM` is a `signed short`
  (`inchi_api.h:124`), and on a caller-writable struct every value that type
  admits is representable. A private helper converted that count with a bare
  `@intCast`, and the public function that owned the bound called the helper
  *before* its own capacity comparison.
* **Symptom.** **Observed, and the two modes disagreed.** With `num_bonds = -1`
  written by hand, `connect` answered two ways. Debug and ReleaseSafe: **ABRT**,
  "integer does not fit", at the helper's `@intCast` — `bg719`, reported at
  `zig/root.zig:1721` and reached from `connect` at `:1136`. ReleaseFast and
  ReleaseSmall: the unchecked cast wrapped the value, so the input to everything
  downstream was one the language does not define, and the process **did not
  terminate** — `bg721` was still running single-threaded when the driver
  stopped it. No exit status and no output were obtained from that run, so
  nothing is claimed about what it would have printed. Neither answer was the
  module's declared error, and the module header had promised that each bound is
  "checked where a caller can act on it, with an ordinary comparison rather
  than an assertion".
* **Fix.** Make the conversion total and put the range check in front of it.
  `used()` answers 0 for a non-positive count — the same `count <= 0` guard its
  sibling `borrowedArray` already used — so it cannot trap on a value the field
  is declared to hold. A new private `countOutOfRange` then refuses anything
  outside `0..max_bonds_per_atom`, and the public function calls it for both
  ends before either side is written. The refusal **reuses an error that
  already exists**, widening its documentation from the ceiling to the whole
  range; no error was added and no signature changed.
* **Why the same error is honest here.** The API states the range itself at
  `inchi_api.h:171` — "Index j is in the range 0 <= j <=
  (atom[i].num_bonds-1)" — and the compiled closure reads the field as
  `for (j = 0; j < num_bonds; j++)` (`INCHI-1-SRC/INCHI_API/libinchi/src/ichilnct.c:297`).
  A negative count is not a shorter list; it is a record that reads nothing, so
  there is no entry to append to. Refusing it leaves the caller's bytes exactly
  as written, which repairing it would not.
* **Target bound.** Any binding that re-exports a C struct with a signed count
  in it, in any language whose checked and unchecked integer conversions differ
  by optimisation mode — which is Zig, between `ReleaseSafe` and
  `ReleaseFast`. The bound is not the platform and not the library: it is a
  public type whose field range is wider than the invariant the public function
  enforces. The general form is L21's with the direction reversed — L21's
  guard tested a macro the file had not included, and this one trusted that the
  only caller of the reader was inside a range test it had not yet reached.
* **The proof boundary, stated plainly.** The Debug half is a driver
  observation of the defect. The ReleaseFast half is a driver observation of a
  non-terminating run and nothing more: no exit status, no output, no
  diagnosis of what it was doing, and no claim that the unchecked cast is the
  cause of the non-termination — only that the fix removes the negative value
  before any conversion sees it. Nothing in this package has been built or run
  since the change.

### L31 — A header namespace is an upper bound, not a producer promise

* **Condition.** `RetValMol2INCHI` declares separate read and generation
  failure codes, and the facade retains both in `MolfileStatus`.
* **Symptom, source-confirmed.** The type documentation promised those stages
  could be distinguished by status, but the pinned v1.07.5
  `MakeINCHIFromMolfileText` maps reading failures (`inchi_dll_b.c:184-197`)
  and generation failures (`inchi_dll_b.c:229-232`) to the same
  `mol2inchi_Ret_ERROR`. Both become `.rejected`; the producer does not emit
  the header's codes 4 and 5.
* **Fix.** Keep the complete header namespace and correct the type, arm and
  consumer documentation. No new error, inferred stage or additional API
  claims information that the producer does not supply. The existing broken
  counts-line test already expects `.rejected` and is unchanged.
* **Target bound.** The pinned InChI v1.07.5 molfile producer, in linked and
  runtime-loaded routes. Another producer may use more of the header's
  namespace; the facade continues to represent it without a compatibility
  alias or shim.
* **Evidence boundary.** Native assignments remain source-confirmed. On
  2026-10-04, the driver's `bg1114` after wave observed the malformed-molfile
  control return raw 2 and typed `.rejected` serialized as 2, exit 0, under
  Debug/ReleaseSafe and static/dynamic linkage. This verifies that control,
  not generation-failure reachability or non-emission of codes 4/5. Receipt:
  `/home/tmp2/gertullj/scratch/foundation-libs/text-contract-probes/inchi/epochs/key-verdict-native-codes/after/summary.json`.
  `CHANGELOG.md` §42 records the exact sample command and receipt.

### L32 — A nested consumer needs both argument hops and the outer compiler configuration

* **Condition.** An SDK starts a second `zig build` for its consumer package.
  Forwarding the child's `b.args` to its executable is only half the route.
* **Symptom, source-confirmed.** InChI's outer helper dropped the caller's
  trailing arguments, including the documented provider path. It also left
  global-cache selection, job width and summary mode to the child's defaults.
  No runtime failure or completed load is claimed by this source record.
* **Fix.** Append `--` and the outer `b.args` verbatim, last. Emit fixed
  `-j8`, two-token `--summary all` and the inherited global cache path via
  two-token `--global-cache-dir`. Preserve the existing local `consumer`
  cache subdirectory and all resolved SDK, target, CPU and executor choices.
  Preserve `hostCanExecute` and its compile/install-only branch.
  Relay a non-default `b.install_prefix` as two-token `--prefix` before the
  argument handover, making relative paths absolute against the outer build's
  cwd. Preserve omission for the default outer `zig-out` prefix.
* **Target bound.** The nested InChI consumer route under the pinned Zig
  0.16.0 build runner, in linked and loaded configurations. Directly driving
  `consumer/build.zig` already forwarded its own arguments; this correction
  changes the missing outer hop, not that standalone interface.
* **Evidence boundary.** Integrated the build owner's source-only record.
  `CHANGELOG.md` §43, the prefix relay in §45 and the corrected README argument
  description remain `PENDING-VERIFICATION`. The parent owns real native,
  foreign-executor, prefix and provider runs; no permanent forwarding/copy
  test was added.

### L33 — A correct verdict tag can carry the wrong native number

* **Condition.** A facade declares a signed, non-exhaustive enum for native
  return codes but leaves named members implicitly numbered. The native
  taxonomy is not sequential: InChI key verdicts are 0, -1, 1, 2 and 3.
* **Symptom, observed before by the driver.** In the parent's `bg1082` wave,
  `checkKey` returned tag `non_standard` for a native-valid non-standard key,
  but `@intFromEnum` returned 1 while the native call returned -1. The
  Debug/static sample ended in `TypedSerializationMismatch`. Across
  Debug/ReleaseSafe and static/dynamic linkage, the wave reported 16 expected
  numeric defects and 8 passing standard-key or malformed-molfile rows.
* **Fix.** Assign each named `KeyVerdict` its explicit native code, retaining
  `c_int` and `_`. Keep the existing classification mapping and symbolic
  callers. Assert numeric serialization of actual verdicts in the existing
  semantic tests; a tag-only assertion cannot distinguish this defect.
* **Target bound.** InChI's pinned v1.07.5 `RetValCheckINCHIKeyv` contract,
  on linked and runtime-loaded routes. Any binding whose users log, marshal
  or compare native numeric codes has the same boundary even when all
  symbolic classification tests succeed.
* **Evidence boundary.** The parent supplied actual before and after reports.
  On 2026-10-04, `bg1114` observed all 24 after rows passing, exit 0:
  Debug/ReleaseSafe, static/dynamic linkage, five key verdict cases and the
  malformed-molfile control. Native and serialized key codes now agree at
  0, -1, 1, 2 and 3. This scoped `OBSERVED` result establishes neither the
  full suite nor the current 53-target, runtime-loader or nested-helper/prefix
  gates. No worker gate ran; API and tests remain frozen. See
  `CHANGELOG.md` §44 for the exact sample command. After receipt:
  `/home/tmp2/gertullj/scratch/foundation-libs/text-contract-probes/inchi/epochs/key-verdict-native-codes/after/summary.json`.
  Before receipts:
  `/home/tmp2/gertullj/scratch/foundation-libs/text-contract-probes/inchi/epochs/key-verdict-native-codes/before/summary.json`;
  exact sample:
  `/home/tmp2/gertullj/scratch/foundation-libs/text-contract-probes/inchi/epochs/key-verdict-native-codes/before/Debug-static-nonstandard.json`.

### L34 — A source stamp is part of a result, not a footnote to it

* **Condition.** A workspace edits a package's build graph while driver runs
  are in flight, so each receipt describes one tree and the tree moves.
* **Symptom.** Every matrix cell here can be read as a claim about the package
  as it ships, because the receipt records no stamp a reader could check. Two
  runs with identical counts can describe different code.
* **Fix.** Each gate records one source stamp for its whole run and this file
  quotes the first hex of it beside the numbers, so a later edit cannot inherit
  a result it did not produce. Build-only stays build-only: a cell that compiled
  with no runner is coverage, never a passing test, and a cell whose tests were
  skipped is recorded as skipped.
* **Target bound.** Any package whose source moves while gates run. The cost is
  one line per receipt and the benefit is that "current" has a definition.
* **Evidence boundary.** Four runs for this package, each with its own stamp:
  the six-target `check` baseline of 2026-10-05
  (`20261005T014547Z-797a73f2`, exit 0, `31/31 steps`), the 53-platform matrix
  of 2026-10-04 (`20261004T221720228710Z-45046`, `bc5a479718…`, 12 pass,
  33 build-only, 8 run failures), the native final wave
  (`20261004T233628757747Z-69351`, eight `exit 0` at `22/22` tests) and the
  own-loaded wave (`20261004T232823091897Z-23133`, eight `pass` at `22/22`).
  None of them verifies an edit made after its own stamp, and this lesson
  claims no verification of any such edit.