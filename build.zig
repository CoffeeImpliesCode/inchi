//! SPDX-License-Identifier: LicenseRef-InChI-MIT-Conditional
//! See FORK-LICENSE.md for the full grant and the owner authorization behind it.
//! Build graph for the IUPAC/InChI `libinchi` core.
//!
//! What this builds, and from where:
//!
//!   * The complete upstream API library, compiled from this repository's own
//!     C sources. The compile unit list is the `target_sources(libinchi PRIVATE
//!     ...)` block of `INCHI-1-SRC/INCHI_API/libinchi/src/CMakeLists.txt`,
//!     written out below file by file rather than globbed, so a new upstream
//!     translation unit cannot enter the archive without a decision here.
//!
//!   That block names 103 paths: 60 `.c` files — 6 in `libinchi/src`, 6 in
//!   `libinchi/src/ixa`, 48 in `INCHI_BASE/src` — and 43 headers, which are
//!   reached by `#include` and of which two are public. The three lists below
//!   are those 60 by name and nothing is globbed: a shared build compiles the
//!   same 60 files as a static one, because `-Dlinkage` chooses how they are
//!   linked, never which of them exist. The block's only other entries are
//!   `${P_VC}/libinchi.rc` and `${P_VC}/libinchi.aps`, added under
//!   `if(WIN32 AND MSVC)` (src/CMakeLists.txt:137-142); those are MSVC resource
//!   files for a DLL, and a `-Dlinkage=dynamic` Windows artifact is linked by
//!   Zig's linker, which takes no .rc input — so no translation unit is missing
//!   here, and none is dropped to make room.
//!
//!   * `inchi`, the Zig facade over the translated public API. The facade root
//!     is `zig/root.zig` and it reaches the C declarations through
//!     `@import("c")`, the module produced by `addTranslateC`.
//!   * `tests.zig` and `smoke.zig`, which call every public facade entry point.
//!
//! There is no CMake, no autotools, no Make and no download. Upstream's core has
//! no generated inputs at all: there is no `inchi_version.h`, no `.h.in`, no
//! configure step, so there is nothing to generate and nothing to fetch.
//!
//! What the default install step delivers, for both linkages:
//!
//!   * `lib/libinchi.a` for `-Dlinkage=static` (the default, unchanged), or
//!     `lib/libinchi.so` with its version and soname symlinks for
//!     `-Dlinkage=dynamic`, or `lib/inchi.dll` plus `lib/inchi.lib` for a
//!     Windows target. `b.addLibrary` owns the file name and the version and
//!     soname metadata; upstream's own `PREFIX ""` (src/CMakeLists.txt:165)
//!     produces the same `libinchi.*` file name that Zig's default `lib` prefix
//!     produces.
//!   * `include/inchi_api.h` and `include/ixa.h`, the complete public header
//!     closure: `inchi_api.h` ends with `#include "ixa.h"` and neither header
//!     includes anything but the other, so two files is the whole surface a C
//!     consumer needs.
//!   * `lib/pkgconfig/inchi.pc`, generated here. Upstream ships no pkg-config
//!     file and no install rules, so this file describes *this* install tree
//!     and is the only place its name, `-linchi` and libm dependency are
//!     stated. It locates itself with `${pcfiledir}`, so it is correct for any
//!     `--prefix` this build is installed under.
//!   * `share/licenses/inchi/` with `LICENSE`, `NOTICE.md`, `FORK-LICENSE.md`,
//!     `UPSTREAM.md`, `FORK-NOTES.md`, `UPSTREAM.sha256`,
//!     `README.upstream.md` and `tbb/LICENSE`, through
//!     `installLicenceRecords`. A private repository removes no licence
//!     obligation, and a package that ships a binary without them is the
//!     failure this prevents. `share/doc/inchi/` carries the same files again
//!     as documentation; both claims are kept rather than one being renamed
//!     into the other.
//!   * `bin/misuse`, this package's own diagnostic program, and nothing else.
//!     InChI itself installs no tools and no runtime data, so the *library*
//!     contributes no `bin/` and no data tree; that is a fact about upstream,
//!     recorded rather than filled in. The one program here is fork-authored and
//!     is the only executable this build produces, because it is the only way to
//!     observe what a call before a successful load does.
//!
//! Runtime loading
//! ---------------
//! `-Druntime=true` builds the same artifact and installs it exactly as
//! `-Druntime=false` does, and changes how the facade *reaches* it. With the
//! flag off, `dep.module("inchi")` exposes `c` as the translation step's own
//! output and the artifact is linked into it: a call is a call, and
//! `inchi.runtime_loaded` is false. With the flag on, `c` is the generated
//! dispatch from `runtime/graph.zig`, the artifact is **not** linked into the
//! facade, and a caller has to name the provider once with
//! `inchi.load(.{ .path = … })` before anything else works.
//!
//! The two flags are orthogonal and neither one changes the other: `-Dlinkage`
//! decides the artifact kind, `-Druntime` decides the dispatch. A static
//! archive and a shared object are both addressable by the platform loader, so
//! `-Dlinkage=static -Druntime=true` and `-Dlinkage=dynamic -Druntime=true` are
//! both real configurations and both are built by this file.
//!
//! What this file does for the flag is exactly three things:
//!   * `-Druntime` is read once, here, and threaded into every graph this
//!     package configures — the package's own, each `check` cell, and the
//!!     nested `consumer/` build. No configuration quietly keeps the linked
//!     dispatch while the flag says otherwise.
//!   * In the bundled arm, `c` becomes
//!     `graph.createModule(b, translate_c, target, optimize)` instead of
//!     `translate_c.createModule()`, and `module.linkLibrary(artifact.?)` is
//!     skipped. Linking the artifact as well would let the linker resolve the
//!     symbols before `load` ever ran, which is the one thing this route is
//!     for.
//!   * In the linked arm, `rt` is bound to `graph.createCoreModule(b, target,
//!     optimize)` — one core instance, created here. The facade names
//!     `LoadSource` and `LoadError` in both configurations, so the linked one
//!     needs the core module for those two types. A runtime build must *not*
//!     import it separately: `createModule` already owns that instance and the
//!     dispatch re-exports the two types from it, and a second instance would
//!     be a second set of types (`runtime/graph.zig:111-114`).
//!
//! `-fsys=inchi` and `-Druntime=true` are refused together, with a message
//! saying why, rather than one quietly winning: that mode's contract is to link
//! an installed libinchi, and a configuration that resolves its symbols at run
//! time does not link one.
//!
//! `runtime/` is listed whole in `build.zig.zon` `.paths`: `graph.zig` is
//! `@import`ed by this file at configure time, and the generated dispatch is
//! built from the other files in it. A fetched package without them cannot
//! configure.
//!
//! Options, as the build runner spells them:
//!   -Druntime=true|false   resolve libinchi's symbols through the platform
//!                         loader instead of linking the artifact (default
//!                         `false`, which is the ordinary linked build)
//!   -Dtarget=<triple>     build for one target; `check` then analyses that one
//!                         target instead of the six-target matrix
//!   -Doptimize=<mode>    Debug, ReleaseSafe, ReleaseFast or ReleaseSmall
//!   -fsys=inchi           link an installed libinchi instead of building the
//!                         bundled core; `-fno-sys=inchi` forces the bundled one.
//!                         This is `b.systemIntegrationOption`, which the build
//!                         runner feeds from `-fsys=`/`-fno-sys=`; it is not a
//!                         `-D` option and `-Dsystem=true` would be an unknown
//!                         option rather than a mode.
//!
//!   -Dlinkage=static|dynamic
//!                         which artifact to build. The default is `static`,
//!                         which is what this graph built before the option
//!                         existed; a shared build additionally takes
//!                         upstream's export list, its PIC flags and its
//!                         `INCHI_API` export macros. `static` names a static
//!                         library artifact, not a promise that a program
//!                         linking it is wholly static.
//!
//! Steps: the default install step, `test`, `smoke`, `check`, `consumer`, and
//! `runtime-test`, which exists only under `-Druntime=true`.

const std = @import("std");

const manifest = @import("build.zig.zon");

/// The runtime route's build half. It is `@import`ed here, at configure time,
/// rather than only named in a comment: `-Druntime=true` is honoured by calling
/// `createModule` and `createCoreModule` on this file, so the option cannot be
/// accepted without the module that implements it, and a change to either
/// signature becomes a compile error in this graph rather than a surprise at
/// build time.
const graph = @import("runtime/graph.zig");

/// The upstream release this fork carries. Mirrors UPSTREAM.md; `build()`
/// refuses to configure when `build.zig.zon` drifts away from it.
const upstream = struct {
    const canonical_url = "https://github.com/IUPAC-InChI/InChI.git";
    const tag = "v1.07.5";
    const commit = "11a87982bb518f57ac013f0b258c283655e1ea1d";
    const version: std.SemanticVersion = .{ .major = 1, .minor = 7, .patch = 5 };
    /// `INCHI_BASE/src/bcf_s.h:52` reads `#define CURRENT_VER "1.07.5"`. That
    /// string is the software version; `INCHI_BASE/src/mode.h:258` separately
    /// defines `INCHI_VERSION "1"`, which is the InChI *standard* version and
    /// must not be reported as the software version.
    const current_ver = "1.07.5";
};

/// The three source directories upstream's own CMake target names. They are
/// also the include path, because sources in one directory include headers from
/// the others by relative path (`inchi_dll_a.h` includes
/// `../../../INCHI_BASE/src/ichicant.h`).
const base_src = "INCHI-1-SRC/INCHI_BASE/src";
const api_src = "INCHI-1-SRC/INCHI_API/libinchi/src";
const ixa_src = api_src ++ "/ixa";

