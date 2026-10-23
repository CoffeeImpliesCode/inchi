# InChI fork notes

## Source deviations

| File | Change and reason |
|---|---|
| `INCHI-1-SRC/INCHI_BASE/src/ichiparm.c` | Replace the build-time and date macros in `HelpCommandLineParms` with `v1.07.5` and `(no build timestamp)`, and reword a comment containing nested `/*`; this stabilizes help output and lets Zig's ReleaseSafe C backend compile the file. |
| `INCHI-1-SRC/INCHI_BASE/src/ichicano.c` | Move the `sys/timeb.h` include below `mode.h` and guard it with `COMPILE_ANSI_ONLY`; `mode.h` defines the macro, and the ANSI-only build does not use that header. |

## Build graph deviations

- `build.zig` replaces the upstream CMake/Make build and lists all 60 upstream C translation units explicitly: 48 base, 6 API, and 6 IXA units.
- C compilation and translation use `TARGET_API_LIB=1` and `COMPILE_ANSI_ONLY=1`; C flags are `-std=c11` and `-fno-strict-aliasing`.
- The package publishes the Zig module `inchi` and the C library `libinchi`. For bundled sources, `-Dlinkage=static|dynamic` selects linkage; static is the default.
- Shared ELF builds use upstream's `libinchi.map`; shared non-Windows builds add `-fPIC`.
- `-fsys=inchi` translates the installed `inchi_api.h` and resolves the library through pkg-config instead of compiling bundled sources. It cannot be combined with `-Druntime=true`.
- `-Druntime=true` uses generated dispatch for the facade while still building and installing the C artifact.
- `test`, `smoke`, `check`, and `consumer` are package build steps. `check` compiles the facade, tests, and smoke program without running target binaries; `consumer` builds the separate consumer package and runs it only when an executor is available.
- `cross-test.profile.sh` sets only `CROSS_BUILD_STEP=test`; the harness selects targets and executors.
- `package.nix` supplies the shared Nix derivation. The flake exposes static and shared outputs, with static as default; the development shell provides tools without building the SDK.

## Platform boundaries

- WASI has no shared C library or `dlopen`; dynamic linkage and runtime loading are unavailable there.
- The `ichicano.c` guard avoids requiring `sys/timeb.h` in ANSI-only builds on macOS and OpenBSD, whose sysroots lack that header.
- Dynamic Windows builds use import/export definitions only for the MSVC ABI; MinGW relies on linker auto-export.
- Cross-target `check` compiles but does not execute binaries; `consumer` runs only when Zig finds an enabled host executor.