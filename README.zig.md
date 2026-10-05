# inchi — the IUPAC chemical identifier, built and wrapped in Zig

This package compiles InChI **1.07.5** — upstream's own C, byte for byte, from
the `INCHI-1-SRC` tree in this repository, all 60 translation units of the
`libinchi` target including the six-unit IXA backend, less **two authorised,
bounded and landed** patches, to `ichiparm.c` and `ichicano.c` — and publishes a
Zig facade over the translated `INCHI_BASE/src/inchi_api.h`.
It generates standard and
non-standard InChI identifiers, reads them back into structures, computes
InChIKeys and their two SHA-256 extension hashes, and validates both.

No chemistry is reimplemented. No table is regenerated, nothing is downloaded
at build time, and exactly **two** upstream files are edited, each under its own
owner-authorised and bounded patch: `INCHI_BASE/src/ichiparm.c` and
`INCHI_BASE/src/ichicano.c`. Both patches' scope, patch records and what they
did and did not change are in § Verification status, and **every row of that
table names the tree it was taken on** — several of them predate a patch, and
the packaging rows predate the current documents, so none of their numbers is
carried forward as current. `pub const c` keeps the whole translated
C surface — IXA, `MakeINCHIFromMolfileText`, `GetINCHIEx`, the
`INCHIGEN_*` generator family — reachable for anything the facade does not
name.

## Requirements

Zig **0.16.0**, the real compiler. This package calls `b.systemIntegrationOption`,
`b.addTranslateC` and `std.Io.Threaded`, none of which exist in earlier
versions. In the workspace that grew this package, a bare `zig` on `PATH` is a
version dispatcher rather than a compiler, so the pinned binary is named
explicitly on the gate command lines below.

A C library is required: `libinchi` calls stdio, stdlib, string and math.
`link_libc = true` is set on the library module, and libm is linked there too
on the targets where it is a separate library — glibc and the BSDs. It is
linked on the module a dependent imports rather than on the static archive,
because a `linkSystemLibrary` on a static library stays inside that library's
own link line and never reaches the executable that links the archive.

## Commands

| Command | What it does |
|---|---|
| `zig build` | installs the bundled library — `zig-out/lib/libinchi.a` by default — both public headers `inchi_api.h` and `ixa.h` into `zig-out/include`, the generated `zig-out/lib/pkgconfig/inchi.pc`, `zig-out/bin/misuse`, the licence material under `zig-out/share/doc/inchi/`, and compiles `smoke.zig` |
| `zig build -Dlinkage=dynamic` | the same install, as a shared library: `libinchi.so` with its soname links on ELF, `libinchi.dylib` on Darwin, `inchi.dll` and `inchi.lib` on Windows |
| `zig build test` | builds **and runs** `tests.zig` in the requested `-Doptimize` mode |
| `zig build smoke` | builds and runs the deterministic smoke program |
| `zig build check` | compiles the C core, the facade, `tests.zig` and `smoke.zig` for all six cross targets, **without running any of them** |
| `zig build check -Dtarget=<triple>` | the same, for one target |
| `zig build consumer` | runs the separate package in `consumer/` against the published module |
| `zig build -fsys=inchi` | links an installed `libinchi` instead of compiling this repository's copy |
| `zig build -fno-sys=inchi` | the bundled build; this is the default |
| `zig build install --prefix <dir>` | the install step with an explicit prefix, which is what `package.nix` calls |
| `zig build -Druntime=true` | the same install, with the facade's `c` import backed by the generated dispatch instead of a link. See § Runtime loading |
| `zig build runtime-test -Druntime=true` | runs `runtime/load_tests.zig`. **Only exists under `-Druntime=true`**; needs `INCHI_TEST_PROVIDER` and `INCHI_TEST_ALIEN`, and skips nothing when either is missing |
| `misuse pre-load` / `misuse after-load <path>` / `misuse linked-load` | the installed program's three modes. Built and installed in **every** configuration, and **no build step runs them**: two of the three are supposed to stop, and which two depends on how it was built, so running them is the caller's |
| `zig build consumer -Druntime=true -- --provider <path>` | names a provider for the consumer. Both hops now forward: the outer helper appends `--` and its `b.args`, then `consumer/build.zig` passes its `b.args` to the program. `PENDING-VERIFICATION` |

`-Dlinkage` accepts `static` and `dynamic` and **defaults to `static`**, which is
what this package always built; it is forwarded to the nested `consumer/` build
alongside `-Dtarget`, `-Doptimize`, `-Druntime` and `-fsys`. `-Druntime` accepts
`true` and `false` and **defaults to `false`**; it is orthogonal to `-Dlinkage`
— which artifact, and which dispatch — and may be set with it. `-Dtarget=` and
`-Doptimize=` are the ordinary standard options. The optimisation mode is
threaded verbatim into the C core, the facade, the test root, the smoke root,
the six cross checks and the nested consumer; there is no Debug-to-ReleaseSafe
mapping anywhere.

The nested consumer also receives the query's CPU selection, fixed `-j8`,
two-token `--summary all`, the outer local cache's existing `consumer`
subdirectory and the inherited global cache root via two-token
`--global-cache-dir`. It retains the resolved target, optimize, linkage,
runtime and system choices, executor switches and `--libc-runtimes`; trailing
program arguments travel verbatim after `--`. The existing resolved-target
`hostCanExecute` decision still chooses `run` or compile/install only.
A non-default install prefix travels as two-token `--prefix` before the
argument handover. The helper uses the actual `b.install_prefix`, making a
relative prefix absolute before changing into `consumer/`; it emits no prefix
when the outer build uses its default `zig-out`.
These helper corrections are landed source, `PENDING-VERIFICATION`, not
evidence that a configured provider has loaded or a foreign program has run.

**One combination is refused:** `-Druntime=true` together with `-fsys=inchi`
panics at configure time. The published cross gate names `-Dlinkage=static` and
`-Druntime=false` explicitly — in `cross-test.profile.sh`'s `CROSS_BUILD_ARGS`
and in the CI `cross` job — so the 53-cell matrix is the static linked closure
by construction rather than by omission.

This file documents the **Zig interface**. Current source deviations, current
build deviations, the build/run/test matrix and consumption are in the fork's
own [`README.md`](README.md).

## Cross-target checks

`check` never executes a foreign binary. It compiles the whole core plus both
Zig roots, which is what makes it a check of the facade and not of an
unreferenced archive. Six commands, one attempt each, no target skipped:

```
zig build check -Dtarget=x86_64-linux-gnu
zig build check -Dtarget=aarch64-linux-gnu
zig build check -Dtarget=aarch64-macos-none
zig build check -Dtarget=x86_64-windows-gnu
zig build check -Dtarget=riscv64-linux-gnu
zig build check -Dtarget=wasm32-wasi
```

**All six are green on the tree as it stands, and the one that was red has been
re-run at its own target.** These six runs were first taken on the
**post-`ichiparm.c`, pre-`ichicano.c`** tree — one attempt per target, none
skipped — and five were green while one was red. That set stays what it was:
the **six-target fast compile-only baseline**, kept alongside the 53-platform
matrix rather than replaced by it, with the red cell kept as history. The same
six commands have since been run again on the current tree and **all six are
green** — `zig build check -Dtarget=<target> -Doptimize=Debug -j8 --summary all
--color off`, `Build Summary: 6/6 steps succeeded`, exit 0 on every cell,
`2026-10-02T07:23:30.237Z` to `2026-10-02T07:23:32.431Z`, aggregate
`local://foundation-cross-test-final-baseline.json` and per-cell
`local://foundation-cross-test-final-baseline-inchi-<target>.log`. That round is
the workspace's 48-cell explicit-target baseline across all eight additions,
and this package's six cells are green in it. The macOS cell is therefore
**superseded by a re-run of itself** and not only by the broader compile below.
See § Verification status for what each row covers now.

**What the red cell was, and why.** `zig build check
-Dtarget=aarch64-macos-none` failed with
`INCHI_BASE/src/ichicano.c:46:10: error: 'sys/timeb.h' file not found`
(`local://foundation-expansion-inchi-authorized-patch-cross-aarch64-macos-none-369.log`,
`Build Summary: 2/6 steps succeeded (1 failed)`). The include there was
unconditional, while the code that uses `struct _timeb` and `_ftime` sits
inside the `#else` of `#ifdef COMPILE_ANSI_ONLY` (`ichicano.c:95`, `#endif` at
`ichicano.c:412`, both pre-patch) — and this build defines
`COMPILE_ANSI_ONLY=1`, so the flag suppressed the use, not the header. Zig's
`aarch64-macos-none` sysroot has no `sys/timeb.h`
(`lib/libc/include/any-darwin-any/sys/`). That receipt is **history**; the
green cell of the same target in the fresh baseline is what replaced it.

That failure is now patched, and the guard is a move as well as an addition.
`ichicano.c` carries `#ifndef COMPILE_ANSI_ONLY` around the include — the same
macro both of its readers already sit behind, and the same include
`ichitime.h:56` already carries commented out under that macro — and the
guard sits **after `#include "mode.h"` and before `#include "ichicano.h"`, at
`ichicano.c:49-51`**. It has to sit there: `mode.h:197-201` is what *defines*
`COMPILE_ANSI_ONLY` (`!_MSC_VER || TARGET_API_LIB || TARGET_EXE_USING_API`), so
a guard placed above `mode.h` tests a macro that header has not defined yet and
works here only because the build also passes `-DCOMPILE_ANSI_ONLY=1` on the
command line. With the macro defined by `mode.h` the include is now skipped;
with it undefined — MSVC — the include is taken exactly as upstream left it.
The move is the same three lines relocated inside `ichicano.c:45-52`: the file
is still 107427 bytes and 2744 lines — byte for byte the first placement's
file, because a move adds no bytes — and the readers behind the macro are at
`:97`, `:327`, `:334-335`, `:397`, `:402` and `:414`, each two further than
upstream's `:95`, `:325`, `:412`, `:332-335` and `:395-402`. Against
**upstream** every line from `:46` down is two higher than upstream cites it,
because the patch inserts two directive lines inside the first fifty; nothing
above `:45` moves at all. The file in this arrangement **is compiled**: the
fresh six-target baseline above, the stable native wave and the current
53-cell matrix all ran on it. Its patched digest is
`9a0998a3a41f62508e755d9411bf3c78b2b7b1ae63edcea7a40c55307130d98b`, upstream's
baseline for the same path is unchanged at
`5c031a2b441dc08509f75fe22e4b6ecddf285ada625b4a69cf77d2920d42f891`, and both
patched files' digests, contexts and line-number shifts are written out in
[`UPSTREAM.md`](UPSTREAM.md) § The two patched source files.

**Where the header is actually absent, probed rather than predicted.** Seven
`zig cc -E -H -include sys/timeb.h` probes, each with its exit code and
diagnostic recorded (`local://foundation-cross-test-timeb-header-availability.json`),
settle the question the directory survey raised:

| Target | `sys/timeb.h` | Observed |
|---|---|---|
| `x86_64-linux-gnu` | **present** | exit 0, no diagnostic |
| `x86_64-linux-musl` | **present** | exit 0, no diagnostic |
| `aarch64-freebsd` | **present** | exit 0, with `generic-freebsd/sys/timeb.h:41:2: warning: "this file includes <sys/timeb.h> which is deprecated"` |
| `x86_64-netbsd` | **present** | exit 0, no diagnostic |
| `wasm32-wasi` | **present** | exit 0, no diagnostic — reached through `generic-musl`, not through the wasi target's own directory |
| `aarch64-macos` | **absent** | exit 1, `'sys/timeb.h' file not found` |
| `x86_64-openbsd` | **absent** | exit 1, `'sys/timeb.h' file not found` |

**The absent pair is macOS and OpenBSD. WASI is not one of them**, and a missing
directory is not a missing header: no OpenBSD target owns a libc include
directory of its own, while WASI reaches `generic-musl` through the
four-directory search path a non-Darwin target gets
(`lib/std/zig/LibCDirs.zig:183-236`). Those seven probes answer the question
for those seven targets and for no others — the family-wide claim, the four
Apple and nine OpenBSD cells, rests on the directory list above and is
confirmed by the 53-cell compile in the next section, not by seven probes —
and neither `x86_64-openbsd` nor `aarch64-macos` was guessed at.

**The red `zig build check -Dtarget=aarch64-macos-none` row is history twice
over**: it is the receipt that motivated the patch, and its target has since
been re-run green on the current tree. The probe row for `aarch64-macos` above
it is not history — it is the current reading of the compiler's search path.

**The patched file, in the placement this section's guard first took, was
compiled 53 times; so is the placement this package ships.** Two full-matrix
runs stand in the record. The earlier one compiled all 53 of its cells on the
tree carrying the guard at its first position — four Apple cells and nine
OpenBSD cells included, every cell exit 0. The current one compiled all 53
again, on the arrangement this section describes, with the same counts and the
same split between executed and compile-only cells. The earlier run is history
for what this package ships, exactly as the `ichiparm.c`-era receipts are
history for the `ichicano.c` line; the current run is what covers it.

**What each compile covers, and what neither settles.** Both are Debug builds of
the C core and the facade for those 53 targets and nothing else. The move
relocates three lines inside one file and changes no chemistry, algorithm, ABI,
allocator, option, default, flag or build mode with it. The whole-record
`sha256sum -c` replay and the final filtered package round over this
arrangement are the driver's to run and to record, and they are recorded
outside this document — in the root ledger's `FORKS.json`, under
`cross_test_wave`, and in `local://foundation-cross-test-package-regression.json`;
`zig build -fsys=inchi` remains unrun and is named in § Verification status.

**`wasm32-wasi` compiled, and that was not luck.** `compile lib inchi Debug
wasm32-wasi success`, `translate-c success`,
`Build Summary: 6/6 steps succeeded`
(`…-authorized-patch-cross-wasm32-wasi-372.log`) — the same unconditional
include, on a target whose *own* `wasm-wasi-musl` directory has no
`sys/timeb.h` either. It compiles because a non-Darwin target gets a
four-directory search path (`lib/std/zig/LibCDirs.zig:183-236`) and
`generic-musl` carries the header. That is why this section reports receipts
instead of predictions: the earlier header reading was right about macOS and
wrong about WASI, in the same direction as L20.

### The full platform matrix