/// `target_sources(libinchi PRIVATE ...)` entries with no directory prefix,
/// i.e. the files in the libinchi `src` directory itself.
const api_sources = [_][]const u8{
    "ichilnct.c",
    "inchi_dll.c",
    "inchi_dll_a.c",
    "inchi_dll_a2.c",
    "inchi_dll_b.c",
    "inchi_dll_main.c",
};

/// `${P_IXA}` entries of the same block.
const ixa_sources = [_][]const u8{
    "ixa_builder.c",
    "ixa_inchikey_builder.c",
    "ixa_mol.c",
    "ixa_read_inchi.c",
    "ixa_read_mol.c",
    "ixa_status.c",
};

/// `${P_BASE}` entries with the `.c` suffix, in the order the CMake block lists
/// them. The headers in that block are not translation units; they are reached
/// by `#include`, and the two public ones are installed.
const base_sources = [_][]const u8{
    "bcf_s.c",
    "ichi_bns.c",
    "ichi_io.c",
    "ichican2.c",
    "ichicano.c",
    "ichicans.c",
    "ichierr.c",
    "ichiisot.c",
    "ichimak2.c",
    "ichimake.c",
    "ichimap1.c",
    "ichimap2.c",
    "ichimap4.c",
    "ichinorm.c",
    "ichiparm.c",
    "ichiprt1.c",
    "ichiprt2.c",
    "ichiprt3.c",
    "ichiqueu.c",
    "ichiread.c",
    "ichiring.c",
    "ichirvr1.c",
    "ichirvr2.c",
    "ichirvr3.c",
    "ichirvr4.c",
    "ichirvr5.c",
    "ichirvr6.c",
    "ichirvr7.c",
    "ichisort.c",
    "ichister.c",
    "ichitaut.c",
    "ikey_base26.c",
    "ikey_dll.c",
    "inchi_gui.c",
    "mol_fmt1.c",
    "mol_fmt2.c",
    "mol_fmt3.c",
    "mol_fmt4.c",
    "mol2atom.c",
    "permutation_util.c",
    "readinch.c",
    "runichi.c",
    "runichi2.c",
    "runichi3.c",
    "runichi4.c",
    "sha2.c",
    "strutil.c",
    "util.c",
};

/// Flags every C translation unit is compiled with.
///
/// `-std=c11` is upstream's own language level:
/// `target_compile_features(libinchi_compiler_flags INTERFACE c_std_11)`
/// (src/CMakeLists.txt:6) and `C_OPTIONS = -std=c11 ...` in
/// `libinchi/gcc/makefile:123`. It is pinned rather than left to the
/// compiler's default so that an upstream source change cannot become a
/// build break through a default bump.
///
/// `-fno-strict-aliasing` is upstream's, in both the CMake interface flags and
/// that makefile, and it is kept here for the reason upstream keeps it. The
/// core compiles stb_sprintf 1.10 (`INCHI_BASE/src/stb_sprintf.h`, included by
/// `bcf_s.c:52`, `ichimak2.c:49` and `mol_fmt3.c:56`), whose formatter reads
/// its arguments with `va_arg` as `stbsp__uint32` and as pointers of several
/// different types, and the InChIKey code carries SHA-256 digests in
/// `unsigned char` buffers (`ikey_dll.c:130-135`). Those accesses are exactly
/// the ones strict aliasing permits a compiler to reorder or discard, and the
/// symptom is a wrong InChI string with no diagnostic anywhere.
///
/// Upstream also passes `-O1` and `-Wno-all` to its shared library. The
/// optimisation level here is the build's own `-Doptimize` mode rather than a
/// hard-coded `-O1`, and warnings stay enabled so that a real defect in a
/// future re-sync is visible instead of silenced.
const static_c_flags = [_][]const u8{
    "-std=c11",
    "-fno-strict-aliasing",
};

/// The same flags plus the position-independent code flag, for a shared build
/// on every target that is not Windows.
///
/// Upstream's own shared-library compile line is `$(LINUX_FPIC) ...`, with
/// `LINUX_FPIC = -fPIC` guarded by `ifneq ($(OS_ID),0)` — that is, defined for
/// everything except Windows (`libinchi/gcc/makefile:56-71,127-131`). CMake
/// reaches the same property by setting `POSITION_INDEPENDENT_CODE` through
/// the `fPIC` compile *definition* it lists
/// (`target_compile_definitions(libinchi PRIVATE fPIC ...)`,
/// src/CMakeLists.txt:154-158), which is a no-op for these sources.
///
/// This passes the compiler flag rather than the inert macro, on the same
/// non-Windows condition upstream applies it on. On a Windows target the flag
/// has no meaning for a COFF image, and upstream does not pass it there.
const shared_c_flags = [_][]const u8{
    "-std=c11",
    "-fno-strict-aliasing",
    "-fPIC",
};

/// The macros upstream's own library build defines
/// (`target_compile_definitions(libinchi PRIVATE ... COMPILE_ANSI_ONLY
/// TARGET_API_LIB)`, src/CMakeLists.txt:154-158, and `-DTARGET_API_LIB
/// -DCOMPILE_ANSI_ONLY` at libinchi/gcc/makefile:129).
///
/// They select the API library build of InChI rather than the stand-alone
/// executable or the wInChI library build, and they decide which declarations
/// the exported headers expand to. They belong on the *translation* line as
/// well as the compile line, so the declarations Zig sees are the declarations
/// the C was compiled under.
const core_macros = [_][2][]const u8{
    .{ "TARGET_API_LIB", "1" },
    .{ "COMPILE_ANSI_ONLY", "1" },
};

/// The macros that turn the API library's own definitions into exported ones on
/// a Windows DLL build: `_USRDLL` is what upstream's own DLL project defines
/// (`INCHI_API/libinchi/vc14/libinchi.vcxproj:108`, `:143`, `:176`, `:210`:
/// `_WINDOWS;_MBCS;_USRDLL;BUILD_LINK_AS_DLL;TARGET_API_LIB=1`), and
/// `BUILD_LINK_AS_DLL` is what the MinGW makefile passes
/// (`libinchi/gcc/makefile:133`).
///
/// Together they are read at `INCHI_BASE/src/inchi_api.h:691-709`, which is the
/// only place `INCHI_API`, `EXPIMP_TEMPLATE` and `INCHI_DECL` come from, and
/// which selects
/// `__declspec(dllexport)` for the library and `__declspec(dllimport)` for a
/// caller. Both arms of that `if` also require `_WIN32` *and* `_MSC_VER`.
///
/// That last condition is why these two are defined for an MSVC ABI only, and
/// not on every Windows target. A MinGW build is not an MSVC build: the whole
/// block is skipped there, `INCHI_API` expands to nothing, and the DLL's
/// symbols are exported by the auto-export the COFF/MinGW linker already does.
/// Defining `BUILD_LINK_AS_DLL` on such a target without `_USRDLL` would, if
/// `_MSC_VER` were ever defined for it, turn every definition in the core into
/// a `dllimport` declaration — so it is not defined there at all, which is
/// upstream's own observable MinGW configuration.
const dll_export_macros = [_][2][]const u8{
    .{ "BUILD_LINK_AS_DLL", "1" },
    .{ "_USRDLL", "1" },
};

/// The same pair with only its first half, which is what a *caller* of that DLL
/// needs: `inchi_api.h:698-702` gives `__declspec(dllimport)` when
/// `BUILD_LINK_AS_DLL` is defined and `_USRDLL` is not. Named on its own rather
/// than sliced out of `dll_export_macros`, so which half a given configuration
/// takes is stated where it is used and does not depend on the order of a
/// table.
const dll_import_macros = [_][2][]const u8{
    .{ "BUILD_LINK_AS_DLL", "1" },
};

/// Upstream's export list for the shared library, applied as the linker's
/// version script on a shared build.
///
/// This is upstream's own file, used as upstream uses it: CMake passes
/// `--version-script=${P_LIBINCHI_MAP}/libinchi.map` for `UNIX AND NOT APPLE`
/// (src/CMakeLists.txt:168-172) and the MinGW makefile passes
/// `--version-script=libinchi.map` wherever it is not macOS
/// (`libinchi/gcc/makefile:62-65,263-268`). The makefile's comment says what it
/// is for: "inchi.map restricts set of exported from .so functions to those
/// which belong to InChI API". Without it a shared libinchi would publish every
/// internal InChI symbol — the core has hundreds of external-linkage functions
/// that are not API — into the global symbol namespace of every process that
/// loads it, and two copies of InChI in one process would interpose on each
/// other. Nothing is invented here: the file, its global list and its `local`
/// arm are upstream's bytes.
const library_map_path = "INCHI-1-SRC/INCHI_API/libinchi/gcc/libinchi.map";

/// The targets on which libm is a separate library and the ELF version script
/// applies. One predicate, two facts, because they are the same set of
/// targets: `libm` is separate on the glibc and BSD targets and is part of
/// libc on macOS, Windows and wasi, and `libinchi.map` is what upstream passes
/// for `UNIX AND NOT APPLE` (src/CMakeLists.txt:168-172) and for everything
/// that is not macOS (`libinchi/gcc/makefile:62-65`). Every caller below wants
/// one of the two and none of them wants only one, so a target outside this
/// list gets neither a `-lm` nor a version script rather than getting one by
/// accident.
const elf_unix_tags = [_]std.Target.Os.Tag{
    .linux,
    .freebsd,
    .netbsd,
    .openbsd,
    .dragonfly,
    .illumos,
};

fn isElfUnix(target: std.Build.ResolvedTarget) bool {
    for (elf_unix_tags) |tag| {
        if (target.result.os.tag == tag) return true;
    }
    return false;
}

