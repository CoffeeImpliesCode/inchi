# UPSTREAM

## Identity

| Field | Value |
|---|---|
| Project | InChI, the IUPAC International Chemical Identifier |
| Repository | `https://github.com/IUPAC-InChI/InChI.git` |
| Tag | `v1.07.5` |
| Commit | `11a87982bb518f57ac013f0b258c283655e1ea1d` |
| C library version | `1.07.5` (`bcf_s.h`); release date: April 30, 2024 |
| Source acquisition | Full clone of the canonical repository, with upstream history and the `upstream` remote |
| Full-tree deterministic git-archive SHA-256 | `55382c70314a01a9d2f3a18f0833a44c352d7332884f614f28cbb1d40c17d5f6` |
| Integrity record | `UPSTREAM.sha256` — 110 entries: 107 upstream files, `LICENSE`, upstream `README.md` and the independent fixture |

The archive digest covers the full upstream tree. `UPSTREAM.sha256` covers the shipped subset and the fixture, not the full tree. Upstream's README is preserved as `README.upstream.md`, SHA-256 `90c885dabbed6b320728d8cc84fe30f0d323116213c77b6231950c90b80ba824`.

The two shipped source directories contain 105 files: 86 in `INCHI-1-SRC/INCHI_BASE/src` and 19 in `INCHI-1-SRC/INCHI_API/libinchi/src`. The integrity record includes those 105, upstream's TBB licence and ELF version script, `LICENSE`, `README.upstream.md` and `testdata/pubchem_known_answers.tsv`.

## Source deviations

| Upstream path | Fork change |
|---|---|
| `INCHI-1-SRC/INCHI_BASE/src/ichiparm.c` | Fix an accidental nested-comment delimiter; replace `__DATE__` and `__TIME__` in the usage banner with `v1.07.5` and `(no build timestamp)`. Upstream SHA-256: `eb3516115a1d25776f823de800d1c61cf0161e5bedbecac3511cd21ec0de2478`; current SHA-256: `74302e26597450060b8341a569f4fd8a07813aadce1f05e9b3507c34980cdd3a`. |
| `INCHI-1-SRC/INCHI_BASE/src/ichicano.c` | Move `<sys/timeb.h>` below `mode.h` and guard it with `#ifndef COMPILE_ANSI_ONLY`, after the header defines that macro. Upstream SHA-256: `5c031a2b441dc08509f75fe22e4b6ecddf285ada625b4a69cf77d2920d42f891`; current SHA-256: `9a0998a3a41f62508e755d9411bf3c78b2b7b1ae63edcea7a40c55307130d98`. |
| `.gitignore` | Keep upstream rules and append fork build-output ignores; this edited file is not in `.paths` or the integrity record. |

All other upstream files shipped by `.paths` are unchanged. The upstream MIT text is in `LICENSE`; the per-path licence exceptions are in `NOTICE.md`.

## Build graph

The Zig build compiles 60 upstream C translation units: 48 from `INCHI_BASE/src`, six from `libinchi/src` and six from `libinchi/src/ixa`. It builds the `libinchi` API library, including the IXA backend, rather than the standalone executable. `build.zig` lists source files explicitly.

The C modules use `-std=c11`, `-fno-strict-aliasing`, `TARGET_API_LIB=1` and `COMPILE_ANSI_ONLY=1`. `translate.h` applies the same two macros to translated declarations. The upstream ELF version script `INCHI-1-SRC/INCHI_API/libinchi/gcc/libinchi.map` ships for dynamic ELF linking.

## Upstream files not shipped

| Paths | Scope |
|---|---|
| `INCHI-1-SRC/INCHI_EXE/`, `INCHI-1-SRC/INCHI_BASE/redundant/`, `INCHI-1-SRC/INCHI_API/demos/`, `INCHI-1-SRC/INCHI_API/bin*/` | Standalone executable, superseded sources, demos and prebuilt binaries. |
| `INCHI-1-SRC/INCHI_API/tbb/` | Allocator sources and wrapper are not shipped; `INCHI-1-SRC/INCHI_API/tbb/LICENSE` is shipped for the Apache-2.0 header in `INCHI_BASE/src/tbb/`. |
| `INCHI-1-SRC/INCHI_API/libinchi/gcc/`, `INCHI-1-SRC/INCHI_API/libinchi/vc14/` | Upstream makefiles and Visual Studio project; `libinchi/gcc/libinchi.map` is the exception and is shipped. |
| `INCHI-1-SRC/readme.txt`, `INCHI-1-SRC/cmake_build_tool.sh`, `INCHI-1-SRC/cmake_build_tool.bat` | Upstream notes and CMake drivers. |
| `INCHI-1-DOC/`, `INCHI-1-TEST/` | Manuals, release notes, FAQ and upstream test distribution. |
| Root `CMakeLists.txt`, `Doxyfile`, `.devcontainer/`, `.editorconfig`, `.gitattributes`, `.dockerignore` | Upstream build, documentation and development configuration. |

`INCHI-1-SRC/INCHI_API/libinchi/src/CMakeLists.txt` and `INCHI-1-SRC/INCHI_BASE/src/readme.txt` are inside the shipped source directories; neither is compiled. `INCHI-1-SRC/INCHI_API/tbb/LICENSE` and `INCHI-1-SRC/INCHI_API/libinchi/gcc/libinchi.map` are the only files from otherwise unshipped upstream directories included in `.paths`.
