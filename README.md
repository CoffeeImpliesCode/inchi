# inchi — the IUPAC chemical identifier, as a Zig package

**InChI** is the structure-based chemical identifier developed by
[IUPAC](https://iupac.org/) and the [InChI Trust](https://www.inchi-trust.org/).
This repository packages it: it compiles **upstream's own C**, byte for byte,
from the `INCHI-1-SRC` tree in this repository — all 60 translation units of the
`libinchi` target including the six-unit IXA backend — and publishes a Zig 0.16
package over the translated public API. It generates standard and non-standard
identifiers, reads them back into structures, computes InChIKeys and their two
SHA-256 extension hashes, and validates both.

Nothing about the chemistry is reimplemented, no table is regenerated, and
nothing is downloaded at build time.

Upstream's own project README is shipped here unchanged, byte for byte, as
[`README.upstream.md`](README.upstream.md). This file is the fork's document.
Where the two differ, this one describes this package; upstream's describes the
project it came from.

* **Zig interface** — build, import, call, and the whole typed surface:
  [`README.zig.md`](README.zig.md).
* **Provenance, pin and integrity** — [`UPSTREAM.md`](UPSTREAM.md) and
  [`UPSTREAM.sha256`](UPSTREAM.sha256).
* **Licence** — [`NOTICE.md`](NOTICE.md) for the per-file inventory and
  [`FORK-LICENSE.md`](FORK-LICENSE.md) for this fork's own grant.
* **Dated history** — [`CHANGELOG.md`](CHANGELOG.md).

---

## 1. Current native-source deviations
Two upstream C files are edited, each once, each for a stated reason, and each
with the owner having authorised that specific edit.
Upstream's digest for each is recorded as the baseline the patch is measured
against in
[`UPSTREAM.md`](UPSTREAM.md) § The two patched source files; the digest this
package ships is the record line in `UPSTREAM.sha256`, quoted below.

| File | What changed | Why | Upstream digest → shipped digest |
|---|---|---|---|
| `INCHI-1-SRC/INCHI_BASE/src/ichiparm.c` | Nine inserted lines — a seven-line disclosure comment and two string-literal macros — plus three changed lines: the two banner arguments in `HelpCommandLineParms`, and one existing comment line whose format string held an accidental nested-comment delimiter. The compiler's `__DATE__`/`__TIME__` macros are replaced by the **pinned source tag** and a literal `"(no build timestamp)"` | Two builds of these same sources produced different help text, so the library's output was not reproducible across build dates. Separately, Zig's C backend rejects `__DATE__`/`__TIME__` in a ReleaseSafe-mode compile, and rejects the nested `/*` | `eb351611…` → `74302e26597450060b8341a569f4fd8a07813aadce1f05e9b3507c34980cdd3a` |
| `INCHI-1-SRC/INCHI_BASE/src/ichicano.c` | `#include <sys/timeb.h>` moved below `#include "mode.h"` and wrapped in `#ifndef COMPILE_ANSI_ONLY` — **two inserted lines, no changed line**. The include moves; it is not rewritten | `mode.h` defines `COMPILE_ANSI_ONLY` for every non-Microsoft compiler and for `TARGET_API_LIB`, so a guard read *above* that header sees the macro still undefined and includes the header anyway. `<sys/timeb.h>` is absent on `aarch64-macos` and `x86_64-openbsd` | `5c031a2b…` → `9a0998a3a41f62508e755d9411bf3c78b2b7b1ae63edcea7a40c55307130d98b` |

**What did not change, and is not negotiable.** No chemistry, no ABI, no
allocator, no option, no timeout, no flag, no build mode, and no diagnostic
suppression. The `ichicano.c` guard removes a header that nothing in that
configuration uses — the only two readers of `struct _timeb` and `_ftime` in
the file, `InchiTimeGet` and `bInchiTimeIsOver`, sit in the `#else` arm of the
same file's own `#ifdef COMPILE_ANSI_ONLY` — and changes no compiled token in
any other configuration.

**No source is omitted.** All 60 upstream translation units are compiled: 48 in
`INCHI-1-SRC/INCHI_BASE/src`, 6 in `INCHI-1-SRC/INCHI_API/libinchi/src`, and the
six `ixa/*.c` units. The compile list is written out file by file in `build.zig`
rather than globbed, so a new upstream unit cannot enter the archive without a
decision.

**The full public surface ships, not a facade-shaped subset of it.**
`inchi_api.h` declares 36 exported public functions in three blocks — the
`Get*`/`Free*`/`Check*` surface, the `INCHIGEN_*` and `STDINCHIGEN_*` generator
handle families, and `MakeINCHIFromMolfileText` — plus one more,
`FreeInChIExtInput`, declared without the decoration the rest carry and
therefore not exported. Those 36 are exactly the 36 non-`IXA_` globals in
`INCHI-1-SRC/INCHI_API/libinchi/gcc/libinchi.map`, and `ixa.h` adds **91
exported `IXA_` declarations**, matching that file's other 91: the version
script exports 127 globals in all. `ixa.h` is 686 lines and 355 of them mention
`IXA_`, across 199 distinct identifiers — so 355 is a line count, and never was
a declaration count. `inchi_api.h:1413` ends with `#include "ixa.h"`, so one
installed header reaches the whole IXA API, and the six IXA translation units
that implement it are compiled. A C consumer including `<inchi_api.h>` and
linking `libinchi` gets the complete classic **and** IXA closure. `pub const c`
in the Zig facade is the complete translated declaration set, so anything the
typed facade does not name stays reachable.

**Every other upstream source file, header, build file, licence text and
document is unmodified.** The two files above and `.gitignore` are the only
edits in the tree; §2 covers the third. The record is `UPSTREAM.sha256`, now
**110 lines**; `README.upstream.md`, upstream's `LICENSE` and upstream's own
`INCHI-1-SRC/INCHI_API/tbb/LICENSE` are among the files it pins.

## 2. Current native-build deviations

Upstream's own `CMakeLists.txt`, `makefile`, `makefile32` and `vc14` projects are
carried for provenance and are **not used**. This package has its own build
graph, and every flag it passes is quoted from one of those upstream files
rather than chosen here.

| Deviation | What it is | Where the value comes from |
|---|---|---|
| Build system | `build.zig` compiles upstream's C directly. No CMake, no autotools, no Make, no configure step, no generated header. Upstream's core generates no version header at all, so none is invented | — |
| Dialect and flags | `-std=c11`, `-fno-strict-aliasing` | upstream's own `libinchi/src/CMakeLists.txt:6` and `libinchi/gcc/makefile:123` |
| Macros | `TARGET_API_LIB=1`, `COMPILE_ANSI_ONLY=1`, on both the C compile line and the `addTranslateC` translation line | `libinchi/src/CMakeLists.txt:154-158` and `libinchi/gcc/makefile:129` |
| Library name | `inchi` → `libinchi` | `PREFIX ""` at `libinchi/src/CMakeLists.txt:165` |
| Linkage | `-Dlinkage=static` or `-Dlinkage=dynamic`. **The default is `static`**, which is what this package always built; nothing about the default changed | the two variants are one library, not two projects |
| Shared-library export set | On ELF targets a shared build passes upstream's own version script `INCHI-1-SRC/INCHI_API/libinchi/gcc/libinchi.map` to the linker, so the exported set is the public API and not every internal InChI symbol. `-fPIC` is added on non-Windows targets | upstream's `libinchi/gcc/makefile:62-67` and the `.map` file itself |
| Windows DLL macros | `BUILD_LINK_AS_DLL` and `_USRDLL` are defined on the C core **only** when the target ABI is `msvc`, because `inchi_api.h:691` gates the whole import/export block on `_WIN32 && _MSC_VER && BUILD_LINK_AS_DLL`. On MinGW neither is defined, which is upstream's own observable behaviour. The static build never carries them, on any target | `inchi_api.h:691-709` |
| Installed closure | the library, `include/inchi_api.h` and `include/ixa.h`, `lib/pkgconfig/inchi.pc`, `bin/misuse`, and `share/doc/inchi/{LICENSE, NOTICE.md, FORK-LICENSE.md, UPSTREAM.md, README.md, README.upstream.md, tbb/LICENSE}`. **InChI itself installs no tools and no runtime data**, so there is still no upstream data tree and no other executable; the one program is fork-authored and is built in both configurations. The two READMEs keep distinct names in the installed tree, and the Intel TBB Apache-2.0 text sits in its own `tbb/` subdirectory so it is never read as part of the MIT set. The `.pc` uses `prefix=${pcfiledir}/../..`, so it is correct for any `--prefix`; it carries `Version: 1.07.5` — upstream's own `CURRENT_VER` string, not the manifest's `1.7.5` — `Cflags: -I${includedir} -DTARGET_API_LIB -DCOMPILE_ANSI_ONLY`, `Libs: -L${libdir} -linchi`, `Libs.private: -lm` only where libm is a separate library, and `-DBUILD_LINK_AS_DLL` appended to `Cflags` only for `msvc` with a shared build | `INCHI-1-SRC/INCHI_BASE/src/bcf_s.h:52` |
| `-z relro` | **deliberately omitted.** Upstream passes it at `libinchi/src/CMakeLists.txt:169` and `libinchi/gcc/makefile:64`; it is a hardening workaround for the produced image and decides nothing about the exported set or about a consumer's compile line. Recorded as an omission on the record, not a silent one | `libinchi/src/CMakeLists.txt:169`, `libinchi/gcc/makefile:64` |
| `.gitignore` | upstream's 31 rules are kept verbatim and first; the fork appends `.zig-cache/`, `zig-out/`, `consumer/.zig-cache/`, `consumer/zig-out/`, `result`, `result-*`, `.devenv/` and `.direnv/`. Nothing was removed to make room | — |
| A shipped upstream file | `INCHI-1-SRC/INCHI_API/libinchi/gcc/libinchi.map` moved from "carried for provenance" into the package, because a shared build reads it and a build cannot read a file the package does not ship. It is upstream's, unmodified, and is the 110th line of `UPSTREAM.sha256` | — |
| Portable packaging | `package.nix` is the one source-only derivation, consumed by both `flake.nix` and `devenv.nix`. `flake.nix` exposes `packages.<system>.static` and `packages.<system>.shared`, `default` being `static`. The `nixpkgs` input is pinned twice over: by revision in `flake.nix:15` and by the committed `flake.lock` beside it, which is the same rev `c7def046b9a883d46974757852106483d741586f` with its `narHash`. **There is no `devenv.lock`**, because `devenv.yaml` pins its own input by revision; none is invented to match the flake's. `devenv.nix` is the canonical development shell and carries **tools, not this SDK**, so entering the shell does not mean building the library. No sibling import, no host path, no build-time download, no claim of a wholly static executable | [`UPSTREAM.md`](UPSTREAM.md) § Portable packaging |
| Runtime loading | `-Druntime=true`, default `false`. When true, `build.zig` replaces exactly one call in the bundled arm — `module.linkLibrary(artifact.?)` — with `runtime/graph.zig createModule(b, translate_c, target, optimize)`, and the facade's `c` import becomes the generated dispatch. The C artifact is built and installed either way: which dispatch a build *uses* is a different question from which artifact it *produces*. Four pieces: the reusable core `runtime/loader.zig`, this SDK's descriptor `runtime/library.zig`, the generated dispatch from `runtime/generate.zig`, and `runtime/sync.c` compiled with `-DRT_SYNC_PREFIX=inchi_rt` | `runtime/graph.zig` |

**What a runtime-loaded provider must be**, read out of `runtime/library.zig`
rather than assumed:

* **It exports** every `extern` the translated header declares — `translate.h`
  over `inchi_api.h` and, through `inchi_api.h:1413`, `ixa.h`: the whole
  `GetINCHI`/`GetStdINCHI`/`GetINCHIEx` surface, every `GetStructFrom*` rebuild,
  every `Free*`, the AuxInfo conversion pair and its release pair, the key
  surface, `CheckINCHI`, `MakeINCHIFromMolfileText`, the whole
  `INCHIGEN_*`/`STDINCHIGEN_*` generator, and the IXA entry points. One
  deliberate exception: `FreeInChIExtInput` (`inchi_api.h:678`) carries no
  `EXPIMP_TEMPLATE INCHI_API` decoration, is absent from the **127** globals in
  `INCHI-1-SRC/INCHI_API/libinchi/gcc/libinchi.map` — 36 classic and 91
  `IXA_` — and that file's `local: *`
  hides it from a shared ELF provider — so its declaration stays **direct**
  rather than demanding a symbol a correct libinchi does not export. It is
  defined at `INCHI-1-SRC/INCHI_API/libinchi/src/inchi_dll.c:2923` and called
  from inside the library itself, so a static archive carries it; a shared ELF
  provider built with that version script does not.
* **It was built from the same `inchi_api.h` and `ixa.h` with the same
  settings**: `MAXVAL` 20, `ATOM_EL_LEN` 6, `NUM_H_ISOTOPES` 3, `STR_ERR_LEN`
  256, `MAX_NUM_STEREO_ATOM_NEIGH` 4, `MAX_NUM_STEREO_BONDS` 3, `INCHI_NUM` 2,
  `FIND_RING_SYSTEMS` 1. Those fix the layouts of `inchi_Atom`,
  `inchi_Stereo0D`, `InchiInpData`, `NORM_ATOM`, `NORM_ATOMS` and
  `INCHIGEN_DATA`, and `inchi_Atom` is also what the facade's own `Atom` is.
* **ABI family:** plain C calling convention, no variadics, no exported data.
  `AT_NUM`/`NUM_HS` are `signed short`, `AT_NUMBR` `unsigned short`, `S_CHAR`
  `signed char`, the `WarningFlags` cells `unsigned long`, every status `int`.
  Nothing here is width-configurable.
* **Allocator:** upstream's own, and no Zig allocator is ever in the path. Every
  allocation a caller receives is released by a matching `Free*` in the same
  provider — which is also why a Zig leak oracle cannot see one.

**What the load call looks like.** `LoadSource` is a two-arm union and the arm
is always explicit — `.path` for an absolute file path, `.system` for a named
library, passed to the platform loader unchanged. There is no path-to-system
fallback. `load` returns one of `EmptySource`, `SourceTooLong`,
`UnsupportedTarget`, `OpenFailed`, `MissingSymbol`, `ValidationFailed`,
`ProviderMismatch`, `ReentrantLoad`. The same request is idempotent; a different
request after a load has succeeded is refused rather than honoured; a failed
candidate is closed and nothing is published; there is no automatic retry; and
any ordinary module call made before the load panics in every optimization mode,
naming the library and telling the caller to call `load` first.

**One combination is refused.** `-Druntime=true` together with `-fsys=inchi`
**panics at configure time**, with a message saying why. System mode's contract
is to bind to an installed `libinchi`; a configuration that resolves its
symbols at run time does not bind to one. It is refused rather than resolved in
favour of either side, because silently dropping one would build something the
caller did not ask for under a name that says they did. `-Dlinkage` and
`-Druntime` are otherwise orthogonal — which artifact, and which dispatch — and
may be set together.

**Two runtime steps.** `runtime-test` exists **only** under `-Druntime=true`; it
is `addTest` plus `addRunArtifact` on `runtime/load_tests.zig`, needs both
`INCHI_TEST_PROVIDER` and `INCHI_TEST_ALIEN`, and **skips nothing** when either
is missing, so it cannot be run where both cannot be named. `misuse` is built
and installed by `zig build` in **every** configuration, because which of its
modes stop depends on the configuration and only the caller knows which one it
built; its three modes are `misuse pre-load`, `misuse after-load <path>` and
`misuse linked-load`. **No step runs `misuse` and asserts an exit status**,
because two of the three are supposed to stop — `zig build` owes that it
produces the program, and running the three commands is the caller's.

**The cross gate is the static, linked closure, and it says so.** `check` and all
53 cells of the published matrix are named on the command line without
`-Dlinkage` or `-Druntime`, so they compile the static library and link it
directly. `-Dlinkage=dynamic` has no answer for `wasm32-wasi`, because WASI has
no shared object for a C library, so
the matrix could not cover both linkages without dropping a cell. All 53 cells
stay; the shared artifact is covered by `zig build -Dlinkage=dynamic` and by
`zig build consumer -Dlinkage=dynamic`, both `PENDING-VERIFICATION` in §3. **The
matrix row does not cover both linkages, and it does not cover the runtime route
either.**

**Upstream's CI is left exactly as it arrived** and is not retargeted at this
fork's infrastructure. This repository's own workflow is
`.github/workflows/verify.yml`.

### Dated history

The build graph has moved in waves, each with its own numbered entry and its own
receipts. The current state is described above; what changed and when is in
[`CHANGELOG.md`](CHANGELOG.md):

* **§1–§3** (the original package) — the Zig package, the decision to compile
  the whole `libinchi` target including IXA, and the decision to build the
  in-tree library by default with `-fsys=inchi` as the opt-in.
* **§4 onward** — the Zig API corrections: sentinel types, option-string
  handling, bounds, ownership and lifetimes.
* **§33–§35** (2026-10-02 wave) — the 53-cell matrix over the shipped
  arrangement, the disclosure-prose corrections, and the consumer step's
  execute-or-build predicate.
* **Zig API contract alignment — 2026-10-03** — output ownership, warning
  dimensions, reachable construction enums, and the module fragment.
* **§36** (this wave) — the shared/static delivery, `inchi.pc`, the full
  installed closure, the ELF version script's promotion into the package, and
  the portable Nix and devenv packaging.
* **§37** (this wave) — runtime loading, documented from the landed source: the
  explicit `LoadSource` arms, the provider's export and ABI requirements, and
  the load-time check, with every runtime gate `PENDING-VERIFICATION`.

Each entry states what was observed when the claim was made and what is
`PENDING-VERIFICATION`. No entry borrows another entry's receipt.

## 3. Current build, run and test matrix

**Read the State column before the Result column.** Rows marked
**history** are real runs with real receipts, but each was taken over a tree
this package has since left — before the `ichicano.c` patch, before a document
settled, or before this migration. Their numbers are **not** carried forward.
Rows marked **`PENDING-VERIFICATION`** have had a correction land in them and no
gate has observed them yet. The complete receipt table, including the packaging
rounds and the `sha256sum -c` history, is in
[`README.zig.md`](README.zig.md) § Verification status.

**Every `16/16` below is what its own run printed, against the `tests.zig` of
its day**, which declared sixteen top-level tests. The file as it ships
declares **22** (`tests.zig:185, 213, 232, 259, 274, 302, 322, 340, 400, 428,
446, 464, 488, 526, 556, 574, 599, 652, 672, 707, 753, 810`). The older rows
stayed on a tree this package has since left, so their numbers are not carried
forward. Three later receipts did execute the 22-test file, each against its own
source stamp: the native final wave and the own-loaded wave, eight cells each at
**22/22**, and the 53-target matrix below, whose 20 executed cells ran 22 tests
each. Adding a test moves neither a compile result nor a build-only cell, so the
six-target `check` baseline and every `build_only` cell stay current on their own.

| Gate | Command | State | Result |
|---|---|---|---|
| test + smoke + install, Debug, native | `zig build test smoke install -Doptimize=Debug` | **history** | exit 0, `16/16 tests passed`, `install inchi success`. Taken before the `ichiparm.c` patch; it never compiled the `ichicano.c` guard |
| test + smoke, ReleaseSafe, native | `zig build test smoke -Doptimize=ReleaseSafe` | **history** | exit 0, `16/16 tests passed`. Same tree as the row above |
| consumer package | `cd consumer && zig build run` | **history** | exit 0, four published identifiers and keys, `consumer ok`. Same tree |
| test + smoke + install, Debug, native — stable wave | `zig build test smoke install -Doptimize=Debug` | **history** | exit 0, `16/16 tests passed`, on the arrangement this package shipped before the current migration |
| test + smoke, ReleaseSafe, native — stable wave | `zig build test smoke -Doptimize=ReleaseSafe` | **history** | exit 0, `16/16 tests passed`, same session |
| consumer — stable wave | `cd consumer && zig build run` | **history** | exit 0 against the tree the two rows above installed |
| `check -Dtarget=x86_64-linux-gnu` | `zig build check -Dtarget=x86_64-linux-gnu` | **history** | exit 0, `6/6 steps succeeded` |
| `check -Dtarget=aarch64-linux-gnu` | as above | **history** | exit 0, `6/6 steps succeeded` |
| `check -Dtarget=aarch64-macos-none` | as above | **history** | exit 0, `6/6 steps succeeded`. This target was red before the `ichicano.c` patch and is green on the arrangement the final baseline compiled |
| `check -Dtarget=x86_64-windows-gnu` | as above | **history** | exit 0, `6/6 steps succeeded` |
| `check -Dtarget=riscv64-linux-gnu` | as above | **history** | exit 0, `6/6 steps succeeded` |
| `check -Dtarget=wasm32-wasi` | as above | **history** | exit 0, `6/6 steps succeeded` |
| `cross-test`, full 53-platform matrix | `cross-test` at the package root, through `cross-test.profile.sh` | **history** | harness exit 0, `target_count: 53`, counts `pass 20`, `fail 0`, `build_only 33`, `partial 0`; 20 cells executed the suite at 16 tests each — that was the whole of `tests.zig` in that tree, which declared 16 tests then and declares **22** now — and no foreign BSD, macOS, Mac Catalyst, Windows or WASI binary was executed in any cell. Compile and test coverage, not a measurement of which targets can run. The 33 `build_only` cells and the six-target `check` baseline stay current regardless: adding a test does not move a compile result |
| `cross-test`, current epoch | `cross-test --jobs 8 --build-jobs 8` | **current, source-bound** | Run `20261004T221720228710Z-45046`, receipt `inchi-53-target-8.json`, source stamp `bc5a479718…` identical before and after, exit 1. Corrected audit: **12 pass, 33 build-only, 0 build failures, 8 run failures** of 53, 20 cells executed. All eight failures are the same big-endian cell family — `aarch64_be-linux`, `armeb-linux`, `mips-linux`, `mips64-linux`, `powerpc-linux`, `powerpc64-linux`, `s390x-linux`, `thumbeb-linux` — and in each the suite reports 21 of 22 with one failure: `tests.test.the molfile route produces PubChem's published identifier and key` returns `error.MissingIdentifier` at `tests.zig:734` with `molfile: status rejected, message` and an empty message, reached under `qemu-mips` and its siblings. The remaining 14 tests pass in every one of them. That is one upstream molfile route under foreign big-endian emulation; this package changed no C byte, and the rows above are the record |
| `zig build check`, six declared compile targets | `zig build check` | **current, source-bound** | Label `baseline-inchi-check`, baseline run `20261005T014547Z-797a73f2`, 2026-10-05: exit 0, `Build Summary: 31/31 steps succeeded`, no failing step, all six declared targets seen. Compile and link only |
| Native final wave, both linkages × four modes | `zig build test smoke install -Druntime=false` | **current, source-bound** | `native-final-evidence/20261004T233628757747Z-69351`: eight cells, eight `exit 0`, each `30/30 steps succeeded` and `22/22 tests passed`. Native and linked only; nothing was opened through the platform loader |
| Own-loaded wave, both linkages × four modes | the same steps under `-Druntime=true` | **current, source-bound** | `loaded-final-evidence/20261004T232823091897Z-23133`: eight cells, eight `pass`, each `31/31 steps succeeded` and `22/22 tests passed` |
| `sha256sum -c UPSTREAM.sha256` | as in [`UPSTREAM.md`](UPSTREAM.md) § Integrity | **`PENDING-VERIFICATION`** | every existing receipt verified a **109-line** record. The record is now **110 lines** — the ELF version script was added — and no receipt covers it |
| `zig build -Dlinkage=dynamic` | static is the default; shared is new | **current, source-bound** | the two eight-cell waves above each ran four `-Dlinkage=dynamic` cells, and every one exited 0 with `22/22 tests passed`, so a shared `libinchi` is built, installed and exercised through the typed facade in `Debug`, ReleaseSafe, ReleaseFast and ReleaseSmall. The two std spellings this row used to carry as unconfirmed — `Step.Compile.setVersionScript` and `Build.installFile` — are settled by those sixteen configurations |
| installed shared closure and `inchi.pc`, and a C consumer against it | — | **partly current** | the two waves installed the shared closure and its generated `inchi.pc` sixteen times, so the file and the soname links exist as written. **No C consumer has linked against them**, and that half of the row is still withheld |
| installed static closure and an installed C/IXA consumer | `zig cc … libinchi.a …` | **history** | exit 0, `installed InChI ethanol/key and IXA water agree with PubChem`, against the pre-`ichicano.c` installed copy |
| `nix build .#static` and `nix build .#shared` | — | **`PENDING-VERIFICATION`** | no `nix` evaluation or build of `package.nix` or `flake.nix` has been run. The `nixpkgs` input is pinned by revision in `flake.nix:15` and by the committed `flake.lock` beside it, so the row is unrun rather than unpinned |
| `devenv shell` | — | **`PENDING-VERIFICATION`** | no `devenv` evaluation or shell has been entered |
| `zig build -Druntime=true`, all four modes and both linkages | `zig build test smoke install -Druntime=true` | **current, source-bound** | the own-loaded wave above: eight cells, eight `pass`, each `31/31 steps succeeded` and `22/22 tests passed` |
| runtime-loaded own provider | load by explicit `.path`, then call | **current, source-bound** | every cell of that wave loaded a provider of kind `own`: the `libinchi.so.1.7.5` this tree's own native wave installed, named by absolute path through `INCHI_TEST_PROVIDER` and by no other route, with nothing read from the ambient environment and no fallback |
| runtime-loaded compatible external provider | load a libinchi built outside this package | **`PENDING-VERIFICATION`** | every provider in that wave was of kind `own`, so no external libinchi has been loaded here |
| loader behaviour — startup, failure, explicit retry, idempotence, provider change, atomic publication | — | **`PENDING-VERIFICATION`** | none exercised here |
| pre-load panic in ReleaseFast and ReleaseSmall | an ordinary module call before `load` | **`PENDING-VERIFICATION`** | the loader's pre-load call panics in every optimization mode by construction; no run here observes it |
| `runtime-test` | `zig build runtime-test -Druntime=true`, with `INCHI_TEST_PROVIDER` and `INCHI_TEST_ALIEN` set | **`PENDING-VERIFICATION`** | the step exists only under `-Druntime=true`, and it skips nothing when either variable is missing, so it cannot be run where both cannot be named. Not in CI: `INCHI_TEST_ALIEN` must be a loadable object that is not `libinchi`, and inventing one would be fabricating a fixture this repository does not have |
| `misuse`, all three modes | `misuse pre-load`, `misuse after-load <path>`, `misuse linked-load` | **`PENDING-VERIFICATION`** | built and installed by `zig build` in every configuration, because which modes stop depends on the configuration. **No step runs it and asserts an exit status**, and none is claimed here: two of the three are supposed to stop, and which two depends on how it was built. `zig build` owes that it produces the program; running the commands is the caller's |
| `zig build consumer -Druntime=true -- --provider <path>` | — | **`PENDING-VERIFICATION`** | both source-level hops now forward: the SDK helper appends `--` and its `b.args`, then `consumer/build.zig` passes its `b.args` to the program. Before the outer-hop correction the SDK route silently dropped the provider path. No actual provider load or consumer run is established by this wiring |

Every row marked **current, source-bound** holds one source stamp for its whole
run, and the stamps differ between rows. A build-graph, header, helper or
normalisation edit made after a stamp describes a tree that row never saw, and
no row above verifies one. A `build_only` cell compiled and had no runner: it is
coverage and not a passing test.

`cross-test` needs the harness on `PATH`; the profile at the package root fixes
the build step to `test` and deliberately names no target, no runner and no
host path, so the whole published matrix stays whole and a cell with no detected
runner is reported as build-only.

## 4. Consumption

### From Zig

In your `build.zig.zon`:

```zig
.dependencies = .{
    .inchi = .{ .path = "../inchi" },
},
```

then

```zig
const inchi = b.dependency("inchi", .{ .target = target, .optimize = optimize });
exe.root_module.addImport("inchi", inchi.module("inchi"));
```

```zig
const inchi = @import("inchi");

// One oxygen with two implicit hydrogens, which is water: PubChem CID 962.
var atoms = [_]inchi.Atom{try inchi.atom("O", .{ .ordinary = 2 })};
var output = try inchi.fromMolecule.standard(.{ .atoms = &atoms });
defer output.deinit();

const identifier = output.identifier() orelse return error.NoIdentifier;
std.debug.print("{s}\n", .{identifier});
```

The complete typed surface — options, sentinels, lifetimes, ownership, bounds,
the escape hatch through `pub const c`, and the raw IXA and `INCHIGEN_*` routes
— is [`README.zig.md`](README.zig.md).

### Runtime loading, from Zig

Build with `-Druntime=true`. The module then exposes the same typed surface,
backed by a dispatch that resolves symbols at run time instead of linking them:

```zig
const inchi = @import("inchi");

try inchi.load(.{ .path = "/usr/local/lib/libinchi.so" });
// or, by name, with no fallback to the other arm:
try inchi.load(.{ .system = "libinchi.so.1" });
```

After a successful load the calls are ordinary module calls and look exactly
like the linked ones. Before one, an ordinary call panics — in every
optimization mode — naming the library and telling you to call `load` first.
The provider is chosen once per process: the same request twice is idempotent,
a different request afterwards returns `ProviderMismatch`, and a failed attempt
closes its candidate and publishes nothing, so a retry is explicit.

### From C

The installed headers reach the whole API surface, classic and IXA, from one
include, because `inchi_api.h` includes `ixa.h`:

```c
#include <inchi_api.h>   /* also declares every IXA_* entry point */
```

```sh
cc my_tool.c $(pkg-config --cflags --libs inchi)
```

If you would rather not use pkg-config, the library is `libinchi` and it links
`-lm` wherever libm is a separate library. Upstream itself links `-linchi` by
name and ships no `.pc` file; the one this package installs is this fork's.

### From Nix

```sh
nix build .#static     # the default
nix build .#shared
```

Each output carries the library, both public headers, `lib/pkgconfig/inchi.pc`,
and the full licence material under `share/doc/inchi/` — including the per-file
inventory, this fork's own grant, and upstream's Apache-2.0 text for the Intel
TBB header that travels uncompiled inside the source tree.

### Development

```sh
devenv shell            # or: direnv allow
```

The shell carries the toolchain and nothing else; the SDK is not in its
`packages`. Inside it, `zig build` builds from this repository's sources
exactly as it does outside one, and the packaged derivations are built on
demand:

```sh
devenv build outputs.static
devenv build outputs.shared
```

Every script above begins by naming this repository's own directory and
changing into it. That directory comes from `./.` in `devenv.nix` — the
directory of the file that writes it — through `builtins.toString` and
`lib.escapeShellArg`, and not from `$DEVENV_ROOT`, which `devenv --from
path:<this SDK>` points at the project directory beside this tree. devenv runs
a script as a generated program that inherits the caller's working directory,
so a body that trusted either one looked for `build.zig` in a directory that
has none. Every script that invokes `zig build` carries a fixed `-j8` and
`--summary all` with an explicit `--cache-dir`, so the job count is this file's
own rather than the host's and no cache is left to a default.

That cache directory is `$ZIG_LOCAL_CACHE_DIR/inchi`. A caller that exported
`ZIG_LOCAL_CACHE_DIR` or `ZIG_GLOBAL_CACHE_DIR` keeps both, exactly as
exported; a body fills only what is missing, and the root it fills from is
`$XDG_CACHE_HOME`, else `$TMPDIR`, else nothing — with none of the four set the
body names what is missing and exits non-zero *before* the compiler starts,
which is why the fill is in the bodies rather than in `enterShell`:
`devenv tasks run --mode single <name>` reaches a body without the shell hooks.
Nothing in this file ever falls back to this checkout's own `.zig-cache`.

`sdk:build` and `sdk:build-shared` install something, so they pass `--prefix`
themselves: `zig build install`'s own default is `zig-out` beside the build
root, and the build root here is this checkout. The prefix is `$INCHI_PREFIX`
if the caller exported one, else `$ZIG_LOCAL_CACHE_DIR/inchi/zig-out` — and the
cache rule above has already filled and exported that variable, or stopped the
body, so there is no second resolution order here and no `zig-out` fallback.
`INCHI_PREFIX` is the one prefix variable this shell has, as before.
`sdk:test` and `sdk:check` install nothing —
`build.zig:671` hangs the smoke program's compile step under the install step
and never the reverse (`build.zig:662`, `build.zig:675`) — so they name no
prefix. `sdk:package-static` and `sdk:package-shared` are Nix builds, where the
job count is the caller's `--max-jobs`/`--cores` and not a `-j8` on a
`zig build`.

None of that has been run: no `devenv`, `zig` or Nix command was executed to
produce this section, and the `devenv shell` row above stays
`PENDING-VERIFICATION`.

### System mode

`zig build -fsys=inchi` links an installed `libinchi` instead of compiling this
repository's copy, translating the header that is actually installed next to the
library rather than the in-tree one — an in-tree header would be found first and
would silently bind this repository's 1.07.5 declarations to whatever library
happens to be installed. **No run of `-fsys=inchi` has happened in this
workspace**, so no result is claimed for it, and it is not part of the matrix
above. The bundled build is the default, and a system result may never stand in
for a source-package result.

Three questions this mode resolves, and where each answer comes from
(`SOURCE-CONFIRMED` from `build.zig`, not from a run):

* **Which installed library.** An omitted `-Dlinkage` means the distribution's
  shared object, so `system_linkage` defaults to `.dynamic`; an explicit
  `-Dlinkage` names which installed flavour `-l` is asking for
  (`build.zig:514-521`). It is a separate field from `linkage`, because in this
  mode the graph builds no artifact at all and `linkage` then describes nothing.
* **Which metadata.** Both the translation step and the published module ask
  pkg-config for the installed tree's own `inchi.pc` with the same options —
  `.use_pkg_config = .yes` and that `preferred_link_mode`
  (`build.zig:963-967`, `:1052-1055`) — so the header the declarations came from
  and the `-linchi` they bind to are one answer. `.yes`, not `.force`, is the
  deliberate choice here: the fallback is the bare `-linchi` the file itself
  publishes, and this mode is meant to degrade to a name rather than stop.
* **Which executor.** The nested `consumer` build inherits the executor switches
  this build resolved — `-fdarling`, `-fqemu`, `-frosetta`, `-fwasmtime`,
  `-fwine` — and `--libc-runtimes` (`build.zig:1473-1483`), so it runs under the
  same executor `hostCanExecute` decided with instead of resolving its own. The
  `-fsys=inchi` or `-fno-sys=inchi` spelling is forwarded verbatim for the same
  reason (`build.zig:1465-1471`).

## Licence

Not a single-licensed package.

* The InChI core is **MIT**, but not bare MIT: upstream's own bytes add an
  attribution-notice obligation and a version banner that identifies the
  software.
* `sha2.c`/`sha2.h` carry MIT **with a coupling condition** — valid only in
  combination with the InChI software package.
* `stb_sprintf.h` is MIT **or** the Unlicense, dual-licensed inside the file.
* `tbb/tbbmalloc_proxy.h` is **Apache-2.0**, Intel's, carried and never
  compiled, with upstream's own full Apache text beside it.
* This fork's own files are under **`LicenseRef-InChI-MIT-Conditional`**.

[`NOTICE.md`](NOTICE.md) is the per-file inventory and
[`FORK-LICENSE.md`](FORK-LICENSE.md) is the grant. No personal or corporate
copyright identity is asserted for this fork, because none was supplied.

## Publication

This package is local and unpublished. Nothing here has been published, and no
publication is authorized.