/// True for a Windows target whose ABI is an MSVC one.
///
/// `@tagName` plus a prefix test rather than a comparison against one enum
/// member: the MSVC ABI has more than one spelling over Zig versions, and both
/// mean the same thing here, because what the export macros depend on is only
/// that `inchi_api.h:691` takes its `_MSC_VER` branch. Comparing against a
/// single literal would quietly stop applying the macros if the spelling
/// changed.
fn isWindowsMsvc(target: std.Build.ResolvedTarget) bool {
    return target.result.os.tag == .windows and
        std.mem.startsWith(u8, @tagName(target.result.abi), "msvc");
}

/// Targets `check` analyses. Each one compiles the whole C core, `tests.zig`
/// and `smoke.zig`; none of them is run.
const check_targets = [_][]const u8{
    "x86_64-linux-gnu",
    "aarch64-linux-gnu",
    "aarch64-macos-none",
    "x86_64-windows-gnu",
    "riscv64-linux-gnu",
    "wasm32-wasi",
};

const facade_source = "zig/root.zig";
const test_source = "tests.zig";
const smoke_source = "smoke.zig";
const consumer_dir = "consumer";

/// The runtime route's own roots. Both are built by the step that has the
/// configuration they need, and both are *not* built in the configuration that
/// cannot use them: `load_tests.zig` `@compileError`s itself in a linked build
/// (there is no loader to test and `load` deliberately stops the program), and
/// `misuse.zig` is built in both because what it demonstrates is exactly the
/// difference between them — its own header names all three modes, including
/// the one that proves a linked build has nothing to load.
const runtime_test_source = "runtime/load_tests.zig";
const misuse_source = "runtime/misuse.zig";

/// Everything the package installs under `share/doc/inchi/`, as
/// `source -> installed name` pairs.
///
/// The list is unconditional and the files are all present in this tree, so an
/// install never quietly shrinks: a missing one is a build failure naming the
/// file, not a smaller output.
///
/// `LICENSE` is upstream's own MIT text, shipped verbatim and listed in
/// `UPSTREAM.sha256`; the notice asks that it travel with the sources, so it is
/// installed rather than left behind in the repository.
/// `INCHI-1-SRC/INCHI_API/tbb/LICENSE` is upstream's full Apache-2.0 text, which
/// is the licence of the retained, uncompiled TBB proxy header and has to
/// travel with it. `NOTICE.md` and `FORK-LICENSE.md` are this package's own
/// licence records and `UPSTREAM.md` its provenance record.
///
/// Both READMEs are installed because the fork's grant makes attribution
/// travelling a condition, and upstream's README is the attribution. Which of
/// the two is the fork's own README changes; that both are here does not.
const installed_doc_files = [_]struct { source: []const u8, installed: []const u8 }{
    .{ .source = "LICENSE", .installed = "LICENSE" },
    .{ .source = "NOTICE.md", .installed = "NOTICE.md" },
    .{ .source = "FORK-LICENSE.md", .installed = "FORK-LICENSE.md" },
    .{ .source = "UPSTREAM.md", .installed = "UPSTREAM.md" },
    .{ .source = "README.md", .installed = "README.md" },
    .{ .source = "README.upstream.md", .installed = "README.upstream.md" },
    // Upstream's Apache-2.0 text, for the retained uncompiled proxy header it
    // covers. It is a different licence from the MIT text above and is kept
    // under its own name so the two are never read as one.
    .{ .source = "INCHI-1-SRC/INCHI_API/tbb/LICENSE", .installed = "tbb/LICENSE" },
};

/// Every licence, notice and provenance record installed under
/// `share/licenses/inchi/`, as `source -> installed name` pairs.
///
/// `installed_doc_files` above carries the same material as documentation; this
/// is the same bytes at the place terms live. They are not merged into one
/// directory because both claims are real and a recipient who wants the manual
/// should not have to read a licence file to find it, nor a recipient who needs
/// the terms to have to know this package documents as well as grants.
///
/// `LICENSE` is upstream's own MIT text, verbatim. The second grant is
/// `INCHI-1-SRC/INCHI_API/tbb/LICENSE`, upstream's full Apache-2.0 text, which
/// governs the retained but uncompiled TBB proxy header and is a different
/// licence from the MIT one; it keeps its `tbb/` prefix so the two are never
/// read as one file. `README.upstream.md` is upstream's README byte for byte,
/// and this fork's grant makes attribution travelling a condition.
/// `NOTICE.md`, `FORK-LICENSE.md`, `UPSTREAM.md`, `FORK-NOTES.md` and
/// `UPSTREAM.sha256` are this fork's own records.
const licence_records = [_]struct { source: []const u8, installed: []const u8 }{
    .{ .source = "LICENSE", .installed = "LICENSE" },
    .{ .source = "NOTICE.md", .installed = "NOTICE.md" },
    .{ .source = "FORK-LICENSE.md", .installed = "FORK-LICENSE.md" },
    .{ .source = "UPSTREAM.md", .installed = "UPSTREAM.md" },
    .{ .source = "FORK-NOTES.md", .installed = "FORK-NOTES.md" },
    .{ .source = "UPSTREAM.sha256", .installed = "UPSTREAM.sha256" },
    .{ .source = "README.upstream.md", .installed = "README.upstream.md" },
    .{ .source = "INCHI-1-SRC/INCHI_API/tbb/LICENSE", .installed = "tbb/LICENSE" },
};

