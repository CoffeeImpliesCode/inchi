# InChI for Zig

InChI is the IUPAC chemical identifier. This package builds upstream InChI 1.07.5 as a Zig package with a typed facade over `libinchi`.
The upstream project README is preserved as `README.upstream.md`.

## Source deviations from upstream

Two upstream C files are patched:

| File | Change | Reason |
|---|---|---|
| `INCHI-1-SRC/INCHI_BASE/src/ichiparm.c` | Replaces build-date and build-time banner values with the pinned source tag and a fixed timestamp string; fixes a nested-comment delimiter. | Stable help output and compatibility with Zig's safe C backend. |
| `INCHI-1-SRC/INCHI_BASE/src/ichicano.c` | Moves `<sys/timeb.h>` below `mode.h` and guards it with `#ifndef COMPILE_ANSI_ONLY`. | The ANSI-only path does not use that header, which is absent on some target sysroots. |

No other upstream C source is modified. The build compiles all 60 upstream translation units, including IXA. `UPSTREAM.md` records the pin and patch details.

## Build deviations

`build.zig` compiles upstream's C directly with Zig; the carried CMake, Make, and Visual Studio projects are not used. The compile uses `-std=c11`, `-fno-strict-aliasing`, `TARGET_API_LIB=1`, and `COMPILE_ANSI_ONLY=1`.

Dynamic ELF builds use upstream's `libinchi.map`; non-Windows shared builds use position-independent code. Windows DLL export macros are added only for the MSVC ABI. Upstream's `-z relro` flag is not passed. `.gitignore` keeps upstream's rules and adds Zig and development-environment outputs.

`zig build install` installs the selected library, `inchi_api.h`, `ixa.h`, `lib/pkgconfig/inchi.pc`, the `misuse` executable, and licence/provenance records. The `.pc` file is relocatable and includes platform-specific `libm` linkage where needed. `misuse` accepts `pre-load`, `after-load <path>`, and `linked-load`; build steps do not run these modes.

Build options:

| Option | Default | Effect |
|---|---|---|
| `-Dlinkage=static` or `-Dlinkage=dynamic` | `static` | Selects static or target-native shared linkage. |
| `-Druntime=true` or `-Druntime=false` | `false` | Uses runtime symbol dispatch instead of linking symbols into the facade; the library artifact is still built and installed. |
| `-fsys=inchi` / `-fno-sys=inchi` | bundled | Uses an installed `libinchi` and its headers, or the bundled source. System mode uses pkg-config. |
| `-Dtarget`, `-Doptimize` | Zig defaults | Select the target and optimization mode. |

System mode and runtime loading cannot be combined. Runtime loading requires an OS dynamic loader; it is unavailable on WASI, Emscripten, and freestanding targets.

`zig build runtime-test -Druntime=true` requires `INCHI_TEST_PROVIDER`, an absolute path to a real InChI shared library, and `INCHI_TEST_ALIEN`, an absolute path to a loadable object without InChI exports.

## Support matrix

| Route | Targets and scope |
|---|---|
| `zig build check` | `x86_64-linux-gnu`, `aarch64-linux-gnu`, `aarch64-macos-none`, `x86_64-windows-gnu`, `riscv64-linux-gnu`, and `wasm32-wasi`; compiles and links, but does not execute foreign binaries. |
| `cross-test` | The 53-target harness matrix; `cross-test.profile.sh` selects static, linked builds. Targets without an executor are build-only. |

The last recorded matrix executed 20 targets: 12 passed and 8 failed in the big-endian molfile known-answer test (`aarch64_be-linux`, `armeb-linux`, `mips-linux`, `mips64-linux`, `powerpc-linux`, `powerpc64-linux`, `s390x-linux`, `thumbeb-linux`); 33 targets were build-only. WASI uses static linking and has no shared-library or `dlopen` support.

## Consumption

### Zig

Add the package to `build.zig.zon`:

```sh
zig fetch --save git+https://github.com/CoffeeImpliesCode/inchi#v1.7.5
```

Import its module in `build.zig`:

```zig
const dep = b.dependency("inchi", .{ .target = target, .optimize = optimize });
exe.root_module.addImport("inchi", dep.module("inchi"));
```

The module and Zig library artifact are named `inchi`; C consumers link `libinchi` with `-linchi`. The typed API is documented in `README.zig.md`.

### C

`inchi_api.h` includes `ixa.h`, so one header exposes the classic and IXA APIs. Link with the installed pkg-config file:

```sh
cc my_tool.c $(pkg-config --cflags --libs inchi)
```

### Nix and development

`nix build .#static` builds the default static package; `nix build .#shared` builds the shared package. `devenv shell` provides development tools, not a prebuilt SDK.

Licensing is mixed: see `NOTICE.md` for upstream and per-file terms, and `FORK-LICENSE.md` for the fork-authored files.