The cross gate for this package is the published 53-platform `cross-test`
matrix, driven through the settings-only profile at the package root:

```
cross-test                      # reads ./cross-test.profile.sh
cross-test --no-profile         # the same matrix, discovered by the harness
```

`cross-test.profile.sh` sets exactly one variable, `CROSS_BUILD_STEP=test`, so
each cell is `zig build test -Dtarget=<target>`: the C core, the translated
header, the facade and the test binary are compiled, and `addTest` +
`addRunArtifact` then either executes the binary on a detected runner or leaves
the cell **build-only**. It deliberately does not narrow the matrix, install an
artifact hook, choose a runner, add `-Doptimize` or name a host path, so runner
policy stays with the harness and a target with no runner is never counted as a
pass. It is listed in `build.zig.zon` `.paths` because it is Bash the harness
runs, not documentation.

**All 53 cells have been run, and the run's own summary is `partial`.** The
receipt is `local://foundation-cross-test-final-current-inchi.json`: run
`20261002-071259-33035-20483`, generated `2026-10-02T07:12:59Z`, Zig 0.16.0,
`mode: zig-build`, `target_jobs: 2`, `jobs_per_build: 4`,
`build_timeout_seconds: 3600`, `run_timeout_seconds: 300`,
`bookkeeping_failure: false`, harness `exit_code: 0`, `target_count: 53`. Its
counts are `pass 20`, `fail 0`, `build_only 33`, `partial 0`. "Partial" is the
harness's word for a matrix in which some cells have no runner, and it is the
honest label: **every cell compiled, and 20 of them also executed.** This run
is taken on the arrangement this package ships — the guard below
`#include "mode.h"` — and its per-cell receipts are
`local://foundation-cross-test-final-current-inchi-<target>.log`.

* **20 cells executed the suite and ran 16 tests each — 320 tests actually
  run**, every one of them `Build Summary: 6/6 steps succeeded; 16/16 tests
  passed`, `reason: tests_complete`, `command_exit: 0`. All 20 are Linux
  targets on this host: `x86_64-linux`, `aarch64-linux`, `aarch64_be-linux`,
  `arm-linux`, `armeb-linux`, `hexagon-linux`, `loongarch64-linux`, `mips-linux`,
  `mipsel-linux`, `mips64-linux`, `mips64el-linux`, `powerpc-linux`,
  `powerpc64-linux`, `powerpc64le-linux`, `riscv32-linux`, `riscv64-linux`,
  `s390x-linux`, `thumb-linux`, `thumbeb-linux`, `x86-linux`.
* **33 cells compiled and stayed build-only**, each
  `Build Summary: 5/6 steps succeeded (1 skipped)` with
  `reason: runtime_unavailable` and `command_exit: 0`. **That is the whole of
  the foreign evidence: no BSD, macOS, Mac Catalyst, Windows or WASI binary was
  executed anywhere in this matrix.** The 33 are four Apple cells
  (`aarch64-macos`, `x86_64-macos`, `aarch64-maccatalyst`,
  `x86_64-maccatalyst`), nine OpenBSD, nine NetBSD, six FreeBSD, four Windows
  and `wasm32-wasi` — a successful foreign compile, and nothing more.

**The earlier full-matrix run, and what it is now.** One earlier run over the
same 53 targets is kept as history: run `20261002-040235-43019-14341`, generated
`2026-10-02T04:02:35Z`, `build_timeout_seconds: 1800`, the same counts (`pass
20`, `fail 0`, `build_only 33`, `partial 0`), the same 320 executed tests and
the same 33 compile-only cells, receipt
`local://foundation-cross-test-matrix-inchi.json` with per-cell
`local://foundation-cross-test-matrix-inchi-<target>.log`. It compiled the
guard's **first** placement, so it describes a file this package no longer
ships. It is not withdrawn, and none of its numbers is carried forward.

**Every cross row is a Debug row, and that now includes all 53 of these.**
Neither `check` nor the profile passes `-Doptimize`, so every cell command is
the default Debug and the matrix summary names no other mode. These rows are
about the C core and the facade compiling for those targets and about nothing
else; ReleaseSafe is covered by its own native rows and by no cross row. See
§ Verification status.

## Using it

In your `build.zig.zon`:

```zig
.dependencies = .{
    .inchi = .{ .path = "../inchi" },
},
```

In your `build.zig`:

```zig
const dep = b.dependency("inchi", .{ .target = target, .optimize = optimize });
exe_mod.addImport("inchi", dep.module("inchi"));
```

That is all a dependent needs. The module carries the translated header, the
archive and the libc requirement, so it names no `libinchi.a`, no include path
and no `-l`. A dependent that wants the C API gets the headers: installing the
archive also puts `zig-out/include` on the include path of anything that links
it, and `inchi_api.h` ends with `#include "ixa.h"`, so a C consumer that
includes one header gets the whole IXA surface.

For C consumers, for the packaged Nix variants and for the development shell,
see § Consumption in [`README.md`](README.md). That is where the installed
closure, `inchi.pc`, `nix build .#static` / `.#shared` and `devenv shell` are
described, and where each one's verification state is stated.

Then:

```zig
const std = @import("std");
const inchi = @import("inchi");

var atoms = [_]inchi.Atom{
    try inchi.atom("C", .{ .ordinary = 3 }),  // CH3
    try inchi.atom("C", .{ .ordinary = 2 }),  // CH2
    try inchi.atom("O", .{ .ordinary = 1 }),  // OH
};
try inchi.connect(atoms[0..], 0, 1, .single, .none);
try inchi.connect(atoms[0..], 1, 2, .single, .none);

var output = try inchi.fromMolecule.standard(.{ .atoms = &atoms });
defer output.deinit();

const identifier = output.identifier().?;          // InChI=1S/C2H6O/c1-2-3/h3H,2H2,1H3
const computed = try inchi.key(identifier, .{});   // LFQSCWFLJHTTHZ-UHFFFAOYSA-N
_ = computed.keyText();
```