/// Everything a dependent needs: the Zig facade, with `c` bound to the
/// translated public header and the library already linked into it.
const InchiPackage = struct {
    module: *std.Build.Module,
    /// Null in `-fsys=inchi` mode, where the library comes from the system and
    /// this package installs nothing of its own.
    artifact: ?*std.Build.Step.Compile,
    /// The translation step `module`'s `c` was bound from. A second facade for
    /// the same target reads this one rather than translating the same header
    /// again, so both facades declare the same things.
    translate_c: *std.Build.Step.TranslateC,
    /// The loader core this facade was given its `rt` import from, or null in
    /// a `-Druntime=true` graph, which owns no facade of its own. One core per
    /// build, not one per facade: `LoadSource` and `LoadError` are named by all
    /// of them, and two cores would be two sets of those two types.
    rt_core: ?*std.Build.Module,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const linkage_option = b.option(
        std.builtin.LinkMode,
        "linkage",
        "Link the libinchi artifact statically (default) or dynamically",
    );
    const linkage = linkage_option orelse @as(std.builtin.LinkMode, .static);
    // Which kind of *installed* library `-fsys=inchi` binds to, kept apart from
    // `linkage` because that one describes what this graph builds, and in
    // `-fsys=` mode this graph builds nothing. Only an explicit `-Dlinkage`
    // says which installed flavour is meant; the default is `.dynamic`,
    // because a distribution's `-linchi` is its shared library, and because
    // that is the case whose declarations need `__declspec(dllimport)`.
    const system_linkage = linkage_option orelse .dynamic;
    const use_system = b.systemIntegrationOption("inchi", .{});

    // Runtime loading: the artifact is built and installed exactly as it is
    // without the flag, and the facade reaches it through the platform loader
    // instead of through a link. Orthogonal to `linkage` — a static archive and
    // a shared object are both addressable by `dlopen`, and neither flag
    // changes what the other decides.
    const runtime = b.option(
        bool,
        "runtime",
        "Resolve libinchi's symbols at run time through the platform loader " ++
            "instead of linking the artifact into the facade (default false)",
    ) orelse false;
    // Refused rather than resolved in favour of one of them. `-fsys=inchi`
    // means "bind to an installed libinchi", and a configuration that resolves
    // its symbols when the caller says so does not bind to one; silently
    // dropping either flag would build something the caller did not ask for
    // under a name that says they did.
    if (runtime and use_system) {
        @panic("-Druntime=true and -fsys=inchi cannot be combined: the system " ++
            "mode's contract is to link an installed libinchi, and runtime " ++
            "loading resolves the symbols itself at run time instead. " ++
            "Build one or the other: -Druntime=true for this package's own " ++
            "artifact, or -fsys=inchi for an installed one.");
    }

    const package_version = std.SemanticVersion.parse(manifest.version) catch {
        @panic("build.zig.zon: .version is not a semantic version");
    };
    if (package_version.order(upstream.version) != .eq) {
        @panic(b.fmt(
            "build.zig.zon .version {f} no longer matches the pinned upstream release {s} ({s}, CURRENT_VER {s}) in UPSTREAM.md",
            .{ package_version, upstream.tag, upstream.commit, upstream.current_ver },
        ));
    }

    const inchi = addInchi(b, .{
        .target = target,
        .optimize = optimize,
        .linkage = linkage,
        .runtime = runtime,
        .system_linkage = system_linkage,
        .use_system = use_system,
        .register_module = true,
    });

    if (inchi.artifact) |artifact| {
        b.installArtifact(artifact);
        // The two public headers, installed under their upstream names in one
        // directory. `inchi_api.h` ends with `#include "ixa.h"`, so a C
        // consumer that includes <inchi_api.h> gets the whole IXA surface too.
        // Installing them also puts them on the include path of anything that
        // links this artifact.
        //
        // Two files is the complete public header closure, not a subset:
        // `inchi_api.h` includes nothing but `ixa.h` at its end
        // (inchi_api.h:1413), `ixa.h` includes no header at all, and neither
        // names a libc typedef it did not include, so a consumer needs exactly
        // these two and nothing from INCHI_BASE/src.
        artifact.installHeader(b.path(base_src ++ "/inchi_api.h"), "inchi_api.h");
        artifact.installHeader(b.path(base_src ++ "/ixa.h"), "ixa.h");

        // The link metadata for the tree just installed. Upstream ships no
        // pkg-config file and no install rules at all (there is no `install(`
        // in either CMakeLists.txt), so this file is the only place that
        // states the library name, the include directory and the libm
        // dependency of what this build produced. It locates itself through
        // `${pcfiledir}` rather than a configure-time `--prefix`, so it stays
        // correct when the build is installed under some other prefix, and it
        // says nothing about static executables: `Libs` names the library, and
        // nothing here promises a wholly static link.
        const install_pc = b.addInstallFileWithDir(addPkgConfig(b, target, linkage), .lib, "pkgconfig/inchi.pc");
        b.getInstallStep().dependOn(&install_pc.step);

        // The carried licence and documentation material, in the one place a
        // recipient looks for it.
        for (installed_doc_files) |doc| {
            b.installFile(doc.source, b.fmt("share/doc/inchi/{s}", .{doc.installed}));
        }

        // The same material again, at the place a recipient looks for terms
        // rather than for documentation. `share/licenses/inchi/` is where the
        // rest of this workspace installs a library's grants, and a library
        // installed without them under that name is a source drop wearing a
        // prefix.
        installLicenceRecords(b);
    }

    // ---- The install-tree flavour of the facade --------------------------
    //
    // The published `inchi` module is the build-cache flavour, because that is
    // what every program that imports it needs and that includes the
    // dependents: `linkLibrary` records the directory the shared object was
    // emitted into, and every compilation whose graph imports the module --
    // a dependent's executable among them -- gets an `-rpath` for it. The test
    // binary and `smoke` run out of the build cache for the same reason.
    //
    // Only `misuse` is installed from this package, and it is therefore the one
    // program that cannot use that entry: it wants the install tree's
    // `$ORIGIN/../lib` and nothing else. It is built from a second, *private*
    // facade for that purpose.
    //
    // `needsBothLoaders` is what decides whether that is a second graph at all:
    // under `-Dlinkage=static`, under `-fsys=inchi` and under `-Druntime=true`
    // both flavours produce the same file, and the facade registered above is
    // used as it stands.
    const install_facade = if (needsBothLoaders(if (runtime) null else inchi.artifact, target))
        addInchi(b, .{
            .target = target,
            .optimize = optimize,
            .linkage = linkage,
            .runtime = runtime,
            .system_linkage = system_linkage,
            .use_system = use_system,
            .register_module = false,
            .loader = .install_tree,
            // The same library, translation step and loader core as the graph
            // above; only the search path differs.
            .shared = &inchi,
        }).module
    else
        inchi.module;

    // ---- Tests ------------------------------------------------------------
    //
    // `addTest` plus `addRunArtifact`: the test binary is built and executed
    // here, not merely compiled. Compiling the C core, the facade and the test
    // binary is also what makes `test` a check of the whole binding, because
    // Zig only analyses a function body something calls.
    const test_step = b.step("test", "Run the native behavioural tests");
    const unit_tests = b.addTest(.{
        .name = "inchi-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path(test_source),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{.{ .name = "inchi", .module = inchi.module }},
        }),
    });
    test_step.dependOn(&b.addRunArtifact(unit_tests).step);

    // ---- Smoke ------------------------------------------------------------
    //
    // The default step installs the archive and its headers and compiles this
    // program; `smoke` runs it. It is a proof, not a deliverable, so it is
    // built by `zig build` and never installed, so it runs against the
    // published build-cache flavour of the facade for the reason above.
    const smoke_exe = addSmokeExecutable(b, "inchi-smoke", target, optimize, inchi.module);
    b.getInstallStep().dependOn(&smoke_exe.step);

    const smoke_step = b.step("smoke", "Run the deterministic smoke program");
    const run_smoke = b.addRunArtifact(smoke_exe);
    smoke_step.dependOn(&run_smoke.step);
    if (b.args) |args| run_smoke.addArgs(args);

    // ---- Runtime route ----------------------------------------------------
    //
    // Two roots, both from `runtime/`, and both built here rather than left
    // unreferenced:
    //
    //   * `misuse` is built in *both* configurations and installed under the
    //     name its own header documents, because what it demonstrates is
    //     precisely the difference between them: `pre-load` must stop,
    //     `after-load <path>` must produce PubChem's identifier for water once
    //     a real provider is loaded, and `linked-load` must stop because a
    //     linked build has nothing to load. It is a program, not a test, so
    //     there is no step that runs it and asserts an exit status here — two
    //     of its three modes are *supposed* to stop, and which ones depend on
    //     the configuration, so the caller runs the three commands its header
    //     lists. What the build owes is that `zig build` produces it. It is
    //     also the one installed program here, so it is the one built from the
    //     install-tree flavour of the facade.
    //   * `runtime-test` is the loader's own behavioural test root, and it
    //     exists only under `-Druntime=true`. It `@compileError`s itself in a
    //     linked build, because there is no loader there to test. It needs a
    //     real provider named in `INCHI_TEST_PROVIDER` and a loadable
    //     non-library in `INCHI_TEST_ALIEN`, and it does not skip anything when
    //     either is absent — that is its rule, and it is a good one: a
    //     runtime-loading test that quietly had nothing to say would be worth
    //     less than no test.
    const misuse_exe = b.addExecutable(.{
        .name = "misuse",
        .root_module = b.createModule(.{
            .root_source_file = b.path(misuse_source),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{.{ .name = "inchi", .module = install_facade }},
        }),
    });
    b.installArtifact(misuse_exe);

    if (runtime) {
        const runtime_tests = b.addTest(.{
            .name = "inchi-runtime-tests",
            .root_module = b.createModule(.{
                .root_source_file = b.path(runtime_test_source),
                .target = target,
                .optimize = optimize,
                .link_libc = true,
                .imports = &.{.{ .name = "inchi", .module = inchi.module }},
            }),
        });
        const runtime_test_step = b.step(
            "runtime-test",
            "Run the loader's behavioural tests against a real provider",
        );
        runtime_test_step.dependOn(&b.addRunArtifact(runtime_tests).step);
    }

    // ---- Cross target analysis --------------------------------------------
    //
    // `check` never executes a target binary. It compiles the full C core, the
    // facade, `tests.zig` and `smoke.zig` for every listed target, so a foreign
    // target is analysed on this host. `tests.zig` and `smoke.zig` call every
    // public facade entry point, which is what makes this a check of the facade
    // rather than of an unreferenced archive.
    //
    // A target is never dropped. If a target cannot be built, that is a
    // descriptive failure of this step naming the file and the reason, not a
    // silent skip and not a substitute implementation.
    //
    // The requested linkage is what every cell is built with; nothing here
    // quietly substitutes the default. A cell that cannot take that linkage is
    // a cell that reports it, and there is a real one: `-Dlinkage=dynamic` on
    // `wasm32-wasi` has no answer, because WASI has no shared object for a C
    // library to be built into and the linker refuses the request. That is a
    // platform boundary, stated here rather than worked around by dropping the
    // target or by building something else in its place. The published
    // 53-platform `cross-test` matrix therefore names `-Dlinkage=static`
    // explicitly, so its cells are unambiguous rather than dependent on which
    // linkage happens to be the default.
    //
    // `-Druntime` is threaded the same way. It is not narrowed here either: a
    // cell that cannot produce a dispatch reports itself. `wasm32-wasi` is the
    // one this graph already knows about, because the loader's Unix backend
    // calls `dlopen` and WASI has no dynamic loader; that is the loader's
    // boundary to state, not this step's to hide.
    const check_step = b.step(
        "check",
        "Compile the C core, the facade, the tests and the smoke program for every cross target without running them",
    );
    if (!target.query.isNative()) {
        addTargetCheck(b, check_step, "selected", target.query, linkage, optimize, runtime);
    } else {
        for (check_targets) |triple| {
            addTargetCheck(b, check_step, triple, parseTriple(b, triple), linkage, optimize, runtime);
        }
    }

    // ---- Consumer package --------------------------------------------------
    //
    // consumer/ is a separate package with its own manifest, depending on this
    // one by path and importing `dep.module("inchi")`. It cannot be a dependency
    // of this manifest: that would close a cycle, because its manifest points
    // back here by path. It is therefore built as its own `zig build`, with the
    // target, the optimisation mode, the linkage, `-Druntime` and the
    // system-integration choice forwarded on the command line, and with the
    // build runner's executor switches, the workspace's own `-j8`,
    // `--summary all` and cache directories forwarded alongside them, so the
    // nested `run` executes the consumer under the same executor
    // `hostCanExecute` decided with and at the same width.
    // Each forwarded option is one the nested graph reads from
    // its own options, and a consumer proved against one configuration while
    // the outer graph built another would prove nothing about what was
    // actually produced. A consumer that cannot reach the dispatch at all
    // because it was not asked for one is a consumer that proved the wrong
    // thing, which is why `-Druntime` is forwarded rather than assumed.
    // The caller's trailing arguments are forwarded too, behind `--`: the
    // nested package hands its own `b.args` to the program it runs, so a
    // `--provider <path>` typed here is what reaches the consumer check.
    const consumer_step = b.step(
        "consumer",
        "Build the consumer/ package against the exported module, and run it when this host can execute the selected target",
    );
    consumer_step.dependOn(&runConsumer(b, target, optimize, use_system, linkage, runtime).step);
}

