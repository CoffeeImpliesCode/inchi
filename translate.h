/*
 * translate.h - the translation unit root for addTranslateC in bundled mode.
 *
 * Zig's `zig translate-c` reads exactly one header and makes every declaration
 * it can see available to Zig as the module `c`, which zig/root.zig imports.
 * InChI's public API is two headers, INCHI_BASE/src/inchi_api.h and
 * INCHI_BASE/src/ixa.h, and the first one already ends with
 * `#include "ixa.h"` (inchi_api.h:1413), so including inchi_api.h translates
 * both: the whole Get, Free and Check function surface and the IXA handle API,
 * nothing hand-listed and nothing omitted.
 *
 * This file exists for one reason: the macros below.
 *
 * Upstream builds its API library with TARGET_API_LIB and COMPILE_ANSI_ONLY
 * defined - `target_compile_definitions(libinchi PRIVATE fPIC COMPILE_ANSI_ONLY
 * TARGET_API_LIB)` at INCHI-1-SRC/INCHI_API/libinchi/src/CMakeLists.txt:154-158,
 * and `-DTARGET_API_LIB -DCOMPILE_ANSI_ONLY` in libinchi/gcc/makefile:129. The
 * two spellings of the same configuration for the same sources have to agree.
 * They select the API library build of InChI rather than the stand-alone
 * executable or the wInChI library build, and they decide which declarations the
 * exported headers expand to: `INCHI_API`, `EXPIMP_TEMPLATE` and `INCHI_DECL`
 * are all defined from those macros in inchi_api.h:691-709, and they are what
 * stand between a static archive and a `__declspec(dllimport)` declaration on
 * Windows. build.zig defines the identical pair on the C core's own compile
 * line; this header is the same pair on the translation's line, so the two
 * sides of the binding cannot drift apart.
 *
 * The guards are `#ifndef` so an external -D of the same macro, from a
 * consumer's own build, cannot turn into a redefinition.
 *
 * Nothing here adds or removes an upstream declaration: the file is a macro
 * prelude and one include, and the macro values are upstream's own.
 */

#ifndef FOUNDATION_INCHI_TRANSLATE_H
#define FOUNDATION_INCHI_TRANSLATE_H

/* Matches `core_macros` in build.zig, which defines exactly these two. */
#ifndef TARGET_API_LIB
#define TARGET_API_LIB 1
#endif
#ifndef COMPILE_ANSI_ONLY
#define COMPILE_ANSI_ONLY 1
#endif

/* Quoted form on purpose: this is the repository's own header, found on the
 * include path build.zig adds for the bundled mode. The `-fsys=inchi` mode uses
 * its own generated wrapper, which includes <inchi_api.h> by angle brackets so
 * the installed header next to the installed library is what gets translated. */
#include "inchi_api.h"

#endif /* FOUNDATION_INCHI_TRANSLATE_H */