`smoke.zig` and `consumer/src/main.zig` are both this, in working form, against
four published answers each — see [Examples](#examples).

## The API

### Building a molecule

| Name | What it is |
|---|---|
| `Atom` | upstream's `inchi_Atom` (`inchi_api.h:134-162`), unchanged: `x`, `y`, `z`, `neighbor[MAXVAL]`, `bond_type[MAXVAL]`, `bond_stereo[MAXVAL]`, `elname[ATOM_EL_LEN]`, `num_bonds`, `num_iso_H[4]`, `isotopic_mass`, `radical`, `charge` |
| `Stereo0D` | upstream's `inchi_Stereo0D`, unchanged |
| `BondType` | `inchi_BondType` (`inchi_api.h:67-73`): `.none`, `.single`, `.double`, `.triple`, `.altern` ("avoid by all means") |
| `BondStereo2D` | `inchi_BondStereo2D` (`inchi_api.h:74-86`), the 2D wedge notation. Read only when coordinates are supplied |
| `StereoType0D` | `inchi_StereoType0D` (`inchi_api.h:407-412`): `.none`, `.double_bond`, `.tetrahedral`, `.allene` |
| `StereoParity0D` | `inchi_StereoParity0D` (`inchi_api.h:415-422`): `.none`, `.odd`, `.even`, `.unknown`, `.undefined`. Relative to `Stereo0D.neighbor` order, and meaningless outside it |
| `atom(symbol, hydrogens) Error!Atom` | a zeroed atom. Coordinates stay zero, so InChI reads the molecule's 0D parities instead |
| `ImplicitHydrogens` | `.ordinary`, `.protium`, `.deuterium`, `.tritium`; `.none` and `.automatic` (`ordinary = -1`, upstream's "work it out yourself") |
| `connect(atoms, first, second, kind, stereo2d) Error!void` | appends the bond to **both** adjacency lists, or to neither |
| `tetrahedralStereo(central, neighbours, parity)` | a tetrahedral 0D descriptor |
| `doubleBondStereo(x, a, b, y, parity)` | a stereogenic-double-bond 0D descriptor |
| `Molecule` | `.{ .atoms, .stereo0d, .options }` — borrows all three |

Charge, radical, isotopic mass and coordinates are raw fields on the returned
`Atom`, written directly, and mean exactly what `inchi_api.h:134-162` says they
mean. **A raw adjacency list brings its own count.** `num_bonds` is what
upstream reads, and it bounds `neighbor`, `bond_type` and `bond_stereo`
together: entry `j` of those three describes the bond to `neighbor[j]` for
`0 <= j < num_bonds`, and nothing past that is read
(`inchi_api.h:165-171`). So an atom built by hand stays within
`max_bonds_per_atom` entries and carries the number of entries it filled;
`connect` maintains all three and the count for you.

**`atom(symbol, ...)` has one failure and it is a length.** A symbol longer
than `element_symbol_len - 1` is `error.ElementSymbolTooLong`. A NUL *inside* a
short-enough symbol is not that error and is not an error at all: the bytes are
copied into a zeroed `elname`, and the first NUL ends the element name, so
`"C\0Cl"` is an atom named `C`. `elname` is a zero-terminated field
(`inchi_api.h:147`) and this module does not add a validator for a symbol
upstream itself stores verbatim. There is no higher-level builder: adding a
helper would be reimplementing what upstream already does in
`SetAtomAndBondProperties`.

### Structure to identifier

| Name | What it is |
|---|---|
| `fromMolecule.standard(molecule)` | `GetStdINCHI`. Clears every option that would make the identifier non-standard (`inchi_dll.c:541-587`), then produces a standard one |
| `fromMolecule.full(molecule)` | `GetINCHI`. With no creation or stereo-modifying option this also produces a standard identifier; with one it produces exactly what was asked for |
| `Output` | `.raw`, `.status`, `.origin`, `identifier()`, `auxInfo()`, `message()`, `log()`, `isWarning()`, `deinit()` |

### Identifier to structure, and identifier to identifier

| Name | What it is |
|---|---|
| `fromIdentifier.standard(text, options)` | `GetStructFromStdINCHI`. Refuses a non-standard identifier with `Status.rejected` before converting (`inchi_dll.c:2464-2476`) |
| `fromIdentifier.full(text, options)` | `GetStructFromINCHI`. Accepts standard or non-standard |
| `fromIdentifier.converted(text, options)` | `GetINCHIfromINCHI`. Regenerates an identifier from an identifier — the header's own way of validating one without re-deriving it |
| `Structure` | `.raw`, `.status`, `.origin`, `atoms()`, `stereo0d()`, `warnings()`, `message()`, `log()`, `isWarning()`, `deinit()` |

### Keys and validation

| Name | What it is |
|---|---|
| `key(text, .{ .first, .second })` | `GetINCHIKeyFromINCHI`, plus the two extension hashes on request |
| `standardKey(text)` | `GetStdINCHIKeyFromStdINCHI`. Refuses a non-standard identifier outright instead of producing the non-standard key (`ikey_dll.c:95-102`), and computes no hash |
| `checkIdentifier(text, strict)` | `CheckINCHI`. `strict` is upstream's own switch: false checks the layout, true regenerates and demands the input back |
| `checkKey(text)` | `CheckINCHIKey` |
| `KeyResult` | `keyText()`, `firstHash()`, `secondHash()`. The buffers are fixed at the header's sizes and live in the value, so the key borrows nothing |
| `KeyError` | the failure set of `key` and `standardKey`, one tag per `INCHIKEY_*` code (`inchi_api.h:1050-1056`) |

`KeyVerdict` uses explicit signed `c_int` values matching the native
`RetValCheckINCHIKeyv` codes: `.standard` = 0, `.non_standard` = -1,
`.invalid_length` = 1, `.invalid_layout` = 2 and `.invalid_version` = 3.
Thus `@intFromEnum(checkKey(text))` preserves the native verdict as well as
its tag. This corrects the prior implicit numbering, which serialized
`.non_standard` as 1. The driver observed that mismatch before this change;
the driver subsequently observed all 24 semantic probe rows passing on
2026-10-04 (`bg1114`, Debug/ReleaseSafe, static/dynamic): returned numeric
verdicts match 0, -1, 1, 2 and 3. Receipt:
`/home/tmp2/gertullj/scratch/foundation-libs/text-contract-probes/inchi/epochs/key-verdict-native-codes/after/summary.json`.
This scoped observation does not establish the current full suite, 53-target
matrix, runtime loading or nested helper/prefix behavior.

**`KeyError` is the one channel here that cannot report a code it did not
anticipate.** An error tag carries no number, so a code this release does not
name arrives as `error.UnknownFailure` and the number is lost with it. `Status`,
`IdentifierVerdict` and `KeyVerdict` are non-exhaustive enums with a `_` field
and keep the raw value a caller did not see named. That channel difference is
disclosed rather than papered over: a caller that must tell two unmapped codes
apart reads a verdict enum, and does not guess at `UnknownFailure` to recover a
number it never had. `INCHIKEY_EMPTY_INPUT` is absent for the same kind of
reason — upstream returns it only for a NULL source pointer
(`ikey_dll.c:162-165`), which this facade never hands over, so a zero-length
identifier arrives as `InvalidInchiPrefix` instead.

Neither `key` nor `standardKey` allocates: the key and the hashes live in
buffers the returned `KeyResult` carries, so an error path releases nothing and
a success path releases nothing either.

`MolfileStatus` keeps every code in the header's `RetValMol2INCHI` namespace,
not a promise that `MakeINCHIFromMolfileText` produces every one. In the pinned
v1.07.5 producer, reading failures and generation failures both become
`.rejected` (2), not `.structure_failed` (4) or `.generation_failed` (5)
(`inchi_dll_b.c:184-197`, `inchi_dll_b.c:229-232`). Those two named arms retain
the header's upper-bound namespace; they cannot identify which stage failed in
this producer. Read the message and log instead. This documentation correction
is `SOURCE-CONFIRMED`. The driver's same 24-row after wave observed the
malformed-molfile control returning raw 2 and typed `.rejected` serialized as
2 in all four configurations. Generation-failure collapse and non-emission
of codes 4/5 remain source-confirmed, not runtime reachability observations.

### Status, and why a warning is not a failure

Upstream's return code is a **classification**, not a boolean.
`inchi_Ret_WARNING` (1) means an identifier *was* produced and there is
something worth reading in `szMessage`. Treating that as an error is the single
most common way to lose a correct identifier.

`Output.status` is a `Status`, which is a value channel with a `_` field, so
every code upstream can return — including `inchi_Ret_SKIP` (-2) and
`inchi_Ret_BREAK` (-100), which this release's enum does not name — is
representable and reportable rather than a trap. Nothing in the facade ever
turns a warning into an error:

```zig
var out = try inchi.fromMolecule.standard(zwitterionic_glycine);
defer out.deinit();
if (out.isWarning()) {
    std.debug.print("qualified: {s}\n", .{out.message()});  // e.g. Proton(s) added/removed
}
const identifier = out.identifier().?;   // present, and the published one
```

The first-atom `*` fixture is rejected by the standard and non-standard
constructors. Its message is `"Unsupported in this mode element '*'"`.
Upstream's screening helper repeatedly checks the first atom, not each atom
(`inchi_dll.c:299-313`). This result does not establish screening at later indices.

The extended constructor rewrites `*` to `Zz`. Default options reject it.
`NPZz` permits it and produces a beta identifier beginning `InChI=1B/`.
The behavioral tests exercise both option settings.

### Rebuild warnings

`Structure.warnings()` is upstream's `WarningFlags` copied out of the struct,
indexed `[x][y]` exactly as the header states it (`inchi_api.h:646-652`):

* `x = 0` is the Reconnected layer where the identifier has one, and the
  Disconnected/Normal layer where it does not; `x = 1` is the Disconnected
  layer, which carries a layer only when a Reconnected one is present.
* `y = 0` is the Fixed-H layer; `y = 1` is the Main layer, or Mobile-H.

Each cell is a bit set, and the bits are named by `INCHIDIFF_*` in
`inchicmp.h:47-93` — not in `ichicant.h`, which names none of them. The module
keeps upstream's raw word and gives those names no Zig values, so a caller reads
a bit against those names at this pinned revision.

### Lifetimes and ownership, in one place

* **Upstream allocates, upstream frees, no Zig allocator is involved.** The
  bytes come from `inchi_malloc` and go back to it. `Output.deinit` calls
  `FreeStdINCHI` or `FreeINCHI` according to `Output.origin`; `Structure.deinit`
  calls `FreeStructFromStdINCHI` or `FreeStructFromINCHI` the same way. The tag
  changes no behaviour today — `FreeStdINCHI` is literally `FreeINCHI`
  (`inchi_dll.c:183-186`) — and it is kept because the pairing that matters is
  the one the creator promised in the header.
* **One owner, one release.** `Output` and `Structure` are single-owner values
  and the type system cannot say so: assigning or passing one copies its
  pointers, and a second `deinit` reached through the copy frees the same
  allocation a second time. Release each exactly once, on **every** path that
  received a value — a warning is a qualified success and a rejection may still
  carry a message. Upstream zeroes each struct as it frees
  (`inchi_dll.c:173`, `inchi_dll.c:232`), so a released value holds nothing and
  every borrowed slice it handed out is gone. `KeyResult` is the opposite case
  and is documented as such: it owns nothing, so any number of copies are safe.
* **Nothing is copied on the way out.** `identifier()`, `auxInfo()`,
  `message()`, `log()`, `atoms()` and `stereo0d()` all borrow memory the C
  library allocated. No accessor allocates, concatenates or copies.
* **`auxInfo()` is not a second allocation.** It is the tail of the identifier's
  own buffer: `produce_generation_output` writes a `'\0'` over the line break
  and points `szAuxInfo` at the byte after it (`inchi_dll.c:764-777`), and
  `FreeINCHI` frees `szInChI`, `szLog` and `szMessage` only
  (`inchi_dll.c:160-171`). So `auxInfo()` stays valid exactly as long as the
  whole `Output` does and must never be freed on its own.
* **A structure goes back in with no copy.** `structure.atoms()` is
  `[]const Atom` precisely so `fromMolecule.standard(.{ .atoms = structure.atoms(),
  .stereo0d = structure.stereo0d() })` compiles.
* **Input is borrowed.** `Molecule.atoms` and `Molecule.stereo0d` must outlive
  the call; the option string is borrowed too, and upstream copies it before
  parsing in both directions (`inchi_dll.c:476-480`,
  `inchi_dll_a.c:314-321`, `inchi_dll.c:2216-2219`,
  `inchi_dll.c:2586-2589`), so a NUL-terminated literal is safe even
  though C declares the field `char *`. Nothing is retained past the call:
  the result borrows upstream's memory, never the caller's bytes.
* **What is not borrowed is the `inchi_Input` struct itself.** C declares every
  one of these parameters non-const (`inchi_dll.c:242`, `inchi_dll.c:2114`), so
  each call builds that five-field struct in a mutable local of its own and
  hands C a pointer to it. No allocation, no copy of the caller's arrays.

### Sentinels

Every string this package returns is NUL-terminated **by upstream**, and each
accessor hands back a sentinel slice rather than a plain one, so an identifier
can go straight into `key`, `standardKey`, `checkIdentifier` or back into
`fromIdentifier` with no copy in between. The terminator is not re-derived:

* `szInChI` and `szAuxInfo` are one string-stream buffer split in two; the
  stream is a C string before the split because every append to it is a
  `vsprintf`, which writes its own terminator (`ichi_io.c:757`).
* `szMessage` is a `strlen + 1` allocation filled by `strcpy`
  (`inchi_dll.c:750-753`), or the `MAX_MSG_LEN` buffer `ReadWriteInChI`
  terminates on entry and after every copy (`ichiread.c:715`).
* `szLog` is the log stream, whose trailing line feeds upstream overwrites with
  `'\0'` before handing the buffer over (`inchi_dll.c:791-806`).

So `?[:0]const u8` and `[:0]const u8` throughout, and nothing here claims a
sentinel for an arbitrary slice.

### Options, and the text this package accepts

`Molecule.options` and the `options` argument of the three `fromIdentifier`
entry points take **upstream's own option string verbatim**: space delimited,
every option prefixed with `/` or `-` depending on the platform the caller
builds for. This facade adds, removes and rewrites nothing.

`null` and `""` are the same call — no options at all — and they get there
through different upstream control flow, which is why there is one
normalisation here rather than two layers:

* **Structure to identifier.** `GetStdINCHI` and `GetINCHI` test the option
  pointer itself, so `null` skips the copy and the parse and fixes `argc` at 1
  outright (`inchi_dll.c:474-493`), while `""` is copied and parsed
  (`inchi_dll.c:476-480`) into that same `argc == 1` — `parse_options_string`
  finds no argument in an empty command (`inchi_dll.c:1046-1062`) and
  `ReadCommandLineParms` only ever reads `argv[1..argc-1]` (`ichiparm.c:776`).
* **Identifier to structure, and identifier to identifier.** Those entry points
  test the input pointer, not the option pointer (`inchi_dll.c:2210`,
  `inchi_dll.c:2579`), so both spellings are copied into a buffer upstream then
  appends its own main option to (`inchi_dll.c:2120`, `inchi_dll.c:2503`,
  `inchi_dll.c:2220`, `inchi_dll.c:2589`) and parses. An empty string and a
  null one both leave that main option alone; neither is an argument of its
  own.

Neither spelling is a way to ask for an empty argument list, and neither
clears an option.

Nothing in `fromIdentifier.*` can fail before upstream runs, so that namespace
raises no `Error` at all: every failure it reports arrives as
`Structure.status` / `Output.status` with its message attached.
`error.TooManyAtoms` belongs to the structure-to-identifier direction alone.

**A NUL inside a sentinel string ends it.** Every `[:0]const u8` this package
accepts reaches C as a `char *`, and C reads it as a C string, so bytes after
the first NUL are invisible to upstream and to anything that comes back. The
sentinel type guarantees the trailing terminator, not the absence of interior
ones. The same rule applies to an element symbol, where the NUL lands in a
zero-terminated `Atom.elname` field instead.

### Stereo boundaries

* A 0D parity is **relative to the order of `Stereo0D.neighbor`** and means
  nothing outside it: `inchi_api.h:255-256` states that `even` is the
  arrangement in which the neighbours after the first read clockwise when seen
  from the first. Which parity a given neighbour order means is defined by the
  canonical ranking InChI computes, so a test cannot predict it — it can only
  assert that the two parities produce exactly the two identifiers published
  for that pair of compounds.
* A stereocentre with an implicit hydrogen writes `central` itself into the
  first slot of the quadruple (`inchi_api.h:244-270`). `tetrahedralStereo`
  takes that quadruple as written.
* A stereobond quadruple is `{#X, #A, #B, #Y}` (`inchi_api.h:198-208`) with
  `central_atom = no_atom`, upstream's sentinel for "no central atom".
* **An allene is not built here.** `doubleBondStereo` writes the
  `INCHI_StereoType_DoubleBond` form only. The allene form keeps the same
  quadruple, sets `type = INCHI_StereoType_Allene` and names the middle atom of
  the odd double-bond chain in `central_atom` (`inchi_api.h:272-290`); write
  that on a `Stereo0D` directly — the struct is public — rather than expecting
  this function to fill it in.
* With every coordinate zero, the 2D wedge in `bond_stereo` is not read at all
  and the 0D parities are the stereochemical input
  (`inchi_api.h:297-300`). Supply coordinates and you switch to the wedge.

### Bounds

Every check is an ordinary comparison that survives an optimized build, and
each is at a boundary a caller can act on:

| Boundary | Constant | What happens |
|---|---|---|
| element symbol length | `element_symbol_len` = `ATOM_EL_LEN`, 6 bytes including the terminator, so five characters | `error.ElementSymbolTooLong`. A NUL inside an accepted symbol is not this error and is not refused: it ends the element name there |
| adjacency list length | `max_bonds_per_atom` = `MAXVAL`, 20 | `error.TooManyNeighbors`, checked for **both** atoms before either is written. The count is taken over the whole range `0..max_bonds_per_atom`: `0` means no bond recorded yet, `max_bonds_per_atom` means there is no room left. **A negative raw `num_bonds` is no room either** — the field is `AT_NUM`, a `signed short` (`inchi_api.h:124`), and the API's own statement of the range is "Index j is in the range 0 <= j <= (atom[i].num_bonds-1)" (`inchi_api.h:171`). The compiled closure reads it as `for (j = 0; j < at_new[i].num_bonds; j++)` (`INCHI-1-SRC/INCHI_API/libinchi/src/ichilnct.c:297`), which visits nothing when the count is negative, so a negative count is a caller-writable raw value, not a shorter list |
| atom and neighbour index | `AT_NUM`, a `short` | `error.AtomIndexOutOfRange` for an out-of-range or self-referential bond; `error.TooManyAtoms` past what `num_atoms` or `num_stereo0D` can count |
| key buffer | `key_buffer_len` = 28 | the buffer is fixed in `KeyResult`, so there is nothing to size and nothing to overflow |
| hash buffer | `hash_buffer_len` = 65 | likewise |
| key length | exactly 27 | upstream rejects anything else (`ikey_dll.c:521-525`); surfaced as `KeyVerdict.invalid_length`, not as a silent truncation |

**The negative-count half of the adjacency row is landed source and is still
`PENDING-VERIFICATION`.** Both halves of the row are now true of this tree:
`used()` at `zig/root.zig:1746-1748` is total — `if (count <= 0) 0 else
@intCast(count)`, the same `count <= 0` test `borrowedArray` already used — so
it can no longer trap on a value the field is declared to hold, and the new
private `countOutOfRange` at `zig/root.zig:1759-1761` refuses anything outside
`0..max_bonds_per_atom` with two ordinary comparisons. `connect` calls it for
**both** atoms at `zig/root.zig:1149-1153`, before either list is written, and
returns the existing `Error.TooManyNeighbors` — no new error variant and no
signature change. The `Error.TooManyNeighbors` doc at `zig/root.zig:460-468`
now states the whole range rather than only the ceiling.

**What it replaced, and why the note is still `PENDING-VERIFICATION`.** Before
it, `used()` was a bare `@intCast` on the caller-writable raw field and
`connect` tested only the ceiling, so one `connect` call answered two different
ways according to `-Doptimize`: an opaque "integer cast truncated bits" trap in
Debug and ReleaseSafe, and in ReleaseFast/ReleaseSmall a wrap to a huge `usize`
that `append` then indexed past `neighbor`, `bond_type` and `bond_stereo`. The
row above describes the fixed behaviour, which is `SOURCE-CONFIRMED` from the
source read at the line numbers above. **No gate has run since the change, no
receipt in this file observes it, and this file claims no result for it** — a
22-test `tests.zig` has not been executed by any receipt here either, so the
suite that would exercise this has not been run at all. The before half is
recorded on the API owner's own side in [`CHANGELOG.md`](CHANGELOG.md) §40,
which carries the status "`PENDING-VERIFICATION`, with the before half
observed" and names [`FORK-NOTES.md`](FORK-NOTES.md) **L30** as its
transferable form. Neither claims a result after the change.

**`error.TooManyAtoms` is this facade's count, not the library's molecule
size.** It fires above what `AT_NUM` — a `signed short` (`inchi_api.h:124`) —
can hold, so the facade admits 32767 atoms. Upstream's own structural ceiling
is `MAX_ATOMS`, 32766 (`ichisize.h:50`), and the size it treats as the ordinary
input is `NORMALLY_ALLOWED_INP_MAX_ATOMS`, 1024 (`ichisize.h:51`). A molecule
between those is *not* refused here: it reaches upstream, and whatever upstream
makes of it arrives as `Output.status` / `Structure.status` with its message.
Nothing in this package narrows the check to the smaller number, because that
is a library limit and not a representation the binding could enforce
honestly.

`error.NotEnoughMemory` is reachable in principle and unreached by the test
suite: exercising it honestly needs a real allocation failure, and none is
mocked here. The same is true of `error.TooManyAtoms`.

### The escape hatch

`pub const c` is the complete translated declaration set — the IXA builder
objects, `INCHIGEN_*`, `MakeINCHIFromMolfileText`, `GetINCHIEx`, the polymer and
V3000 extended input, the whole 0D-stereo surface — with upstream's behaviour
and none of the contracts above. One warning: **`GetINCHIEx` writes through the
atom array**, rewriting `*` to `Zz` in place (`inchi_dll.c:330-336`). It is
deliberately not wrapped, which is what keeps `Molecule.atoms` honestly
`[]const Atom`.

## Build modes

**Default: the bundled, full, in-tree library, statically linked.** No `-fsys`
flag, and `-fno-sys=inchi` to say so explicitly; no `-Dlinkage` flag, and
`static` to say that explicitly. All 60 upstream translation units are
compiled from `INCHI-1-SRC/` in this repository with `-std=c11`,
`-fno-strict-aliasing`, `TARGET_API_LIB=1` and `COMPILE_ANSI_ONLY=1` — upstream's
own dialect, flags and macros, read out of upstream's CMake and makefile — into
a static `libinchi`, and `inchi_api.h` and `ixa.h` are installed beside it
together with a generated `inchi.pc` and the licence material.
`UPSTREAM.md` gives the file-by-file list and what each choice is upstream's.

**`-Dlinkage=dynamic`: the same library, as a shared object.** Not a second
project and not a different set of sources: the same 60 units, the same flags,
the same facade, linked shared. On ELF targets the build passes upstream's own
version script `INCHI-1-SRC/INCHI_API/libinchi/gcc/libinchi.map` to the linker,
so what is exported is the public API and not every internal InChI symbol, and
`-fPIC` is added on non-Windows targets — both quoted from upstream's
`libinchi/gcc/makefile:62-67`. On a Windows ABI it defines `BUILD_LINK_AS_DLL`
and `_USRDLL` on the C core only for `msvc`, because `inchi_api.h:691` gates the
whole import/export block on `_WIN32 && _MSC_VER && BUILD_LINK_AS_DLL`; on MinGW
neither is defined, which is upstream's own observable behaviour, and on a
static build neither is defined anywhere. **No shared build has been produced
in this workspace**, so the behaviour above is `SOURCE-CONFIRMED` from the
pinned sources and the option is `PENDING-VERIFICATION` in the matrix in
[`README.md`](README.md).

**`-fsys=inchi`: the installed library.** Opt-in; nothing in this package turns
it on by default. In this mode the build translates the header that is actually
installed next to the library it links and adds **no** in-tree include path — an
in-tree header would be found first and would silently bind this repository's
1.07.5 declarations to whatever `libinchi` happens to be installed. It links
`-linchi` by name, because upstream ships no pkg-config file and no `install(`
rules in either `CMakeLists.txt` (`PREFIX ""` at
`libinchi/src/CMakeLists.txt:165` is what makes the name `libinchi`), and it
generates a wrapper that `#include <inchi_api.h>` after defining the same two
macros from the same table the bundled compile uses.

**A system mode has to match its headers and its runtime.** The mode is not a
flag with nothing behind it: the declarations translated are the installed
header's, the library linked is the installed one, and a header/library pair
that disagree is a real mismatch this package cannot detect for you.
**No run of `-fsys=inchi` has happened in this workspace**, so no proof is
claimed for it; it needs an installed `libinchi` with its own matching
`inchi_api.h` and `ixa.h`.

### Runtime loading

**`-Druntime=true`**, default `false`. The typed surface is identical in both
configurations; only where the symbols come from changes. With the option set,
`build.zig` replaces exactly one call in the bundled arm —
`module.linkLibrary(artifact.?)` — with
`runtime/graph.zig createModule(b, translate_c, target, optimize)`, and the
facade's `c` import becomes a generated dispatch instead of the translated
header's module. The C artifact is built and installed either way: which
dispatch a build *uses* is a different question from which artifact it
*produces*.

The facade-level contract is settled and is what a caller writes: a comptime
`inchi.runtime_loaded` telling you which configuration you are in, and
`inchi.load(source)`. `-Dlinkage` and `-Druntime` are orthogonal — the first
answers *which artifact*, the second *which dispatch* — and may be set
together.

Four pieces, and who owns each:

* `runtime/loader.zig` — the reusable loader core. Pure Zig, and it names no
  symbol of its own, which is what lets two SDKs hold their own loader state in
  one process without sharing any of it. It is the driver's reviewed copy.
* `runtime/library.zig` — this SDK's descriptor: the namespaced synchronization
  binding, the one load-time check, and the record of what a provider must be.
* `runtime/generate.zig` — builds the dispatch from whatever the translation
  step actually produced, so the generated table describes the header this
  build selected rather than another one. Driver copy.
* `runtime/sync.c` — compiled into the dispatch with
  `-DRT_SYNC_PREFIX=inchi_rt`. `runtime/library.zig` declares the same prefix in
  the symbol names it binds, and a build where the two disagree fails to link,
  which is the whole error report: there is no runtime path that could hide it.

A linked build has no dispatch, so it imports the core module itself for the
two public types `LoadSource` and `LoadError` — they are this SDK's types and
must be the same types a caller names in either configuration. A runtime build
must not import it separately; two instances would be two sets of types.

#### Calling it

```zig
const inchi = @import("inchi");

try inchi.load(.{ .path = "/usr/local/lib/libinchi.so" });
// or by name — the arm is always explicit, and neither falls back to the other:
try inchi.load(.{ .system = "libinchi.so.1" });
```

After a successful load the calls are ordinary module calls and look exactly
like the linked ones. **Before** one, an ordinary call panics — in every
optimization mode, `ReleaseFast` and `ReleaseSmall` included — naming the
library and telling the caller to call `load` first. That is an ordinary
pre-initialization panic, not a `debug`-only assertion, because a release build
that silently called through an uninitialised table would be worse than one
that stops.

`load` returns one of `EmptySource`, `SourceTooLong`, `UnsupportedTarget`,
`OpenFailed`, `MissingSymbol`, `ValidationFailed`, `ProviderMismatch`,
`ReentrantLoad`. The behaviour that matters to a caller:

* **One provider per process, chosen once.** The same request twice is
  idempotent. A *different* request after a load has succeeded returns
  `ProviderMismatch` and changes nothing; the provider already chosen stays
  chosen. There is no automatic retry.
* **A failed attempt publishes nothing.** The candidate is closed, and the next
  explicit `load` starts a fresh attempt. Contending callers wait for the
  attempt in flight and receive its result rather than a later one.
* **A request too long is refused, not truncated.** The loader keeps its own
  copy for the life of the process rather than allocating one, and a truncated
  path is a different path — loading a file other than the one asked for is the
  one outcome this loader must never produce.
* **No path-to-system fallback.** `.path` and `.system` go to the platform
  loader unchanged; `.path` is an absolute file path and `.system` a basename
  or SONAME.

#### What a provider must be, and where that boundary actually is

Read out of `runtime/library.zig`, not assumed:

* **It exports** every `extern` the translated header declares — the whole
  `GetINCHI`/`GetStdINCHI`/`GetINCHIEx` generation surface, every
  `GetStructFrom*` rebuild, every `Free*`, the AuxInfo conversion pair and its
  release pair, the key surface (`GetINCHIKeyFromINCHI`,
  `GetStdINCHIKeyFromStdINCHI`, `CheckINCHIKey`), `CheckINCHI`,
  `MakeINCHIFromMolfileText`, the whole `INCHIGEN_*`/`STDINCHIGEN_*` modularized
  generator, and all **91** `IXA_*` entry points. A provider that does not export
  them is refused rather than half used.
* **One deliberate exception.** `FreeInChIExtInput` (`inchi_api.h:678`) is
  declared without the `EXPIMP_TEMPLATE INCHI_API` decoration the rest carry,
  is defined at `INCHI-1-SRC/INCHI_API/libinchi/src/inchi_dll.c:2923`, and is
  *absent* from the **127** globals in
  `INCHI-1-SRC/INCHI_API/libinchi/gcc/libinchi.map` — 36 classic and 91 `IXA_`,
  which together are exactly every decorated declaration in `inchi_api.h` and
  `ixa.h` and nothing else — whose `local: *` therefore
  hides it from a shared ELF provider. `FreeStructFromINCHIEx` calls it
  internally at `inchi_dll.c:2915`, and the typed surface releases a structure
  through the matching `Free*`, so demanding the symbol would refuse a correct
  libinchi for a reason that has nothing to do with the caller. Its declaration
  stays **direct**.
* **Same headers, same settings.** `MAXVAL` 20, `ATOM_EL_LEN` 6,
  `NUM_H_ISOTOPES` 3, `STR_ERR_LEN` 256, `MAX_NUM_STEREO_ATOM_NEIGH` 4,
  `MAX_NUM_STEREO_BONDS` 3, `INCHI_NUM` 2, `FIND_RING_SYSTEMS` 1. Those fix the
  layouts of `inchi_Atom`, `inchi_Stereo0D`, `InchiInpData`, `NORM_ATOM`,
  `NORM_ATOMS` and `INCHIGEN_DATA`, and `inchi_Atom` is also what the facade's
  own `Atom` is — a provider built from a different header configuration would
  misread every molecule handed to it.
* **ABI family.** Plain C calling convention on every target.
  `EXPIMP_TEMPLATE`, `INCHI_API` and `INCHI_DECL` are all empty on this build
  because `BUILD_LINK_AS_DLL` is not defined and the branch that would add
  `__declspec` also requires `_WIN32` and `_MSC_VER` (`inchi_api.h:691-703`); a
  provider that *was* built as a `dllexport` DLL is still callable through the
  table, because a name and a calling convention are all a
  `dlsym`/`GetProcAddress` result carries. No variadics — no declaration in
  `inchi_api.h` or `ixa.h` is variadic, so the dispatch builds no variadic
  wrapper. No exported data — neither header declares an `extern` object, so
  every table entry is a function and no `NAMEAddr()` accessor exists.
  Scalars: `AT_NUM` and `NUM_HS` are `signed short`, `AT_NUMBR` `unsigned
  short`, `S_CHAR` `signed char`, `U_CHAR` `unsigned char`, `INCHI_MODES` and
  the `WarningFlags` cells `unsigned long`, every status a plain `int`.
  Nothing here is width-configurable.
* **Allocator.** Upstream's own. `inchi_malloc`/`inchi_calloc`/`inchi_free` are
  internal to the provider, and every allocation a caller receives is released
  by a matching `Free*` in that same provider. No Zig allocator is ever in the
  path — which is also why a Zig leak oracle cannot see one.

**The boundary is honest.** Resolving the symbols and translating the header is
the boundary; neither is proof that a provider is compatible, and this package
does not pretend to add one. The only load-time check is
`Config(dispatch).validate`, which asks `CheckINCHIKey` — a pure,
allocation-free function over one C string (`ikey_dll.c:513-597`) — to classify
PubChem's published InChIKey for water, `XLYOFNOQVPJJNP-UHFFFAOYSA-N`, as a
valid standard key and `not-an-inchikey` as invalid. That is a check that two
routed entry points behave, **not** a compatibility verdict: a provider compiled
with a different `MAXVAL` would answer it correctly and still misread a
molecule.

#### One refused combination

`-Druntime=true` together with `-fsys=inchi` **panics at configure time**, with
a message saying why. System mode's contract is to bind to an *installed*
`libinchi`; a configuration that resolves its symbols at run time does not bind
to one. It is refused rather than resolved in favour of either side, because
silently dropping one would build something the caller did not ask for under a
name that says they did.

#### The two runtime steps

* **`runtime-test`** exists **only** under `-Druntime=true`. It is `addTest`
  plus `addRunArtifact` on `runtime/load_tests.zig`, exactly like the existing
  `test` step. It needs both `INCHI_TEST_PROVIDER` and `INCHI_TEST_ALIEN`, and
  it **skips nothing** when either is missing — a test that cannot name a
  provider has nothing to say, and passing anyway would mean nothing at all —
  so it cannot be run in a context that cannot name both.
* **`misuse`** is built and installed by `zig build` in **every** configuration,
  because which of its modes stops depends on the configuration and only the
  caller knows which one it built. Its three modes are `misuse pre-load`,
  `misuse after-load <path>` and `misuse linked-load`, matching the header in
  `runtime/misuse.zig`. There is **no step that runs it and asserts an exit
  status**, and none is invented here: two of the three modes are supposed to
  stop, and which two depends on the configuration. `zig build` owes that it
  produces the program; running the three commands is the caller's.

## Examples

`smoke.zig`, run by `zig build smoke`, builds four molecules from element
symbols and implicit hydrogen counts and checks each against the identifier and
key PubChem publishes for that compound. Its observed output is in the
[verification table](#verification-status). It is deterministic: no input, no
clock, no random seed.

`consumer/src/main.zig` does the same four through `dep.module("inchi")` from a
package that did not write this one, with its own molecule builder, and adds
two validation calls. It exists to catch the one failure the library's own
tests cannot see: a module that builds from the inside and does not resolve
from outside.

Both take their expectations from PubChem's published compound records, in
`testdata/pubchem_known_answers.tsv`, never from what the library just produced.

The third example is not Zig. A C program compiled against the **installed**
`libinchi.a` and the **installed** `inchi_api.h` — which ends with
`#include "ixa.h"`, so one include reaches the whole IXA surface — reads a real
V2000 molfile for ethanol (PubChem CID 702) through
`MakeINCHIFromMolfileText`, checks the identifier with `CheckINCHI` and the key
with `GetStdINCHIKeyFromStdINCHI`, and then drives a real IXA handle chain for
water (CID 962): status handle, molecule, atom, `INCHIBUILDER`, `GetInChI`, and
a `Destroy` for every handle on every path, the error paths included. It names
no Zig symbol and no wrapper. Its gate is
`local://foundation-expansion-inchi-patched-installed-C-IXA-smoke-387.log`, run
against the archive the patched tree's `install` produced; its compile step and
full command are in the verification table, and the gate's own source is not part
of this package.

## Testing approach

The oracle is **independently published**, and a same-library round trip is not
what any of this rests on:

* Every expected identifier and key came out of PubChem's own compound records,
  one CID at a time, through the PUG REST property endpoint, as the fixture's
  header records. Where the fixture and the library disagree, the fixture is
  right by construction.
* Ten compounds: water, methane, ethanol, benzene, glycine, L-alanine,
  D-alanine, heavy water, *E*-but-2-ene and *Z*-but-2-ene — the last four
  chosen because they carry information a formula cannot: an isotope layer,
  and a tetrahedral and a stereogenic-double-bond parity.
* For both stereo pairs the test asserts that the two parities of one skeleton
  produce exactly the two published identifiers, one each, and that each one's
  key is the key published beside it. That is a complete known-answer statement
  about both parities without the test having to predict which parity is which,
  which it cannot.
* Three things a formula cannot check are checked as known answers of their
  own: **renumbering** (ethanol and benzene built in two different atom orders
  produce the published identifier both times, not merely equal ones),
  **isotopes** (water and heavy water share a connectivity layer and differ only
  in the `/i` layer, and their keys share the first block and differ in the
  second), and **bond stereo** (the stereogenic double bond of but-2-ene, as a
  pair with the tetrahedral pair above).
* Two round trips exist as **supplements**, never as the oracle. The structure
  upstream rebuilds from L-alanine's identifier goes straight back into a
  `Molecule` and regenerates that identifier with no copy, which also exercises
  `GetStructFromStdINCHI`'s output as `GetStdINCHI`'s input. Seven published
  identifiers are regenerated through `fromIdentifier.converted` with no
  options — the conversion that keeps every layer the identifier already has
  (`inchi_api.h:889-901`) — and each one is compared against PubChem's string,
  not against its own input. Water is then regenerated with upstream's own
  layer-keeping string (`-FixedH -RecMet -SUU -SLUUD`, and `/…` on Windows, from
  the template upstream substitutes at `inchi_dll.c:965`): that answer is
  `InChI=1/H2O/h1H2`, which `checkIdentifier` classifies `non_standard`, while the
  same input with no options stays `1S`. **This facade is not a normalizer**; it
  forwards the caller's options and reports what upstream made of them.
* The rebuilt structure's composition is asserted as an invariant rather than a
  count: C3H7NO2 out of L-alanine's rebuild is three carbons, one nitrogen, two
  oxygens, one *explicit* hydrogen and six implicit ones, because a tetrahedral
  parity has nothing to measure against unless its hydrogen is an atom
  (`inchi_api.h:248-270`) — so a raw atom-count oracle would be wrong by one,
  and an element the fixtures do not build fails the test instead of being
  counted as nothing.
* Errors and boundaries are asserted against upstream's own reported values:
  the star-element rejection message, the four malformed-identifier verdicts
  (including the strict-check `conversion_failed` for a well-formed `1S`
  identifier), the three malformed-key verdicts, the standard-versus-non-standard
  split, the reader's `no_data` on a malformed layout (`inchi_dll.c:2821-2825`)
  beside the standard reader's earlier `rejected` (`inchi_dll.c:2464-2476`), and
  the three bounds errors. The key-version assertion is at index **24** of the
  second block, which is the version character (`ikey_dll.c:577-581`); index 26
  is the (de)protonation flag and any base-26 letter there is legal
  (`ikey_dll.c:554-557`), so a `-B` ending is a well-formed key.
* The warning path is asserted as what it is: a **qualified success that keeps
  its identifier**. Glycine's zwitterion, NH3(+)-CH2-COO(-), is neutralized by
  upstream to exactly the skeleton neutral glycine is, upstream reports that it
  moved protons, and the test asserts that the status is `.warning`, that
  `isWarning()` holds, that the identifier is byte-for-byte the one PubChem
  publishes for CID 750, that it equals the neutral run's identifier, and that
  the clean run's message is empty. **Upstream's prose about the moved protons
  is not asserted**: an English message is not a contract, and pinning it would
  make the test fail on a reworded diagnostic while every behaviour it protects
  still held. The same rule retired an assertion on the extension hashes'
  character count.

Upstream's own test material is not used and not shipped. `INCHI-1-TEST/`
stays in this repository for provenance and is not in `.paths`.

## Verification status

Every row below is a run the driver performed in this workspace, with the
receipt that holds its output. Nothing here is predicted, and nothing is green
that was not observed green. **Every row also names the tree it was taken on**,
because that tree moved under them — the `ichiparm.c` patch, then the
`ichicano.c` guarded include, then the move of that guard below
`#include "mode.h"`:

* every receipt below the stable wave is also history for the `ichicano.c`
  record line. Current replay status is deliberately not duplicated here:
  it belongs to the external driver-owned package closure;
* the `-365`, `-374` and `-373` rows are history for a second reason: they
  predate the `ichicano.c` patch altogether, so they never compiled the
  include that patch guards;
* **the six-target `check` fast baseline has been re-run on the current tree
  and is green in all six cells**, including `aarch64-macos-none`. The
  `-367`…`-372` set that row set replaces is kept as history, and the red
  cell's target now has a green receipt of its own;
* **both `2026-10-02` native waves predate the guard move.** The stable wave
  after it is the current native evidence — Debug, ReleaseSafe, smoke, install
  and consumer, all on the arrangement this file ships;
* **the 53-cell matrix has been re-run over the shipped arrangement.** The
  current run `20261002-071259-33035-20483` has a row of its own below; the
  earlier run over the guard's first placement stays history for the
  arrangement this file ships, and says so in its own row;
* the packaging rows are history for one more reason: they were taken before
  this file settled, so a package hash over a copy of it cannot be the identity
  of the package as it stands. **The final filtered fetch, the source and
  fetched integrity checks and the fetched consumer are the driver's to run
  and to record**, after these documents close, and they are recorded outside
  this document: in the root ledger's `FORKS.json`, under
  `cross_test_wave.materialized_packages.inchi`, and in
  `local://foundation-cross-test-package-regression.json`. This file quotes no
  result and no identity for them, because its own bytes contribute to that
  identity.
* **every receipt above predates the current migration wave**, which added
  `-Dlinkage`, the generated `inchi.pc`, the full installed closure, upstream's
  ELF version script as a shipped file, and the portable Nix and devenv
  packaging. That wave has had no gate. Its rows sit at the bottom of this
  table, each marked **`PENDING-VERIFICATION`**, and none of them borrows a
  receipt from an earlier row. The one earlier row that
  changed shape is the integrity check: `UPSTREAM.sha256` grew from 109 lines
  to 110, so **no receipt in this file covers the record as it stands**.

| Gate | Command | State | Receipt |
|---|---|---|---|
| test, smoke and install (Debug, native) — **HISTORY** | `zig build test smoke install -j8 --summary all --cache-dir …/inchi/native-debug --prefix …/inchi/install` | **green, exit 0**: `Build Summary: 11/11 steps succeeded; 16/16 tests passed`, `run test inchi-tests 16 pass (16 total) 60ms`, the four published identifiers and keys plus `ethanol renumbered` and `smoke ok`, and `install inchi success` — the archive and both public headers the `-386`/`-387` and `-384`/`-385` rows then link against. **History: taken before the `ichicano.c` patch**, so it never compiled the guarded include | `local://foundation-expansion-inchi-authorized-patch-native-debug-365.log` |
| test and smoke (ReleaseSafe, native) — **HISTORY** | `taskset -c 0-7 zig build test smoke --summary all -Doptimize=ReleaseSafe --cache-dir …/inchi/native-releasesafe` | **green, exit 0**: `Build Summary: 9/9 steps succeeded; 16/16 tests passed`, `run test inchi-tests 16 pass (16 total) 244ms`, and the same five smoke lines ending `smoke ok`. Sixteen tests in each mode, from the same patched sources. **History: taken before the `ichicano.c` patch** | `local://foundation-expansion-inchi-patched-native-releasesafe-durable-374.log` |
| consumer — **HISTORY** | `cd consumer && zig build run -j8 --summary all --cache-dir …/inchi/native-consumer` | **green, exit 0**: the same four answers built through `dep.module("inchi")`, `check XLYOFNOQVPJJNP-UHFFFAOYSA-N = standard`, `check InChI=1S/H2O/h1H2 = standard`, `consumer ok`, `Build Summary: 6/6 steps succeeded`. **History: taken before the `ichicano.c` patch** | `local://foundation-expansion-inchi-authorized-patch-consumer-373.log` |
| test, smoke and install (Debug, native) — 2026-10-02 wave — **HISTORY** | `zig build test smoke install -Doptimize=Debug -j8 --summary all --color off --cache-dir …/cross-test-01a0f400/inchi/native` | **green, exit 0**, 22.9 s: `Build Summary: 11/11 steps succeeded; 16/16 tests passed`, `observed_test_totals: passed 16, total 16`, the four published answers plus `ethanol renumbered`. **History: this wave compiled the guard's first placement**, before it moved below `mode.h` | `local://foundation-cross-test-inchi-native-Debug.log` |
| test and smoke (ReleaseSafe, native) — 2026-10-02 wave — **HISTORY** | `zig build test smoke -Doptimize=ReleaseSafe -j8 --summary all --color off` | **green, exit 0**, 60.4 s: `Build Summary: 9/9 steps succeeded; 16/16 tests passed`, `observed_test_totals: passed 16, total 16`, the same five smoke lines. Sixteen tests in each of the two modes, from one tree in one session — **history, same sixteen-test arrangement as the Debug row above it** | `local://foundation-cross-test-inchi-native-ReleaseSafe.log` |
| consumer — 2026-10-02 wave — **HISTORY** | `cd consumer && zig build run -j8 --summary all --color off` | **green, exit 0**, 10.6 s: the same four answers built through `dep.module("inchi")`, `check InChI=1S/H2O/h1H2 = standard`, `consumer ok`, `Build Summary: 6/6 steps succeeded` — against the same sixteen-test arrangement | `local://foundation-cross-test-inchi-native-consumer.log` |
| test, smoke and install (Debug, native) — stable wave — **HISTORY** | `zig build test smoke install -Doptimize=Debug -j8 --summary all --color off --cache-dir …/cross-test-01a0f400/inchi/native --prefix …/cross-test-01a0f400/native-install/inchi` | **green, exit 0**, 1.152 s, `timed_out: false`: `Build Summary: 11/11 steps succeeded; 16/16 tests passed`, `expected_tests: 16`, `observed_tests_passed: 16`, `observed_tests_total: 16`, `verification_status: success`. Those numbers are what this run printed and they are kept as they stand. **History, not current evidence for the file as it ships**: `expected_tests: 16` is itself the proof that the tree it compiled declared sixteen tests, and `tests.zig` declares **22** now. Six of them — the two extended polymer/V3000 routes, the AuxInfo-refusal residue test, the molfile refusal/residue test, and the tests at `:526` and `:574` — landed after it | `local://foundation-cross-test-stable-inchi-native-Debug.log` |
| test and smoke (ReleaseSafe, native) — stable wave — **HISTORY** | `zig build test smoke -Doptimize=ReleaseSafe -j8 --summary all --color off --cache-dir …/cross-test-01a0f400/inchi/native --prefix …/cross-test-01a0f400/native-install/inchi` | **green, exit 0**, 18.584 s: `Build Summary: 9/9 steps succeeded; 16/16 tests passed`, `observed_tests_passed: 16`, `observed_tests_total: 16`, `verification_status: success`. Sixteen tests in each of the two modes, from one tree in one session — **history for both modes for the same reason as the row above**. Three later source-bound runs have executed the 22-test file, and they are the four rows at the foot of this table | `local://foundation-cross-test-stable-inchi-native-ReleaseSafe.log` |
| consumer — stable wave — **HISTORY** | `cd consumer && zig build run -j8 --summary all --color off --cache-dir …/cross-test-01a0f400/inchi/native-consumer --prefix …/cross-test-01a0f400/native-install/inchi/consumer` | **green, exit 0**, 0.968 s: `Build Summary: 6/6 steps succeeded`, `verification_status: success`, `timed_out: false`. Debug, against the tree the two rows above installed — so it carries the same sixteen-test arrangement, not the 22-test one | `local://foundation-cross-test-stable-inchi-native-consumer.log` |
| installed C/IXA surface — compile — **HISTORY** | `zig cc -std=c11 -DTARGET_API_LIB -DCOMPILE_ANSI_ONLY -I …/install/include c_surface_gate.c …/install/lib/libinchi.a -lm -o …/patched-C-IXA-surface` | **green, exit 0**, no diagnostics: upstream's own installed `inchi_api.h`, the installed archive, no wrapper. **History: it links the archive the `-365` row installed, which predates the `ichicano.c` patch** | `local://foundation-expansion-inchi-patched-installed-C-IXA-compile-386.log` |
| installed C/IXA surface — run — **HISTORY** | `…/patched-C-IXA-surface` | **green, exit 0**: `installed InChI ethanol/key and IXA water agree with PubChem`. **History: the same pre-`ichicano.c` installed copy as the row above** | `local://foundation-expansion-inchi-patched-installed-C-IXA-smoke-387.log` |
| installed usage banner — compile, then run — **HISTORY** | `zig cc … patched_banner_smoke.c …/install/lib/libinchi.a -lm -o …/patched_banner_smoke`, then `…/patched_banner_smoke` | **green, exit 0** both times: `GetINCHI(empty): deterministic pinned-source help stamp observed`, then the two banner lines quoted in § The authorised `ichiparm.c` patch, landed and covered, carrying `of v1.07.5 (no build timestamp)` and no date anywhere. **History: the same pre-`ichicano.c` installed copy** | `local://foundation-expansion-inchi-patched-installed-banner-compile-384.log`, `…-patched-installed-banner-smoke-385.log` |
| `sha256sum -c UPSTREAM.sha256` — **HISTORY, first-patch record** | as below | **green, exit 0** on the record as it stood at the first patch: 109 records, 109 `: OK`, no failures, `INCHI-1-SRC/INCHI_BASE/src/ichiparm.c: OK` and `INCHI-1-SRC/INCHI_API/tbb/LICENSE: OK` among them. **History: that record's `ichicano.c` line held a digest this package no longer names**, so the row is not evidence about the record as it stands | `local://foundation-expansion-inchi-authorized-patch-integrity-109-364.log` |
| scoped diff against the pin | `git diff 11a87982bb518f57ac013f0b258c283655e1ea1d -- INCHI-1-SRC LICENSE` | **exit 0, with a diff over one path**, `INCHI-1-SRC/INCHI_BASE/src/ichiparm.c`, in three hunks: the `:2597` comment correction, the nine-line insertion at `:2699`, and the two argument rewrites. **Not a pristine proof**: it carries no `--exit-code`, so its exit status says only that the query ran, and it says nothing about any path outside `INCHI-1-SRC` and `LICENSE` | `local://foundation-expansion-inchi-authorized-single-native-file-deviation-363.log` |
| package fetch — **HISTORY** | `zig fetch <this package path> --global-cache-dir <scratch>`, from a build root outside the repository | **green, exit 0**, and the package materialises out of `.paths`. **The identity it printed is deliberately not quoted as current.** That fetch hashed a tree whose `ichiparm.c`, `ichicano.c` and package documents are all in earlier states, so its hash is a property of that snapshot: quoting it beside the current documentation would be a circular claim about a file that the hash itself covers | `local://foundation-expansion-inchi-current-filtered-package-fetch-382.log` |
| materialised integrity — **HISTORY** | `sha256sum -c UPSTREAM.sha256`, run **inside** the fetched package | **green, exit 0, 109 of 109 `OK`.** Every line of the record has a file behind it in the filtered copy — `INCHI-1-SRC/INCHI_BASE/src/stb_sprintf.h`, `…/src/tbb/tbbmalloc_proxy.h`, `INCHI-1-SRC/INCHI_API/tbb/LICENSE`, the upstream `LICENSE`, and upstream's own README — then at `README.md`, now preserved at `README.upstream.md` — among them, so the shape of the claim holds: the record is checkable where a dependent reads it, not only at the repository root. **HISTORICAL for the `ichiparm.c` and `ichicano.c` lines**, which that copy carried in their earlier states, and for the record as a whole, which is now 110 lines | `local://foundation-expansion-inchi-current-filtered-package-integrity-388.log` |
| materialised consumer — **HISTORY** | `cd <fetched package>/consumer && zig build run --summary all --cache-dir <scratch>` | **green, exit 0, Debug.** Four identifiers and keys, both checks, `consumer ok`, `Build Summary: 6/6 steps succeeded`. `consumer/build.zig.zon` resolves `.path = ".."`, which inside the fetched tree is the **filtered copy**, so this row compiled the library out of the package rather than out of a checkout. `zig build run` takes the default `-Doptimize`, i.e. **Debug**: it is not a ReleaseSafe row | `local://foundation-expansion-inchi-current-filtered-package-consumer-389.log` |
| delivery package round, all eight additions — **HISTORY** | `zig fetch` of each `.paths`-filtered package from a build root outside every repository, then `sha256sum -c` inside the copy and `zig build run` in its `consumer/` | **green in all eight**: 8 filtered fetches, 8 integrity runs and 8 copied consumers passed, 1518 integrity records in total, observed `2026-10-02T02:32:12Z`. InChI's own three are `…-delivery-settled-filtered-package-fetch-449.log`, `…-delivery-final-package-integrity-459.log` and `…-delivery-final-package-consumer-460.log`. **HISTORICAL, like the round above it**: every identity in it was taken before this package's documents settled. **The final package round is the driver's to run after they close**, and its result and identity are recorded in the workspace ledger's `cross_test_wave.materialized_packages.inchi` and in `local://foundation-cross-test-package-regression.json`; this file asserts neither | `local://foundation-expansion-package-proof.json` |
| `check -Dtarget=x86_64-linux-gnu` | `zig build check -Dtarget=x86_64-linux-gnu -j8 --summary all` | **green, exit 0**, 6/6 steps | `…-authorized-patch-cross-x86_64-linux-gnu-367.log` |
| `check -Dtarget=aarch64-linux-gnu` | as above | **green, exit 0**, 6/6 steps | `…-authorized-patch-cross-aarch64-linux-gnu-368.log` |
| `check -Dtarget=aarch64-macos-none` — **HISTORY, superseded** | as above | **RED, exit 1**: `ichicano.c:46:10: error: 'sys/timeb.h' file not found`, `Build Summary: 2/6 steps succeeded (1 failed)`. **HISTORY**: this receipt is the cause that motivated the `ichicano.c` patch, not a state of the current tree. **It has since been re-run at this same target, and it is green** — `Build Summary: 6/6 steps succeeded`, exit 0, on the shipped arrangement; see the final baseline row below. It is also superseded for the macOS family by the broader compile — `aarch64-macos`, `x86_64-macos`, `aarch64-maccatalyst` and `x86_64-maccatalyst` all compiled at exit 0 in the **current** 53-cell matrix below, on the shipped arrangement | `…-authorized-patch-cross-aarch64-macos-none-369.log` |
| `check -Dtarget=x86_64-windows-gnu` | as above | **green, exit 0**, 6/6 steps | `…-authorized-patch-cross-x86_64-windows-gnu-370.log` |
| `check -Dtarget=riscv64-linux-gnu` | as above | **green, exit 0**, 6/6 steps | `…-authorized-patch-cross-riscv64-linux-gnu-371.log` |
| `check -Dtarget=wasm32-wasi` | as above | **green, exit 0**, 6/6 steps | `…-authorized-patch-cross-wasm32-wasi-372.log` |
| six-target `check` baseline — **final 48-round run, on the shipped arrangement** | the six `-Dtarget=` cells below, one attempt each, none skipped: `zig build check -Dtarget=<target> -Doptimize=Debug -j8 --summary all --color off` | **6 of 6 green, exit 0 on every cell**, `Build Summary: 6/6 steps succeeded` on every cell, `2026-10-02T07:23:30.237Z` to `2026-10-02T07:23:32.431Z`, `complete: true`, `unrun_cells: []`, no cell timed out. That round is the workspace's 48-cell explicit-target baseline across all eight additions, run one SDK at a time with its own cache and prefix. **This is the current state of the six-target baseline**; the `-367`…`-372` set above is history for it | `local://foundation-cross-test-final-baseline.json`, per-cell `local://foundation-cross-test-final-baseline-inchi-<target>.log` |
| `check -Dtarget=x86_64-linux-gnu` — **final baseline** | as above | **green, exit 0**, 0.256 s, `Build Summary: 6/6 steps succeeded` | `local://foundation-cross-test-final-baseline-inchi-x86_64-linux-gnu.log` |
| `check -Dtarget=aarch64-linux-gnu` — **final baseline** | as above | **green, exit 0**, 0.129 s, `Build Summary: 6/6 steps succeeded` | `local://foundation-cross-test-final-baseline-inchi-aarch64-linux-gnu.log` |
| `check -Dtarget=aarch64-macos-none` — **final baseline** | as above | **green, exit 0**, 0.906 s, `Build Summary: 6/6 steps succeeded`. **The target that was red, re-run on the shipped arrangement** | `local://foundation-cross-test-final-baseline-inchi-aarch64-macos-none.log` |
| `check -Dtarget=x86_64-windows-gnu` — **final baseline** | as above | **green, exit 0**, 0.291 s, `Build Summary: 6/6 steps succeeded` | `local://foundation-cross-test-final-baseline-inchi-x86_64-windows-gnu.log` |
| `check -Dtarget=riscv64-linux-gnu` — **final baseline** | as above | **green, exit 0**, 0.397 s, `Build Summary: 6/6 steps succeeded` | `local://foundation-cross-test-final-baseline-inchi-riscv64-linux-gnu.log` |
| `check -Dtarget=wasm32-wasi` — **final baseline** | as above | **green, exit 0**, 0.192 s, `Build Summary: 6/6 steps succeeded` | `local://foundation-cross-test-final-baseline-inchi-wasm32-wasi.log` |
| six-target `check` — **current source-bound baseline** | `zig build check` over the six declared compile targets, one invocation | **green, exit 0**, `Build Summary: 31/31 steps succeeded`, no failing step, all six declared targets seen. Compile and link only; it runs nothing | baseline run `20261005T014547Z-797a73f2`, label `baseline-inchi-check` |
| 53-cell matrix — **current source-bound run** | `cross-test --jobs 8 --build-jobs 8` | **exit 1**: **12 pass, 33 build-only, 0 build failures, 8 run failures** of 53, 20 cells executed at 22 tests each. The eight failures are the big-endian family — `aarch64_be-linux`, `armeb-linux`, `mips-linux`, `mips64-linux`, `powerpc-linux`, `powerpc64-linux`, `s390x-linux`, `thumbeb-linux` — and in each one test of 22 fails: `tests.test.the molfile route produces PubChem's published identifier and key` returns `error.MissingIdentifier` at `tests.zig:734` with `molfile: status rejected, message` and an empty message under `qemu-mips` and its siblings. The other 14 tests pass in every cell. A build-only cell compiled and had no runner | run `20261004T221720228710Z-45046`, receipt `inchi-53-target-8.json`, source stamp `bc5a479718…` |
| native final wave — **current source-bound** | `zig build test smoke install -Druntime=false`, both linkages × `Debug`, ReleaseSafe, ReleaseFast, ReleaseSmall | **8 of 8 `exit 0`**, each `30/30 steps succeeded` and `22/22 tests passed`. Native and linked only; nothing was opened through the platform loader | `native-final-evidence/20261004T233628757747Z-69351` |
| own-loaded wave — **current source-bound** | the same steps under `-Druntime=true`, both linkages × four modes | **8 of 8 `pass`**, each `31/31 steps succeeded` and `22/22 tests passed`. Every cell loaded a provider of kind `own` — the `libinchi.so.1.7.5` this tree's native wave installed — named by absolute path through `INCHI_TEST_PROVIDER`, with nothing read from the ambient environment and no fallback | `loaded-final-evidence/20261004T232823091897Z-23133` |
| `cross-test`, full 53-platform matrix — **current, on the shipped arrangement** | `cross-test` at the package root, through `cross-test.profile.sh` (`CROSS_BUILD_STEP=test`); each cell is `zig build test -Dtarget=<target> -j4 --summary all --test-timeout 300s` with the harness's own runner policy | **run on the arrangement this file ships, harness `exit_code: 0`.** Run `20261002-071259-33035-20483`, generated `2026-10-02T07:12:59Z`, `target_count: 53`, `target_jobs: 2`, `jobs_per_build: 4`, `build_timeout_seconds: 3600`, `run_timeout_seconds: 300`, `bookkeeping_failure: false`, counts `pass 20`, `fail 0`, `build_only 33`, `partial 0`. **20 cells executed the suite at 16 tests each — 320 tests actually run** — every one `Build Summary: 6/6 steps succeeded; 16/16 tests passed`, `reason: tests_complete`, `command_exit: 0`; the 33 others compiled only, `Build Summary: 5/6 steps succeeded (1 skipped)`, `reason: runtime_unavailable`, `command_exit: 0`. **No foreign BSD, macOS, Mac Catalyst, Windows or WASI binary was executed in any cell** — those 33 are a compile result and are labelled `build_only` because of it | `local://foundation-cross-test-final-current-inchi.json`, per-cell `local://foundation-cross-test-final-current-inchi-<target>.log` |
| `cross-test`, full 53-platform matrix — **HISTORY, before the guard reorder** | as above | **run, harness `exit_code: 0`.** Run `20261002-040235-43019-14341`, generated `2026-10-02T04:02:35Z`, `target_count: 53`, `build_timeout_seconds: 1800`, counts `pass 20`, `fail 0`, `build_only 33`, `partial 0`, the same 320 executed tests and the same 33 compile-only cells. **Every one of its 53 cells compiled the guard's first placement**, so it is history for the arrangement this file ships; none of its numbers is carried forward and no re-run of it is claimed | `local://foundation-cross-test-matrix-inchi.json`, per-cell `local://foundation-cross-test-matrix-inchi-<target>.log` |
| `cross-test --list` | `cross-test --list`, in the package root | **green, exit 0**: 53 targets listed in the harness's published order | `local://foundation-cross-test-profile-inchi-list_profile.log` |
| `cross-test --no-profile --list` | `cross-test --no-profile --list`, in the package root | **green, exit 0**: **the same 53 targets**, which is the profile's own proof that it narrows nothing | `local://foundation-cross-test-profile-inchi-list_no_profile.log` |
| `bash -n cross-test.profile.sh` | `bash -n <package>/cross-test.profile.sh` | **green, exit 0**. The profile's only assignment is `CROSS_BUILD_STEP=test`; the three checks above read it back through the harness | `local://foundation-cross-test-profile-inchi-syntax.log` |
| `<sys/timeb.h>` availability, seven `zig cc` probes | `zig cc -target <t> -E -H -include sys/timeb.h -x c /dev/null`, one per target | **5 present, 2 absent**: present on `x86_64-linux-gnu`, `x86_64-linux-musl`, `x86_64-netbsd` and `wasm32-wasi` with no diagnostic, present on `aarch64-freebsd` with upstream's own `warning: "this file includes <sys/timeb.h> which is deprecated"`, **absent on `aarch64-macos` and `x86_64-openbsd`**, both exit 1. A preprocessor probe over the compiler's real search path; **not** a build of this package and not a gate on it | `local://foundation-cross-test-timeb-header-availability.json` |
| guard placement, two `zig cc` runs of `ichicano.c` at `aarch64-macos` | `zig cc -target aarch64-macos -E -P -std=c11 -fno-strict-aliasing -DTARGET_API_LIB=1 [-DCOMPILE_ANSI_ONLY=1] INCHI-1-SRC/INCHI_BASE/src/ichicano.c`, both against the guard's **first** placement, before it moved | **exit 1 without the `-D`** — `ichicano.c:47:10: fatal error: 'sys/timeb.h' file not found` — and **exit 0 with it**. So the first placement compiled only because the command line agreed with the header, and both records carry the same `output_sha256`, which is **not** a comparison of two successful preprocessings: the failing run wrote a diagnostic, not a translation. What the pair does show is that a compiler-configured ANSI build of this file never needs the header, and that the first placement's success was a property of the `-D` this package supplies rather than of the source. **This is the observation behind moving the guard below `mode.h`** | `local://foundation-cross-test-inchi-guard.json` |
| `sha256sum -c UPSTREAM.sha256` over the record as it stands | as below | **not quoted in this file.** `UPSTREAM.sha256` holds **110** records — the 110th is `INCHI-1-SRC/INCHI_API/libinchi/gcc/libinchi.map`, upstream's ELF version script, added when shared-library delivery landed — and its `ichicano.c` line is the digest re-derived from the shipped file's own bytes; every receipt above verified a **109-line** record, so none of them is evidence about this one. The current whole-record replay is the driver's to run and to record, and it is recorded outside this document, in the workspace ledger's `cross_test_wave` — this file states no result, no exit code and no digest for it | — |
| what is still open over the shipped arrangement, and who owns it | `sha256sum -c UPSTREAM.sha256` over the current record, `zig fetch` + integrity + consumer over the settled documents, `zig build -fsys=inchi` | **owned elsewhere, and claimed by nobody here.** The current 53-cell matrix, the final six-target baseline and the stable native wave above all ran on the arrangement this file ships. The whole-record integrity replay and the final filtered package round are recorded by the driver in the workspace ledger's `cross_test_wave.materialized_packages.inchi` and in `local://foundation-cross-test-package-regression.json`, after these documents close; no result and no identity for either is asserted here, because this file's own bytes contribute to that identity. See § Cross-target checks for what the guard move does and does not touch — no chemistry, algorithm, ABI, allocator, option, default, flag or build mode changes with it. `zig build -fsys=inchi` has **not** been run in this workspace and is claimed by no row below | — |
| `zig build -fsys=inchi` | as in § Build modes | **not run.** It needs an installed `libinchi` carrying its own matching `inchi_api.h` and `ixa.h`; no such pair was available here, so no result is claimed for it | — |
| `zig build -Dlinkage=dynamic`, all four optimize modes | `zig build install -Dlinkage=dynamic -Doptimize=<mode>` | **current, source-bound** | the two eight-cell waves each ran four `-Dlinkage=dynamic` cells and every one exited 0 with `22/22 tests passed`, so a shared `libinchi` is built, installed and exercised in all four modes. The two std spellings this row used to carry as unconfirmed — `Step.Compile.setVersionScript` and `Build.installFile` — are settled by those sixteen configurations. The default linkage is unchanged at `static` |
| installed shared closure and a C consumer against it | `zig cc … -linchi …` after a shared install | **partly current** | the shared closure and its generated `inchi.pc` were installed sixteen times, so the file and the soname links exist as written. **No C consumer has linked against them**, and that half of the row is still withheld |
| `zig build -Druntime=true` and every runtime-loaded consumer check | `zig build test smoke install -Druntime=true`, then each consumer-behaviour gate | **partly current** | the own-loaded wave ran this route in all four modes and both linkages: eight cells, eight `pass`, `31/31 steps` and `22/22 tests` each, every one loading an own provider named by absolute path with no fallback. The **consumer-behaviour** gates, the compatible-external provider and the loader's failure paths have no receipt |
| `runtime-test` | `zig build runtime-test -Druntime=true`, with `INCHI_TEST_PROVIDER` and `INCHI_TEST_ALIEN` set | **`PENDING-VERIFICATION`** | the step exists only under `-Druntime=true`. It skips nothing when either variable is missing, so it cannot be run in a context that cannot name both. **Not in CI**, and the workflow says why: `INCHI_TEST_ALIEN` has to be a loadable object that is not `libinchi`, and inventing one here would be fabricating a fixture this repository does not have |
| `misuse`, all three modes | `misuse pre-load`, `misuse after-load <path>`, `misuse linked-load` | **`PENDING-VERIFICATION`** | built and installed by `zig build` in **every** configuration. **No step runs it and asserts an exit status**, because two of the three modes are supposed to stop and which two depends on the configuration. `zig build` owes that it produces the program; running the commands is the caller's. Describing a harness here that does not exist would be inventing one |
| `zig build consumer -Druntime=true -- --provider <path>` | — | **`PENDING-VERIFICATION`** | real only because `consumer/build.zig` now forwards `b.args` to the run step. Before that, the documented command line would have silently done nothing and the environment variable was the only way to name a provider |
| `nix build .#static` and `nix build .#shared` | — | **`PENDING-VERIFICATION`** | no `nix` evaluation and no `nix` build of `package.nix` or `flake.nix` has been run in this workspace. The `nixpkgs` input is pinned twice: by revision in `flake.nix:15`, and by the committed `flake.lock` at the package root pinning `c7def046b9a883d46974757852106483d741586f` with its `narHash` — the same rev. That lock is now in `.paths`, so a `.paths`-filtered copy carries `flake.nix` and the lock that pins it together. The row is **unrun, not unpinned**, and no `nix` result of any kind is claimed |
| `devenv shell` | — | **`PENDING-VERIFICATION`** | no `devenv` evaluation or shell entry has happened. `devenv.yaml` names a pinned input by revision, `cachix/devenv-nixpkgs` at `c2f38fe7f9e04d9aadd354d380f2bd40531d9737`, and **there is no `devenv.lock` in this repository** — none is invented to match the flake's, and the revision pin is what the shell resolves from |

Each of the four rows marked **current, source-bound** holds one source stamp
for its whole run, and the stamps differ from each other and from every row
above. A build-graph, header, helper or normalisation edit made after a stamp
describes a tree that row never saw, and no row here verifies one. The
whole-record `sha256sum -c UPSTREAM.sha256` over the 110-line record, the final
filtered package round, `zig build -fsys=inchi`, the Nix derivations, the devenv
shell, a foreign-compatible provider and the loader's failure, retry,
idempotence and provider-change paths are all still `PENDING-VERIFICATION`, and
this table quotes no result for any of them.

`CHANGELOG.md`, `FORK-NOTES.md`, `UPSTREAM.md` and `NOTICE.md` link to this
table instead of repeating it. When a claim and this table disagree, this table
is the one with a receipt behind it.

**What is history, and is kept as history.** These receipts are real runs and
none is withdrawn, but each one describes a tree this package has since left,
so none of their numbers is carried forward:

* `…-native-ReleaseSafe-corrected-193.log` — **red, exit 1**, the three
  diagnostics quoted in the next section. It is not restated as anything else,
  and it is superseded for the patched file by `-374`.
* `…-immutable-source-complete-legal-109-240.log` — 109 records, green, over a
  record whose `ichiparm.c` line still held **upstream's** digest.
* `…-external-driver-package-fetch-324.log`, `…-materialized-package-integrity-333.log`
  and `…-materialized-package-consumer-340.log` — one whole pre-patch package
  round: 109 of 109 `OK` and `consumer ok` **inside that copy**. A fetched copy
  is a snapshot and cannot contain a later edit. The later rounds `-382`,
  `-388` and `-389`, and the delivery round at `-449`, `-459` and `-460`, are
  history too; none of them describes the package as it stands, and none of
  their identities is quoted as current anywhere in this file.
* `…-pinned-native-pristine-diff-267.log` — `git diff --exit-code` with empty
  output, green, **while the tree was unmodified**. That was the property the
  first patch ended, so it is a statement about the pre-patch tree only. The
  scoped diff that followed, `-363`, is not a pristine proof either: it names
  one path and carries no `--exit-code`. **There is no pristine proof in this
  package's current history and none is claimed**: two upstream files are
  patched on purpose, which is the whole point of L18.
* `-183`, `-201`, `-202` … `-207`, `-209`, `-220` and `-225` — the pre-patch
  Debug, install, cross, consumer and installed-C rows, superseded row for row
  by the receipts above.
* `local://foundation-cross-test-matrix-inchi.json` — the earlier 53-cell
  `cross-test` run, green at the harness level over the guard's first
  placement. It is a real run and none of it is withdrawn; it describes a file
  this package no longer ships, the same relationship the pre-patch integrity
  receipts have to a record this one no longer names. The current matrix row
  above supersedes it.

### ReleaseSafe is green on the patched tree, and the old red is history

Zig's C backend rejects `__DATE__` and `__TIME__` expansions in a
ReleaseSafe-mode compile, and rejects the nested `/*` in upstream's own format
string. That is what `…-native-ReleaseSafe-corrected-193.log` recorded, in
three diagnostics: `'/*' within block comment` at `ichiparm.c:2597`, and two
`expansion of date or time macro is not reproducible` at `ichiparm.c:2718`, over
`__DATE__` and `__TIME__`. That receipt is **pre-patch**, it is **red**, and it
stays red as a statement about the file it compiled. It is **not** a verdict
about the package: the one narrow exception authorised for exactly those
diagnostics has landed, and the patched file has since been built and run in
ReleaseSafe.

**What was changed, from the authorisation and nothing beyond it:** the comment
correction at `ichiparm.c:2597` and the `__DATE__`/`__TIME__` arguments of the
usage banner in `HelpCommandLineParms`. No warning switch was added, no `-Wno-`
flag is passed, no suppression is conditional on the optimisation mode, no
diagnostic is filtered from any output, and no optimisation mode is substituted
for another.

**What was observed afterwards.** `taskset -c 0-7 zig build test smoke
--summary all -Doptimize=ReleaseSafe`, exit 0: `Build Summary: 9/9 steps
succeeded; 16/16 tests passed`, `run test inchi-tests 16 pass (16 total) 244ms`,
and the smoke program printing the four published identifiers and keys, the
renumbered ethanol, and `smoke ok`. Sixteen tests in Debug and sixteen in
ReleaseSafe, from one tree, in one session (`-365`, `-374`) — and again on the
shipped `ichicano.c`, from the stable wave: `zig build test smoke
-Doptimize=ReleaseSafe -j8 --summary all --color off`, exit 0, 18.584 s,
`Build Summary: 9/9 steps succeeded; 16/16 tests passed`,
`observed_tests_passed: 16`, `observed_tests_total: 16`. The `-365`/`-374`
pair predates the `ichicano.c` patch and is history; the stable pair is the
current ReleaseSafe evidence.

**Every cross row is a Debug row — the six baseline cells and all 53 matrix
cells alike.** Neither `check` nor the profile passes `-Doptimize`, so both
compile the facade for their targets and run nothing. ReleaseSafe is claimed
only where the table says so — the native `-374`, the `2026-10-02` ReleaseSafe
row and the stable ReleaseSafe row, the last of them the only one taken on the
file as it ships. Debug is not a substitute for ReleaseSafe and no step maps one
to the other.

**Three further `__DATE__`/`__TIME__` uses are untouched, on purpose.** They sit
in `OpenFiles`, at `ichiparm.c:2910`, `:2919` and `:2928`. All three are inside
`#ifndef TARGET_API_LIB`, which opens at `ichiparm.c:2887`, and **every build in
this package preprocesses that block away**: `core_macros` at `build.zig:166-169`
defines `TARGET_API_LIB` as `1`, and `build.zig:456` applies it to the one C
module. They are left exactly as upstream wrote them; they are named here so a
reader does not take their absence from the diagnostics as a claim about the
patched file.

### The authorised `ichiparm.c` patch, landed and covered

The owner authorised **one narrow exception, at the time, to
`INCHI_BASE/src/ichiparm.c` and to no other file** — that authorisation is
**historical**, and it was later superseded by a second, separately scoped one
for `ichicano.c` (§ The second patch, and its open row below; root
`AGENTS.md` §4 records both). **It has landed in this tree, and every row of the
table above was taken after it did.** Explicitly **not authorised** under it:
any algorithm, ABI, signature or control-flow change; any warning suppression;
any substitution of one optimisation mode for another.

Its scope, read out of the patched file rather than taken on report: the comment
correction at `ichiparm.c:2597`, where the format string
`"Timeout per structure: %lu/*.%03lu sec\n"` lost the `/` and the `*` became the
`.` the sentence meant — inside the `/* … */` block at `:2594-2599`, so no code
path changed; and the `__DATE__`/`__TIME__` arguments of the usage banner in
`HelpCommandLineParms`, in **both** of its branches, replaced by two string
literals defined immediately above the function at `:2707-2708`:

```c
#define INCHI_BUILD_SOURCE_TAG "v1.07.5"
#define INCHI_BUILD_STAMP_WHEN "(no build timestamp)"
```

The banner's format strings are untouched. Both branches still have the same
conversions and the same arguments in the same order and of the same types — the
replacements land in exactly the `%s` / `%-s` positions the macros filled. The
`#ifdef TARGET_EXE_USING_API` branch is at `:2718` with its arguments at `:2721`;
the `#else` branch is at `:2724` with its arguments at `:2727`.

**What the banner actually prints, as observed.** A C program linked against the
**installed patched** `libinchi.a` and the **installed** `inchi_api.h` called
`GetINCHI` on an empty input and read the help text back out (`-384`, `-385`,
both exit 0). The first two lines, shown exactly as the run printed them, each
ending in the single trailing space the `%s %-s` conversion leaves:

```
InChI version 1, Software 1.07.5 (API Library) 
Linux 64-bit Build (gcc Clang 21.1.0) of v1.07.5 (no build timestamp) 
```

Only the last two fields are this patch's. `Linux 64-bit` and `gcc Clang 21.1.0`
are **this host's** own `INCHI_BUILD_PLATFORM` and `INCHI_BUILD_COMPILER`,
reported by whichever compiler built that archive; they are out of the patch's
scope and would read differently elsewhere. `v1.07.5` and
`(no build timestamp)` are the two literals substituted here, in the very
positions `__DATE__` and `__TIME__` filled, so no build-time date claim exists
anywhere in the text. Nothing is filtered out of that output.

**Line numbers moved, and only from `:2699` down.** The pre-existing `/****/`
separator stays where it was at `:2699`; the patch adds **nine** lines at
`:2700-2708` — the explanatory comment and the two `#define`s — so
`HelpCommandLineParms` moved from `:2700` to `:2709` and every line below it
shifted by nine. The banner and `OpenFiles` numbers above are therefore
**post-patch**, as are the numbers in the previous section that cite `2910`,
`:2919` and `:2928`. Every other `ichiparm.c` line number in this file — `2597`
above, and the `:2712`, `:2718` and `:2901` figures quoted from the pre-patch
diagnostics — is a **pre-patch** citation.

**The record.** `UPSTREAM.sha256` holds **110 records** — it was 109 when this
was written, and grew by the ELF version script
`INCHI-1-SRC/INCHI_API/libinchi/gcc/libinchi.map` when shared-library delivery
landed, so no receipt below covers it — and carries the
**patched** digest for that one line; upstream's digest for the same path, and
the file's byte count either way, are written out in `UPSTREAM.md`
§ The two patched source files. `sha256sum -c UPSTREAM.sha256` was green over
all 109 on the then-patched tree at the repository root (`-364`) and again
inside the `.paths`-filtered copy (`-388`); **both are history for the
`ichicano.c` line**, which has since been patched and re-derived. The patch
records, the integrity updates and the provenance around them are the patch
owner's — see `UPSTREAM.md`, `NOTICE.md` and `FORK-NOTES.md`; this file repeats
the counts, not the digests.

**The second patch, and where it stands.** `aarch64-macos-none` failed on
`#include <sys/timeb.h>` at `INCHI_BASE/src/ichicano.c:46`
(`…-authorized-patch-cross-aarch64-macos-none-369.log`), and that file was
patched under a second, separately scoped authorisation: the include sits
inside `#ifndef COMPILE_ANSI_ONLY`, the macro its only two readers were already
behind, and the guard sits **after `#include "mode.h"`** at `ichicano.c:49-51`
because `mode.h:197-201` is what defines that macro. Both arrangements are
described in § Cross-target checks, with the seven header probes that say which
targets actually lack the header — **macOS and OpenBSD, not WASI**.

**What has been observed since — and on which arrangement.** Two full-matrix
runs stand over the patched file, and they describe two different placements.
The earlier one compiled it in every one of its 53 cells: 20 executed the suite
at 16 tests each, and the 33 runner-less cells compiled and stopped there. The
four Apple cells and the nine OpenBSD cells are `build_only`, which is a compile
result and not a runtime result, and nothing in this file says a foreign binary
ran. That matrix finished **before** the guard moved, so it describes the first
placement and is history for the second.

The shipped arrangement — the guard below `mode.h` — has been compiled since, by
three waves. The 53-cell matrix has been re-run on it: run
`20261002-071259-33035-20483`, harness `exit_code: 0`, every one of the 53 cells
exit 0, and the same split of 20 cells executing 16 tests each and 33 compiling
only (`local://foundation-cross-test-final-current-inchi.json`). The six-target
`check` baseline is green in **all six** cells of the workspace's 48-cell round,
`Build Summary: 6/6 steps succeeded`, exit 0 each, including the
`aarch64-macos-none` cell that used to be red; that row is now superseded by a
re-run of itself and not only by the broader matrix. The stable native wave is
green in both modes on the same tree: `test smoke install -Doptimize=Debug`,
16/16, 11/11 steps; `test smoke -Doptimize=ReleaseSafe`, 16/16, 9/9 steps; and
the `consumer` build through `dep.module("inchi")`, 6/6 steps. Every one of
those receipts is in § Verification status.

**Driver-owned closures.** This file quotes no result for current whole-record
`sha256sum -c UPSTREAM.sha256` or the final filtered package round over these
settled documents. Their current statuses and receipts are recorded outside
this package in `FORKS.json.cross_test_wave.materialized_packages.inchi` and
`local://foundation-cross-test-package-regression.json`: this file's own bytes
contribute to the package identity. `zig build -fsys=inchi` is the one gate
that is simply unrun, and nothing is claimed for it in either direction. See
`CHANGELOG.md` §30, §31, §32 and §33 and `FORK-NOTES.md` decisions 17 and 19.

**Every other native file in every fork keeps its upstream bytes.** These two
exceptions are not a precedent and are not generalised beyond these two files.

**What that means for the table above.** Nothing is claimed for the patched
tree that the table does not carry a receipt for, and every row names the tree
it describes. The rows that predate the guard reorder — the `-365`/`-374`/`-373`
set, both `2026-10-02` native waves, the installed C/IXA and banner rows and
the 53-cell matrix **run before it** — are history for it and are labelled so;
the three waves that came after it are the current matrix, native and baseline
evidence. The packaging rows are history for the current documents, and this
file quotes no package identity at all.

### What the packaging rows establish, and what they do not

**All four packaging rows are history.** Each answers one question — does the
package a dependent receives actually contain this library — and each answered
it about a copy made **from `.paths` alone** at the moment it was taken. Source
closure through the manifest was observed rather than argued: the 105 native
files this package ships across the two source directories, the Apache-2.0 text
that travels with the Intel TBB header, the upstream MIT text, upstream's own
README — then at `README.md`, now preserved at `README.upstream.md` — and the
independent fixture were all present in the fetched tree,
and a consumer built there resolved the library through `dep.module("inchi")`
with no source-tree path available to it. **None of that changed with a later
edit to a patched C file or to this document**, and none of it is withdrawn.

**What makes them history rather than current is the identity.** A fetched
directory's hash covers every byte `.paths` selects, including the two patched
C files and these documents, so quoting one beside a document that is still
being edited is a circular claim. Both rounds are named in the table with their
receipts; **the final package round runs once these documents settle, and its
result and identity are recorded by the driver, in the root ledger's `FORKS.json`
under `cross_test_wave.materialized_packages.inchi` and in
`local://foundation-cross-test-package-regression.json`. This file asserts no
package identity and quotes no result for that round.**

They are **not** a registry or publication proof either. Each fetch was given a
local directory on this machine; nothing was published, pushed, uploaded or
resolved from a registry, and each identity is a property of a local directory
rather than of a `.url` hash. `INCHI-1-TEST/` is still deliberately outside
`.paths`, so a materialised package still does not carry upstream's test tree —
and nothing in these rows claims it should.

### What the native rows do and do not establish

The native test rows ran **every test `tests.zig` declared at the time**, in one
binary each, against the translated header and the in-tree archive, three times
in Debug and three times in ReleaseSafe: the `-365`/`-374` pair, the `2026-10-02`
wave, and the stable wave. Sixteen per mode per wave, **96 native test
executions in all**, plus 320 per full-matrix run from the twenty cells that ran
the suite, across two full-matrix runs. Every one of those numbers is a count of
a **sixteen-test** `tests.zig`, and every row that prints one is marked
`HISTORY`.

**`tests.zig` as it ships declares 22 top-level test blocks** — `:185, 213, 232,
259, 274, 302, 322, 340, 400, 428, 446, 464, 488, 526, 556, 574, 599, 652, 672,
707, 753` and `:810`. Six of them landed after the last recorded wave: the two
extended polymer/V3000 routes at `:753` and `:810`, the AuxInfo-refusal residue
test at `:652`, the molfile refusal/residue test at `:707`, and the tests at
`:526` and `:574`. **No receipt in this file has executed the file as it ships,
and no 22-test result is claimed anywhere in it.** The six counts above are
history, not a current baseline, and the two "stable wave" rows no longer call
themselves the current native evidence for the file as it ships — their own
`expected_tests: 16` is the evidence that the tree they compiled declared
sixteen.

**What does not move is compile coverage.** The six-target `check` baseline and
every `build_only` matrix cell are compile results; adding a test does not change
what compiles, so those rows stay current and the table says so row by row.

The install step is the one that proves the artifact
itself: it produced `libinchi.a` and both public headers, and the C/IXA rows then
compiled against **that installed copy**, not against the tree, with upstream's
own `inchi_api.h` (which ends with `#include "ixa.h"`) and no wrapper — a real
V2000 molfile for ethanol through `MakeINCHIFromMolfileText`, and a real IXA
status/molecule/builder handle chain for water, with every handle destroyed on
every path including the error paths. The banner rows link that same installed
archive and read the usage text back out of it. Both of those row sets are
history: they link the archive the `-365` install produced, which predates the
`ichicano.c` patch. That is the compiled SDK
reachable from C; `zig build -fsys=inchi` is a different thing and is still
unrun.

Every earlier red receipt in this package's history (`-initial-debug-15`,
-repaired-debug-23`, `-current-debug-49`, `-current-smoke-59`,
-current-install-60`, `-current-releasesafe-62`, `-current-consumer-65`,
-repaired-smoke-proof-69`, `-boundary-debug-122`, `-fixture-debug-150`,
-static-fixture-debug-152`, `-known-answer-debug-156`,
-native-Debug-corrected-fixtures-178`, `-native-consumer-corrected-210`)
describes a file state since corrected. One of them is worth keeping in view:
`…-native-consumer-corrected-210.log` is a *consumer* fault, not a library one.
It asserted `checkIdentifier("InChI=1S/H2O/h1H2", /* strict */ true)` is
`standard`; upstream's strict check regenerates the identifier with the
layer-keeping options and demands it back unchanged (`inchi_dll.c:954-981`),
which a `1S` identifier cannot satisfy, so the correct verdict is
`conversion_failed` and the shallow check is the one that returns `standard`.
The consumer was corrected; nothing about the library was loosened to suit it.

## Integrity

```
sha256sum -c UPSTREAM.sha256
```

**The green replay below is history; the record is now 110 lines.** `sha256sum -c
`UPSTREAM.sha256` reported 109 records, 109 `: OK` lines and no failures, exit 0,
the last of them `INCHI-1-SRC/INCHI_API/tbb/LICENSE: OK`
(`local://foundation-expansion-inchi-authorized-patch-integrity-109-364.log`).
That receipt was taken with `ichiparm.c` patched and **`ichicano.c` still at
upstream's digest**: both `ichicano.c` digests since then were re-derived by
hashing the patched file's own bytes. The current whole-record replay result
belongs to the driver-owned closure above, not that earlier receipt.

**What the 109 are.** 108 upstream records plus one that is not upstream's at
all. The 108 are the 105 files this package ships from the two upstream-owned
source directories — the complete compile unit list of that CMake target plus
every header reached from them, the two public headers that get installed,
stb_sprintf 1.10, the SHA-256 implementation and upstream's own `CMakeLists.txt`
for the target — then upstream's full Apache-2.0 text
(`INCHI-1-SRC/INCHI_API/tbb/LICENSE`, added so the Intel TBB header travelling
in the package travels with its terms; see § Licence), upstream's MIT text as
`LICENSE`, and upstream's own `README.md`. Of those 108, **106 are byte-identical
to the pin and two — `INCHI-1-SRC/INCHI_BASE/src/ichiparm.c` and
`INCHI-1-SRC/INCHI_BASE/src/ichicano.c` — are this fork's authorised patches**;
upstream's digest for each is preserved in `UPSTREAM.md` as the written
baseline, and the record carries the patched one, because those are the bytes
the build compiles. The 109th line, `testdata/pubchem_known_answers.tsv`,
is the independent PubChem fixture, so "all 109 recorded files are upstream's,
byte for byte" would be false by that one line. Nothing else is recorded, so the
same command works in a clone and in an unpacked package.

**The record has also been run inside a materialised package.** Running the same
command **inside a `.paths`-filtered fetched copy** reported all 109 records
`OK` (`…-inchi-current-filtered-package-integrity-388.log`, repeated by
`…-inchi-delivery-final-package-integrity-459.log`) — so this is not merely a
repository-root check, and every line of the record has a file behind it in the
copy a dependent receives. **Both are history**: each copy was a snapshot taken
before the `ichicano.c` patch and before these documents settled, and **this
file quotes no fetched package identity**, because such an identity is a hash of
the very documents this section sits in.

**No receipt in this package's history describes the record as it stands.** `-240`
verified the same 109 paths while the `ichiparm.c` line still held **upstream's**
digest; `-364` verified them with `ichiparm.c` patched and `ichicano.c` still
upstream's; `-333`, `-388` and `-459` verified them inside three different
filtered snapshots, none of which could contain a later edit. The current
`ichicano.c` line and the whole-record check over the tree as it stands are the
parent's to run. The earlier 108-record run
(`…-immutable-source-including-complete-Apache-license-221.log`, byte-identical
to `…-immutable-source-integrity-127.log`) predates the Apache text altogether
and is kept for the same reason every pre-patch receipt is: it is a real run.

**The record describes itself.** `UPSTREAM.sha256`'s own header states 109
records, names `INCHI-1-SRC/INCHI_API/tbb/LICENSE` as one of them with a line
explaining why it is there, excepts that same path from the "deliberately
absent" list, and names `ichiparm.c` and `ichicano.c` as the two of the 105 this
fork patched, with upstream's digest beside each record's — so a reader who
trusts the prose and a reader who trusts the lines are reading the same set.
See [`UPSTREAM.md`](UPSTREAM.md) for how the digests were produced and what they
do and do not prove.

## Licence

Upstream's InChI library is `MIT`, and **not bare MIT**: on top of the
permission grant, upstream's own bytes carry an attribution-notice obligation
(`inchi_api.h:29-37`, `LICENSE:12-13`) and a **compulsory project banner** —
the usage banner that identifies the software version, printed by
`HelpCommandLineParms` in `ichiparm.c` and carried in every identifier's `1S`
prefix. Both are recorded in [`NOTICE.md`](NOTICE.md) § The grants, and which
applies where, with their exact line citations. The text ships verbatim as
`LICENSE` and 100 of the 105 shipped native files carry the same notice. Three
files in the shipped set are not simply MIT and are not claimed to be:
`sha2.c`/`sha2.h`, whose MIT grant upstream qualifies as valid *only in
combination with the InChI package*; `stb_sprintf.h`, `MIT` **or** the Unlicense
— its own licence block offers `ALTERNATIVE A - MIT License` and
`ALTERNATIVE B - Public Domain (www.unlicense.org)` and leaves the choice to the
reader (`stb_sprintf.h:1866-1888`);
and `tbb/tbbmalloc_proxy.h`, `Apache-2.0` and Intel's, which nothing here
compiles but which does travel.

**The Apache-2.0 obligation is discharged.** The package ships upstream's own
`INCHI-1-SRC/INCHI_API/tbb/LICENSE` — the full Apache License 2.0 as it sits in
the pinned tree — beside that header. No licence text was authored, copied in
from elsewhere, or restated, and the header itself is unmodified, so there are
no changes to declare under §4(b); upstream ships no `NOTICE` text for that
file, so there is none to propagate under §4(d). The earlier gap, recorded in
`CHANGELOG.md` §18, is closed by the manifest, not by this documentation.

**The landed `ichiparm.c` patch has its own record, not this section's.** That
patch edits a shipped upstream file, so its scope, its diff and the terms it
preserves belong to its owner — the patch record, `UPSTREAM.md` and
[`NOTICE.md`](NOTICE.md) — and are deliberately not restated or re-audited here.
The terms stated above are upstream's as they stand, and none of them is widened,
narrowed or replaced by this documentation; see [The authorised `ichiparm.c` patch,
landed and covered](#the-authorised-ichiparmc-patch-landed-and-covered) for
what the patch changed and what it deliberately did not.

**This fork's own files are under `LicenseRef-InChI-MIT-Conditional`** — the
MIT text plus the attribution-notice and package-coupling conditions, with the
owner authorization behind it. They were previously recorded here as
**unassigned**, and that is what that state was. The grant is defined in
[`FORK-LICENSE.md`](FORK-LICENSE.md) and inventoried in
[`NOTICE.md`](NOTICE.md); no copyright identity is asserted for this fork,
because none was supplied. None of this changes an upstream term.