/// Compiles, but never runs, everything that makes up the public surface for
/// one target.
fn addTargetCheck(
    b: *std.Build,
    step: *std.Build.Step,
    label: []const u8,
    query: std.Target.Query,
    linkage: std.builtin.LinkMode,
    optimize: std.builtin.OptimizeMode,
    /// Threaded, not defaulted: a `check` cell builds what was asked for. When
    /// this is `true` each cell generates its own dispatch from its own
    /// translation output, which is the only way the check can mean anything
    /// for a cross target.
    runtime: bool,
) void {
    const cross_target = b.resolveTargetQuery(query);
    const cross = addInchi(b, .{
        .target = cross_target,
        .optimize = optimize,
        .linkage = linkage,
        .runtime = runtime,
        // A system library is by definition the host's, so the cross matrix
        // always builds the bundled sources and never reads `system_linkage`.
        .use_system = false,
        .register_module = false,
    });

    const cross_tests = b.addTest(.{
        .name = b.fmt("inchi-tests-{s}", .{label}),
        .root_module = b.createModule(.{
            .root_source_file = b.path(test_source),
            .target = cross_target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{.{ .name = "inchi", .module = cross.module }},
        }),
    });
    step.dependOn(&cross_tests.step);

    step.dependOn(&addSmokeExecutable(
        b,
        b.fmt("inchi-smoke-{s}", .{label}),
        cross_target,
        optimize,
        cross.module,
    ).step);
}

fn addSmokeExecutable(
    b: *std.Build,
    name: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    inchi_module: *std.Build.Module,
) *std.Build.Step.Compile {
    return b.addExecutable(.{
        .name = name,
        .root_module = b.createModule(.{
            .root_source_file = b.path(smoke_source),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{.{ .name = "inchi", .module = inchi_module }},
        }),
    });
}

const InchiOptions = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    /// What this graph builds. The static library is the default and is what
    /// it built before `-Dlinkage` existed.
    linkage: std.builtin.LinkMode,
    /// `-Druntime=true`: the facade reaches the artifact through the platform
    /// loader instead of through a link. The artifact is built and installed
    /// either way; this decides the dispatch, not the deliverable. False is the
    /// ordinary linked build and the default.
    runtime: bool = false,
    /// Which kind of installed library `-fsys=inchi` binds to. It is read only
    /// in that mode, and it is kept out of `linkage` because in that mode this
    /// graph builds no artifact at all: what it builds is decided by the other
    /// field, and what it binds to is decided by this one.
    system_linkage: std.builtin.LinkMode = .dynamic,
    /// `-fsys=inchi`: bind to an installed libinchi and translate its headers
    /// instead of building this repository's copy.
    use_system: bool,
    /// Register the module as `dep.module("inchi")` for dependents. Only the
    /// package's own graph may do that: modules are registered by name against
    /// the whole build, so registering "inchi" once per cross target would
    /// leave only the last one reachable and silently stop checking the rest.
    register_module: bool,
    /// Where a program built from this graph's facade must find the library it
    /// links. See `Loader`. The default is the published facade's flavour, and
    /// a graph that publishes its module does not override it; only the
    /// private facade an installed program is built from passes `.install_tree`.
    loader: Loader = .build_cache,
    /// Reuse another graph's library, translation step and loader core instead
    /// of building this graph's own.
    ///
    /// A program that is both installed and run is compiled twice, once for
    /// each `Loader`, and the two compilations must be of one library rather
    /// than of two builds of the same sources. Only `build` sets it, and only
    /// when `needsBothLoaders` says the two flavours really do differ.
    shared: ?*const InchiPackage = null,
};

fn addInchi(b: *std.Build, options: InchiOptions) InchiPackage {
    // Whether the *installed* library's declarations are import declarations.
    // Only `-fsys=inchi` mode can answer that, and only from what the caller
    // said: `-Dlinkage=static` says the install is an archive, an omitted
    // `-Dlinkage` means the distribution's shared library. It is true only on
    // an MSVC ABI, because that is the only configuration in which
    // `inchi_api.h:691` reads `BUILD_LINK_AS_DLL` and reaches
    // `__declspec(dllimport)`.
    const system_import_declarations = options.use_system and
        options.system_linkage == .dynamic and
        isWindowsMsvc(options.target);

    // In bundled mode the declaration macros are `translate.h`'s, and they are
    // the same for both linkages on purpose. The Zig facade links this graph's
    // own artifact directly, static or shared, so its declarations must be the
    // plain ones (`inchi_api.h:704-709`: "create a statically linked InChI
    // library or link to an executable"). `__declspec(dllimport)` there would
    // add an import-library constraint that a direct link does not have, and
    // `__declspec(dllexport)` there would export InChI from every program that
    // uses it. A shared artifact on Windows gets its export decoration from the
    // *core's* compile line instead, which is where the definitions are.

    // A second facade for the same target reuses this graph's library,
    // translation step and loader core rather than building its own: the two
    // flavours of a program differ in one `-rpath`, and a program that is the
    // same program on both sides of that is the whole point. Only `build` sets
    // `shared`, and only when `needsBothLoaders` says the flavours differ,
    // which it answers false in `-fsys` mode -- so the bundled arm is the only
    // one that ever runs a second time.
    const reused = options.shared;
    const translate_c = if (reused) |previous| previous.translate_c else translate: {
        const root_source_file: std.Build.LazyPath =
            if (options.use_system)
                // The system mode translates the header that is actually installed
                // next to the library it links, so no in-tree include path is added:
                // an in-tree header is found first and would silently bind this
                // repository's 1.07.5 declarations to whatever libinchi is
                // installed.
                systemTranslateHeader(b, system_import_declarations)
            else
                b.path("translate.h");
        const translate_include_paths: []const std.Build.LazyPath =
            if (options.use_system) &.{} else &.{b.path(base_src)};

        const translate_c = b.addTranslateC(.{
            .root_source_file = root_source_file,
            .target = options.target,
            .optimize = options.optimize,
            .link_libc = true,
        });
        for (translate_include_paths) |path| translate_c.addIncludePath(path);
        // The `-I` the generated wrapper's `#include <inchi_api.h>` needs, from
        // the installed tree's own `inchi.pc` rather than from the compiler's
        // default include path. The same call `gmp/build.zig:819` makes, with the
        // options the facade passes below, so the header the declarations came
        // from and the `-linchi` they bind to are one answer.
        if (options.use_system) {
            translate_c.linkSystemLibrary("inchi", .{
                .use_pkg_config = .yes,
                .preferred_link_mode = options.system_linkage,
            });
        }
        break :translate translate_c;
    };

    // The module carries the target and optimise mode of the build that created
    // it, because `Module.linkSystemLibrary` calls `requireKnownTarget`.
    const module = if (options.register_module)
        b.addModule("inchi", .{
            .root_source_file = b.path(facade_source),
            .target = options.target,
            .optimize = options.optimize,
        })
    else
        b.createModule(.{
            .root_source_file = b.path(facade_source),
            .target = options.target,
            .optimize = options.optimize,
        });

    // The `c` import: the translation step's own output in a linked build, and
    // the generated dispatch in a runtime one. Both are built from the same
    // `translate_c`, so a runtime build describes the header this build
    // actually selected rather than another one, and both publish the same
    // namespace — the dispatch re-exports every type and constant from
    // `c_native` instead of restating them, so `c.inchi_Atom` is one nominal
    // type either way and nothing downstream needs a cast between them.
    //
    // `rt` is the other half, and it is deliberately asymmetric. The facade
    // names `LoadSource` and `LoadError` in both configurations
    // (`zig/root.zig:220,226`), so a *linked* build has to be given the loader
    // core to name them from — one instance, created here, costless because
    // nothing in that module is referenced until a configuration actually
    // instantiates the loader. A *runtime* build must not import it separately:
    // `createModule` already owns that one instance and the dispatch
    // re-exports the two types from it, so a second import would be a second
    // set of types and a consumer would be naming one while `load` expected
    // the other (`runtime/graph.zig:111-114`). The facade's `@import("rt")` is
    // never resolved in that configuration, because the only references to it
    // sit in the branch `runtime_loaded` eliminates at comptime.
    var rt_core: ?*std.Build.Module = null;
    if (options.runtime) {
        module.addImport("c", graph.createModule(b, translate_c, options.target, options.optimize));
    } else {
        module.addImport("c", translate_c.createModule());
        // One core per build, not one per facade. A second facade for this
        // target is given this instance rather than a second one, because the
        // `LoadSource` and `LoadError` the two facades publish must be one set
        // of types.
        rt_core = if (reused) |previous|
            previous.rt_core.?
        else
            graph.createCoreModule(b, options.target, options.optimize);
        module.addImport("rt", rt_core.?);
    }
    // The C core calls stdio, stdlib, string and math.
    module.link_libc = true;
    // `sqrt`, `pow`, `floor`, `ceil`, `atan2`, `trunc`, `round`, `fabs` and
    // `sin`/`cos` are called from the core (46 fabs, 23 sqrt, 20 floor, 16
    // atan2, 12 trunc, 9 pow, 8 round across INCHI_BASE/src). libm is a
    // separate library on the glibc and BSD targets and part of libc on macOS,
    // Windows and wasi. It is linked here, on the module a dependent imports,
    // rather than on the archive: a `linkSystemLibrary` on a static library
    // stays inside that library's own link line and never reaches the
    // executable that links the archive, which would leave every dependent to
    // discover the undefined `sqrt` on its own.
    if (isElfUnix(options.target)) {
        module.linkSystemLibrary("m", .{});
    }
    if (!options.use_system) {
        // A dependent that compiles its own C against this module needs the
        // same header set the core was compiled with.
        module.addIncludePath(b.path(base_src));
    }

    var artifact: ?*std.Build.Step.Compile = null;
    if (reused) |previous| {
        artifact = previous.artifact;
    } else if (options.use_system) {
        // `inchi` is the name the installed tree publishes: the libinchi CMake
        // target sets `PREFIX ""` (src/CMakeLists.txt:165) and produces
        // libinchi.so/.dylib/.dll, and the `inchi.pc` beside those files carries
        // `Libs: -L${libdir} -linchi`. Upstream ships no `.pc` of its own, but
        // that is not "there is nothing to ask"; `.yes` keeps the bare `-linchi`
        // as its fallback (`Step/Compile.zig:1140-1148`). Same options as above.
        module.linkSystemLibrary("inchi", .{
            .use_pkg_config = .yes,
            .preferred_link_mode = options.system_linkage,
        });
    } else {
        const core = b.createModule(.{
            .target = options.target,
            .optimize = options.optimize,
            .link_libc = true,
            // `.off` is defence in depth, not a workaround for anything here:
            // a null `sanitize_c` already means no `-fsanitize` flag
            // (Module.zig:246), and a Debug gate here means an unsanitised
            // Debug archive, which is what the C core's own wraparound and
            // narrowing arithmetic expects.
            .sanitize_c = .off,
        });
        for ([_][]const u8{ base_src, api_src, ixa_src }) |dir| core.addIncludePath(b.path(dir));
        for (core_macros) |macro| core.addCMacro(macro[0], macro[1]);
        // The export decoration, only where upstream's own header has a branch
        // for it: an MSVC-ABI Windows DLL build. `dll_export_macros` carries
        // `_USRDLL`, which is the half that makes `inchi_api.h` emit
        // `__declspec(dllexport)` on the definitions in this very library. Every
        // other target keeps the plain declarations, which is what upstream's
        // ELF version script and MinGW auto-export handle instead.
        if (options.linkage == .dynamic and isWindowsMsvc(options.target)) {
            for (dll_export_macros) |macro| core.addCMacro(macro[0], macro[1]);
        }

        // PIC for the shared artifact on the targets upstream compiles one on,
        // and the language level and aliasing flag for both.
        const c_flags: []const []const u8 = if (options.linkage == .dynamic and
            options.target.result.os.tag != .windows) &shared_c_flags else &static_c_flags;
        core.addCSourceFiles(.{ .root = b.path(api_src), .files = &api_sources, .flags = c_flags });
        core.addCSourceFiles(.{ .root = b.path(ixa_src), .files = &ixa_sources, .flags = c_flags });
        core.addCSourceFiles(.{ .root = b.path(base_src), .files = &base_sources, .flags = c_flags });

        artifact = b.addLibrary(.{
            .name = "inchi",
            .linkage = options.linkage,
            .version = upstream.version,
            .root_module = core,
        });
        // Upstream's own export list, as the version script, on the targets
        // upstream passes it on. Without it a shared libinchi would publish
        // every internal InChI symbol, not the API list upstream ships; the
        // static artifact is unaffected and does not take one.
        if (options.linkage == .dynamic and isElfUnix(options.target)) {
            artifact.?.setVersionScript(b.path(library_map_path));
        }

        // What upstream passes to this link that is deliberately not repeated
        // here, recorded so it is an omission on the record and not a silent
        // one: `-z relro`, which src/CMakeLists.txt:169 and
        // libinchi/gcc/makefile:64 add to stop an SELinux complaint that a
        // writable relocation segment produces. It is a hardening option for
        // the produced image; it decides nothing about which symbols exist,
        // which are exported, or what a caller must compile against, and
        // Zig's own linker invocation owns the link line this build hands it.
        // The other upstream shared-library flags are all either honoured here
        // or have no counterpart: `-Wl,-soname,libinchi.so.1.7.5` is what
        // `.version` produces, `-shared` is what `.linkage = .dynamic` means,
        // and `-O1`/`-Wno-all` are upstream's optimisation and warning choices,
        // not this build's.

    }

    // Binding the artifact to the facade module is what lets a dependent
    // use nothing but `dep.module("inchi")`: it needs no `dep.artifact`, no
    // -linchi of its own and no extra include path. It works the same for
    // either linkage, because this is a direct link of whatever was built.
    //
    // Under `-Druntime=true` it does not happen, and that omission is the
    // whole point of the configuration. `c` is the dispatch now, and the
    // dispatch has no reference to the artifact at all; linking it here
    // would let the linker resolve `GetINCHI` and its neighbours out of the
    // archive before `load` ever ran, so a program that never named a
    // provider would still work and the route would silently be a linked
    // one. The artifact above is still built and still installed — which
    // artifact a build produces and which dispatch a build uses are two
    // different questions, and `-Dlinkage` and `-Druntime` answer them
    // independently.
    //
    // The facade module is the one every program of this build imports,
    // and every module in a compilation's graph contributes its own runtime
    // search path, so the entry that lands on the artifact is `Loader`'s
    // decision and not this line's: `linkForLoader` says what each one is,
    // and the published module is the `build_cache` one because a dependent's
    // executable is built out of a build cache too. Only `bin/misuse` is built
    // from an `install_tree` facade, and it is built from a private one.
    // It is reached from outside the branch above so that a second facade,
    // which reuses the artifact instead of building it, is bound exactly like
    // the first.
    if (!options.runtime) {
        if (artifact) |lib| {
            linkForLoader(module, lib, options.target, options.loader);
        }
    }

    return .{
        .module = module,
        .artifact = artifact,
        .translate_c = translate_c,
        .rt_core = rt_core,
    };
}

/// The runtime search path an installed program needs so that its loader
/// finds the shared object this same prefix installed beside it.
///
/// `bin/misuse` and `lib/libinchi.so` are siblings under one prefix, so
/// `$ORIGIN/../lib` is the ELF spelling and `@loader_path/../lib` the Mach-O
/// one, and both name this install tree and no other.  COFF has neither:
/// `installArtifact` puts `libinchi.dll` and its import library into `bin/`
/// beside the program, which is where its loader looks first.  A target with
/// no dynamic loader has nothing to name either.
fn installedProgramRPath(target: std.Build.ResolvedTarget) ?[]const u8 {
    return switch (target.result.os.tag) {
        .windows, .wasi, .uefi => null,
        else => if (target.result.os.tag.isDarwin()) "@loader_path/../lib" else "$ORIGIN/../lib",
    };
}

/// Where a program built against this SDK's shared library must find it.
///
/// The two are not two spellings of one answer, and one program cannot carry
/// both: `Module.linkLibrary` records the directory the shared object was emitted
/// into, because `Step.Compile` appends `-rpath <dir>` for every dynamic
/// artifact a compilation links (`lib/std/Build/Step/Compile.zig:1290-1297`,
/// the block reached from `.other_step`).  That directory is the build cache.
/// It does not exist once the file is installed, and Nix refuses an installed
/// file that names its own build directory at all, so an installed program
/// that carried it could never be packaged -- and on ELF the loader would
/// search a directory that is gone rather than the one that is there.
/// `Module.addObjectFile` puts the very same file on the link line and records
/// no search path at all, which leaves the relocatable entry
/// `installedProgramRPath` returns as the only one an installed artifact
/// carries.
///
/// Which of the two a facade gets is a property of the *program* that imports
/// it, and a published facade has dependents of both kinds. The entry a module
/// contributes lands on every compilation whose graph imports that module, so
/// the published `inchi` module is `build_cache`: a dependent's executable is
/// built out of a build cache and finds the shared object in the one Zig baked
/// in. Only `bin/misuse` is built from an `install_tree` facade, and it is
/// built from a private one for that purpose.
const Loader = enum {
    /// A program `zig build install` writes into `bin/`.  It carries
    /// `$ORIGIN/../lib` -- `@loader_path/../lib` on Mach-O -- and nothing else,
    /// so it finds the library this prefix installed beside it and still finds
    /// it after the tree is moved.
    install_tree,
    /// Everything that is not installed, the published facade included: a
    /// dependent's executable, a test binary, and `smoke.zig`.  It keeps the
    /// ordinary `linkLibrary` call, so Zig bakes in the directory the library
    /// really is in and the loader looks there.  The entry never reaches a
    /// store, because nothing built this way is ever installed.
    build_cache,
};

/// Put `library` on `module`'s link line, with the search path a program of
/// this `Loader` needs and nothing else.
fn linkForLoader(
    module: *std.Build.Module,
    library: *std.Build.Step.Compile,
    target: std.Build.ResolvedTarget,
    loader: Loader,
) void {
    // Windows links through the import library and has no rpath, so the
    // ordinary call is the right one there for both loaders and is kept.
    if (library.linkage != .dynamic or target.result.os.tag == .windows) {
        module.linkLibrary(library);
        return;
    }
    switch (loader) {
        .build_cache => module.linkLibrary(library),
        .install_tree => {
            module.addObjectFile(library.getEmittedBin());
            if (installedProgramRPath(target)) |rpath| module.addRPathSpecial(rpath);
        },
    }
}

/// Whether a target's programs have to be compiled twice to have both loaders.
///
/// A static archive, an import-library link on COFF and a facade that links no
/// library at all all produce the same file for both `Loader` values, so a
/// second graph would be a second copy of a binary that is already right.  A
/// shared library on a platform with a runpath is the one case where they
/// differ, and it is the only case that pays for the second compilation.
fn needsBothLoaders(
    linked: ?*std.Build.Step.Compile,
    target: std.Build.ResolvedTarget,
) bool {
    const library = linked orelse return false;
    return library.linkage == .dynamic and target.result.os.tag != .windows;
}

/// The `#define` lines a translation header carries, assembled at comptime out
/// of the same macro tables the compile line uses, so the header and the
/// compile can never disagree about which configuration the API was declared
/// under.
fn macroDefinesText(macros: []const [2][]const u8) []const u8 {
    var out: []const u8 = "";
    for (macros) |macro| out = out ++ "#define " ++ macro[0] ++ " " ++ macro[1] ++ "\n";
    return out;
}

const system_translate_prefix = "#ifndef FOUNDATION_INCHI_SYSTEM_TRANSLATE_H\n" ++
    "#define FOUNDATION_INCHI_SYSTEM_TRANSLATE_H\n";
const system_translate_suffix = "\n#include <inchi_api.h>\n\n#endif\n";

/// The installed library is an archive, or is not an MSVC-ABI DLL: the plain
/// declarations, the same pair `core_macros` names.
const system_translate_text_plain = system_translate_prefix ++
    macroDefinesText(core_macros[0..]) ++ system_translate_suffix;

/// The installed library is an MSVC-ABI DLL. `BUILD_LINK_AS_DLL` alone, without
/// `_USRDLL`, is the half of the pair that selects the import arm of
/// `inchi_api.h:691-703`, so the translation sees `__declspec(dllimport)` on
/// every API declaration — which is what a caller of that DLL has to see, and
/// what it must not see for an archive.
const system_translate_text_import = system_translate_prefix ++
    macroDefinesText(core_macros[0..]) ++ macroDefinesText(dll_import_macros[0..]) ++
    system_translate_suffix;

/// The `-fsys=inchi` translation header.
///
/// It defines the macros the *installed* library's declarations have to be read
/// with, then includes the installed public header by its installed name. The
/// macros matter: `inchi_api.h` and `ixa.h` expand `INCHI_API`,
/// `EXPIMP_TEMPLATE` and `INCHI_DECL` (inchi_api.h:691-709), and those expand to
/// `__declspec(dllimport)` when `BUILD_LINK_AS_DLL` is defined without
/// `_USRDLL` — which a static archive does not satisfy and a DLL does.
///
/// Which of the two texts is used is decided by the caller from
/// `system_linkage` and the target ABI, never assumed here.
///
/// Generated into the cache rather than kept in the tree, so the repository
/// holds exactly one checked-in translation wrapper: `translate.h`, which names
/// the in-tree sources. A second wrapper for this mode would be a second place
/// that has to agree about the macros.
fn systemTranslateHeader(b: *std.Build, import_declarations: bool) std.Build.LazyPath {
    return b.addWriteFiles().add("inchi_system.h", if (import_declarations)
        system_translate_text_import
    else
        system_translate_text_plain);
}

/// The `inchi.pc` for the tree this build installs.
///
/// Three facts decide its contents and all three are read from the same
/// resolved target the artifact was compiled for, so the file cannot describe a
/// configuration this build did not produce:
///
///   * `Libs: -linchi`. The installed name is `libinchi.*` on ELF and Mach-O —
///     Zig's default `lib` prefix produces the same file name upstream's
///     `set_target_properties(libinchi PROPERTIES PREFIX "")`
///     (src/CMakeLists.txt:165) asks for — and `inchi.dll`/`inchi.lib` on
///     Windows, which is `-linchi` there too. This file is generated because
///     upstream ships none, and it says nothing more than the name.
///   * `Libs.private: -lm` exactly where this graph links libm separately.
///     On macOS, Windows and wasi libm is part of libc and naming it there
///     would be a lie about a dependency that does not exist.
///   * `Cflags`. `-DTARGET_API_LIB -DCOMPILE_ANSI_ONLY` are the macros the
///     library itself was compiled under, and on an MSVC-ABI shared install
///     `-DBUILD_LINK_AS_DLL` as well, so a C consumer of *that* DLL reads
///     `__declspec(dllimport)` on the API declarations. An archive, and every
///     non-MSVC target, take the plain pair.
///
/// `prefix=${pcfiledir}/../..` rather than the `--prefix` this build was
/// configured with: pkg-config substitutes `pcfiledir` with the directory it
/// found the file in, so the metadata is right for the prefix actually
/// installed under, including a `--prefix` chosen after configuration or a
/// tree moved after installation. Nothing here is a promise of a wholly static
/// executable: `Libs` names a library and `Libs.private` names its private
/// dependency, which is what pkg-config is for.
fn addPkgConfig(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    linkage: std.builtin.LinkMode,
) std.Build.LazyPath {
    const import_flag = if (linkage == .dynamic and isWindowsMsvc(target))
        " -DBUILD_LINK_AS_DLL"
    else
        "";
    const libm = if (isElfUnix(target)) "\nLibs.private: -lm" else "";
    return b.addWriteFiles().add("inchi.pc", b.fmt(
        \\# Generated by this package's build.zig. Do not edit.
        \\prefix=${{pcfiledir}}/../..
        \\exec_prefix=${{prefix}}
        \\libdir=${{prefix}}/lib
        \\includedir=${{prefix}}/include
        \\
        \\Name: libinchi
        \\Description: The IUPAC International Chemical Identifier (InChI) and InChIKey library
        \\URL: https://github.com/IUPAC-InChI/InChI
        \\Version: {s}
        \\Libs: -L${{libdir}} -linchi{s}
        \\Cflags: -I${{includedir}} -DTARGET_API_LIB -DCOMPILE_ANSI_ONLY{s}
        \\
    , .{ upstream.current_ver, libm, import_flag }));
}

/// Installs every carried licence text and provenance record under
/// `share/licenses/inchi/`.
///
/// These are copies of files already in this repository, byte for byte;
/// nothing is rewritten, merged or truncated on the way out. `b.installFile`
/// takes a repository path and attaches its own step to the install step
/// (`lib/std/Build.zig:1675-1677`), so this needs no separate `dependOn` —
/// which is why the list above, and not a directory copy, is what makes the
/// install complete: a missing entry is a build failure naming the file.
fn installLicenceRecords(b: *std.Build) void {
    for (licence_records) |record| {
        b.installFile(record.source, b.fmt("share/licenses/inchi/{s}", .{record.installed}));
    }
}

/// Resolves a target triple written the way `zig build -Dtarget=` writes it, so
/// that this and `-Dtarget=` mean the same thing.
fn parseTriple(b: *std.Build, triple: []const u8) std.Target.Query {
    return std.Build.parseTargetQuery(.{ .arch_os_abi = triple }) catch |err| {
        @panic(b.fmt("build.zig: {s} is not a target triple: {s}", .{ triple, @errorName(err) }));
    };
}

/// Invokes the consumer package as its own `zig build` in consumer/.
///
/// The target, the optimisation mode, the linkage, `-Druntime` and
/// `-fsys`/`-fno-sys` are forwarded, because the nested graph configures this
/// package again as a path dependency and each of those is read there from its
/// own options. The build runner's executor switches and `--libc-runtimes` are
/// forwarded for the same reason: the nested build resolves its own copy of
/// them, and the step below has to reach the same decision this one did.
///
/// The standard build-runner switches go with them, because the nested build
/// reads none of them from the outer one otherwise: `-j8` and `--summary all`
/// are this workspace's own entry shape (`AGENTS.md:157-158`), the local cache
/// becomes a `consumer` subdirectory of the outer one and the global cache is
/// inherited whole, and whatever the caller wrote after `--` is forwarded
/// verbatim behind a `--` of its own, because that is the only place a nested
/// `zig build` keeps an argument it did not resolve.
///
/// Run, or only install
/// --------------------
/// The question is whether *this host* can execute the selected target. It is
/// asked of the resolved target by `std.zig.system.getExternalExecutor`
/// (`lib/std/zig/system.zig:42`), the same function `std.Build.Step.Run` calls
/// when a spawned binary turns out to be foreign
/// (`lib/std/Target/Query.zig:396-398`) is `isNativeTriple()` and `ofmt == null`,
/// and `isNativeTriple()` (`:392-394`) demands `cpu_arch`, `os_tag` and `abi`
/// all be null, so `-Dtarget=x86_64-linux-gnu` was never native on an x86_64
/// Linux host -- this step took the `install` branch and built the consumer
/// without running it, which is the one thing this step exists to prevent.
///
/// An external executor counts as available only when the build runner was
/// told it may use one: `-fwasmtime`, `-fqemu`, `-fwine` and `-fdarling` are
/// the build runner's own switches for that
/// (`lib/compiler/build_runner.zig:388-407`, exposed as `b.enable_wasmtime`
/// and friends, `lib/std/Build.zig:71-79`), and each names a separate program
/// whose presence on `PATH` this script cannot know. `-frosetta` names none and
/// `std.Build` reads `enable_rosetta` nowhere, so it is forwarded for fidelity
/// and never gates the decision; `hostCanExecute` says why. Forwarding the
/// switches makes the decision and the nested run agree on one executor: an
/// explicitly enabled Wasmtime executes a `wasm32-wasi` consumer here, and
/// without it the step installs only. A target that still has no executor
/// builds and installs, which is compile evidence and nothing more.
fn runConsumer(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    use_system: bool,
    linkage: std.builtin.LinkMode,
    runtime: bool,
) *std.Build.Step.Run {
    const query = target.query;
    // `addArg` copies each argument, so these temporaries can go right after.
    const triple = query.zigTriple(b.allocator) catch @panic("OOM");
    defer b.allocator.free(triple);
    const cpu = query.serializeCpuAlloc(b.allocator) catch @panic("OOM");
    defer b.allocator.free(cpu);

    // `b.graph.zig_exe` is the compiler running this build script, so the
    // nested build is the same toolchain rather than whatever is on PATH.
    const run = b.addSystemCommand(&.{ b.graph.zig_exe, "build" });
    run.setName("consumer package");
    run.setCwd(b.path(consumer_dir));
    run.addArg(if (hostCanExecute(b, target)) "run" else "install");
    run.addArg(b.fmt("-Dtarget={s}", .{triple}));
    run.addArg(b.fmt("-Dcpu={s}", .{cpu}));
    // The nested build has its own `standardOptimizeOption` and it configures
    // the dependency, so the requested mode is forwarded verbatim: a Debug gate
    // has to mean Debug on both sides.
    run.addArg(b.fmt("-Doptimize={s}", .{@tagName(optimize)}));

    // The linkage is forwarded for the same reason as the options above: the
    // nested build configures this package as a path dependency and reads
    // `linkage` from its own options, so without this argument a
    // `zig build consumer -Dlinkage=dynamic` run would build and prove the
    // static artifact while the outer graph had produced the shared one. The
    // nested graph's `consumer/build.zig` reads the option and hands it to
    // `b.dependency`, so the two graphs really do build the same thing.
    run.addArg(b.fmt("-Dlinkage={s}", .{@tagName(linkage)}));

    // `-Druntime` is forwarded for the same reason again. The nested graph
    // reads it from its own options and hands it to `b.dependency`, so this is
    // what makes `zig build consumer -Druntime=true` a consumer that really
    // loads a provider instead of one that links the artifact and calls the
    // result a runtime build. Both spellings are always sent, not only the
    // true one, so a cell's configuration is stated rather than inferred from
    // a default — and the flag cannot be dropped on the way down.
    run.addArg(b.fmt("-Druntime={}", .{runtime}));

    // The system-integration choice was already resolved by
    // `b.systemIntegrationOption` in this build(), and the nested graph runs
    // this package's own `build()` again as a path dependency. Without the
    // argument that second run would fall back to its own default, so
    // `zig build consumer -fsys=inchi` would install one configuration and
    // then prove the consumer against another without saying so.
    run.addArg(if (use_system) "-fsys=inchi" else "-fno-sys=inchi");

    // The executor switches this build resolved, so the nested build runs
    // under the same one `hostCanExecute` decided with: `-fwasmtime` is how a
    // WASI consumer executes here, and `--libc-runtimes`
    // (`lib/compiler/build_runner.zig:323-325`) is the QEMU integration's
    // dynamic-linker support, which `qemu_fixes_dl` below also depends on.
    if (b.enable_darling) run.addArg("-fdarling");
    if (b.enable_qemu) run.addArg("-fqemu");
    if (b.enable_rosetta) run.addArg("-frosetta");
    if (b.enable_wasmtime) run.addArg("-fwasmtime");
    if (b.enable_wine) run.addArg("-fwine");
    if (b.libc_runtimes_dir) |runtimes| run.addArgs(&.{ "--libc-runtimes", runtimes });

    // The nested build's own width is stated rather than derived. Nothing can
    // append a `-j` to a `Run` step's command, so a nested build left to
    // resolve one takes `cpu_count - 1`
    // (`lib/std/Io/Threaded.zig:1639`) instead, and the consumer this step
    // proves would then compile at a width the outer build never chose -- and at
    // a different width again on whichever machine runs the gate. Eight is the
    // width this workspace's own `zig build` entries carry (`AGENTS.md:157-158`).
    run.addArg("-j8");
    // `--summary all` is two tokens because that is the only spelling the build
    // runner parses (`lib/compiler/build_runner.zig:262-268`, documented at
    // `:1639-1640`). Left out, the nested build prints the `.failures` default
    // a short-lived run gets (`:523`), which is one line for a graph of
    // several steps.
    run.addArgs(&.{ "--summary", "all" });
    // When the outer build was given an explicit cache directory, the nested
    // one gets a subdirectory of it rather than sharing it: two build graphs
    // must not write the same manifest directory.
    if (b.cache_root.path) |cache| {
        run.addArg("--cache-dir");
        run.addArg(b.fmt("{s}/consumer", .{cache}));
    }
    // The global cache is inherited whole rather than subdirectoryed: it is one
    // shared store of packages and hashes, so a nested build left to resolve
    // its own would fetch again what this one already holds. Two tokens, as
    // documented at `lib/compiler/build_runner.zig:1675`, which is also how the
    // compiler emits it from a build script of its own
    // (`lib/std/Build/Step/Compile.zig:1478-1479`).
    if (b.graph.global_cache_root.path) |global_cache| {
        run.addArg("--global-cache-dir");
        run.addArg(global_cache);
    }
    // The caller's own install prefix, when it named one. The default is this
    // build's `<build root>/zig-out`; a prefix that is not the default is
    // forwarded, and made absolute first, because a relative `--prefix`
    // resolves against the nested working directory, which is `consumer/`
    // rather than this build's root. `DESTDIR` needs no forwarding: the
    // nested build inherits the environment this one ran with.
    const default_prefix = b.build_root.join(b.allocator, &.{"zig-out"}) catch @panic("OOM");
    if (!std.mem.eql(u8, b.install_prefix, default_prefix)) {
        const prefix = if (std.fs.path.isAbsolute(b.install_prefix))
            b.install_prefix
        else
            b.pathJoin(&.{ b.graph.cache.cwd, b.install_prefix });
        run.addArg("--prefix");
        run.addArg(prefix);
    }
    // The caller's own arguments, last and behind `--`: `--` is where the build
    // runner stops parsing options and keeps the rest as `b.args`
    // (`lib/compiler/build_runner.zig:428-430`), the nested package hands those
    // to the program it runs (`consumer/build.zig:81`), and that program is the
    // consumer check. So `zig build consumer -Druntime=true -- --provider
    // <path>` -- the command `README.md:255` publishes and
    // `.github/workflows/verify.yml:316` runs -- reaches the consumer that
    // checks the load, and every argument above is this package's own
    // bookkeeping with the nested build, which is why this `--` follows all of
    // them: it ends the nested build's option parsing.
    if (b.args) |args| {
        run.addArg("--");
        run.addArgs(args);
    }
    // The nested build is the step's only observable effect.
    run.has_side_effects = true;
    return run;
}

/// True when this build can execute `target`'s binaries.
///
/// `std.zig.system.getExternalExecutor` (`lib/std/zig/system.zig:42`) is the
/// predicate `std.Build.Step.Run` asks about the artifact it is about to spawn
/// (`lib/std/Build/Step/Run.zig:1268`). Both options `Run` fills in from that
/// artifact are filled in here from the same facts: the consumer executable
/// links libc because the library module it imports requires it
/// (`lib/std/Build/Step/Compile.zig:1054-1057` computes `is_linking_libc` over
/// every module in the graph, not just the root one), and QEMU reaches a
/// foreign dynamic linker only with `--libc-runtimes`.
///
/// One target serves both roles `Run` asks about, because `rootModuleTarget`
/// (`lib/std/Build/Step/Compile.zig:2067-2070`) *is* the root module's resolved
/// target, which is the one `getExternalExecutor` is given.
///
/// `Run` allows every executor in the predicate and then gates the answer on
/// this build's own switches (`:1277`, `:1291`, `:1317`, `:1325`); carrying
/// those switches in `allow_*` asks the identical question and answers it
/// without a second switch, which is why the two cannot disagree. QEMU's
/// second gate is the exception, and the `.qemu` arm below carries it: for a
/// cross libc target `:1310` fails the step unless `b.libc_runtimes_dir` is
/// set, so `-fqemu` alone answers "run" for a case `Run` would refuse. Rosetta
/// is left at its default, as `Run` leaves it: `-frosetta` resolves, but
/// nothing in `std.Build` reads `b.enable_rosetta`, because on an Apple
/// Silicon host it is the operating system that runs the binary rather than a
/// program this build would have to find.
fn hostCanExecute(b: *std.Build, target: std.Build.ResolvedTarget) bool {
    const host = &b.graph.host.result;
    const candidate = &target.result;
    const options: std.zig.system.GetExternalExecutorOptions = .{
        .allow_darling = b.enable_darling,
        .allow_qemu = b.enable_qemu,
        .allow_wasmtime = b.enable_wasmtime,
        .allow_wine = b.enable_wine,
        // `Run`'s `need_cross_libc` (`lib/std/Build/Step/Run.zig:1264-1266`) is
        // `exe.is_linking_libc` and a test of the target itself; its musl half
        // additionally asks for `exe.linkage == .dynamic`, and `consumer/`
        // builds its executable with `b.addExecutable` and no linkage, so that
        // field is null there and the half never contributes.
        .qemu_fixes_dl = candidate.isGnuLibC() and b.libc_runtimes_dir != null,
        .link_libc = true,
    };
    return switch (std.zig.system.getExternalExecutor(b.graph.io, host, candidate, options)) {
        .native, .rosetta => true,
        // `Run`'s QEMU arm (`lib/std/Build/Step/Run.zig:1290-1314`) appends
        // `-L <runtime triple>` for a cross libc target and, with
        // `b.libc_runtimes_dir` unset, `failForeign` on `--libc-runtimes`
        // (`:1310`) instead of skipping the run. So on this target the missing
        // directory is not a skip but a failure, and the answer has to be no.
        //
        // `qemu_fixes_dl` above cannot carry that: `getExternalExecutor` enters
        // the QEMU arm for a foreign CPU on `!cpu_ok` alone
        // (`lib/std/zig/system.zig:95`), whatever that option says, so the
        // returned executor is `.qemu` in exactly the case the option stops
        // describing. `isGnuLibC` is the whole of `Run`'s `need_cross_libc` here
        // — the consumer links libc through the library module, and the
        // `.isMuslLibC() and exe.linkage == .dynamic` half never holds because
        // `consumer/` sets no linkage — so the two now test the same fact.
        .qemu => !candidate.isGnuLibC() or b.libc_runtimes_dir != null,
        // Reachable only for an executor the switches above enabled, each of
        // which `Run` gates on the same switch and nothing else.
        .wine, .wasmtime, .darling => true,
        // Same OS and CPU with no dynamic linker to load, or an architecture
        // and system this build has no enabled executor for.
        .bad_dl, .bad_os_or_cpu => false,
    };
}
