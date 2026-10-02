//! Build graph for the IUPAC/InChI `libinchi` core.
//!
//! What this builds, and from where:
//!
//!   * The complete upstream API library, compiled from this repository's own
//!     C sources. The compile unit list is the `target_sources(libinchi PRIVATE
//!     ...)` block of `INCHI-1-SRC/INCHI_API/libinchi/src/CMakeLists.txt`,
//!     written out below file by file rather than globbed, so a new upstream
//!     translation unit cannot enter the archive without a decision here.
//!   * `inchi`, the Zig facade over the translated public API. The facade root
//!     is `zig/root.zig` and it reaches the C declarations through
//!     `@import("c")`, the module produced by `addTranslateC`.
//!   * `tests.zig` and `smoke.zig`, which call every public facade entry point.
//!
//! There is no CMake, no autotools, no Make and no download. Upstream's core has
//! no generated inputs at all: there is no `inchi_version.h`, no `.h.in`, no
//! configure step, so there is nothing to generate and nothing to fetch.
//!
//! Options, as the build runner spells them:
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
//! Steps: the default install step, `test`, `smoke`, `check`, `consumer`.

const std = @import("std");

const manifest = @import("build.zig.zon");

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
const c_flags = [_][]const u8{
    "-std=c11",
    "-fno-strict-aliasing",
};

/// The macros upstream's own library build defines
/// (`target_compile_definitions(libinchi PRIVATE ... COMPILE_ANSI_ONLY
/// TARGET_API_LIB)`, src/CMakeLists.txt:154-158). `fPIC`, also in that list, is
/// a CMake-ism here: the macro is inert in the sources, and position-independent
/// code is a property of the link, not of this C.
const core_macros = [_][2][]const u8{
    .{ "TARGET_API_LIB", "1" },
    .{ "COMPILE_ANSI_ONLY", "1" },
};

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

/// Everything a dependent needs: the Zig facade, with `c` bound to the
/// translated public header and the library already linked into it.
const InchiPackage = struct {
    module: *std.Build.Module,
    /// Null in `-fsys=inchi` mode, where the library comes from the system and
    /// this package installs nothing of its own.
    artifact: ?*std.Build.Step.Compile,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const use_system = b.systemIntegrationOption("inchi", .{});

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
        artifact.installHeader(b.path(base_src ++ "/inchi_api.h"), "inchi_api.h");
        artifact.installHeader(b.path(base_src ++ "/ixa.h"), "ixa.h");
    }

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
    // built by `zig build` and never installed.
    const smoke_exe = addSmokeExecutable(b, "inchi-smoke", target, optimize, inchi.module);
    b.getInstallStep().dependOn(&smoke_exe.step);

    const smoke_step = b.step("smoke", "Run the deterministic smoke program");
    const run_smoke = b.addRunArtifact(smoke_exe);
    smoke_step.dependOn(&run_smoke.step);
    if (b.args) |args| run_smoke.addArgs(args);

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
    const check_step = b.step(
        "check",
        "Compile the C core, the facade, the tests and the smoke program for every cross target without running them",
    );
    if (!target.query.isNative()) {
        addTargetCheck(b, check_step, "selected", target.query, optimize);
    } else {
        for (check_targets) |triple| {
            addTargetCheck(b, check_step, triple, parseTriple(b, triple), optimize);
        }
    }

    // ---- Consumer package --------------------------------------------------
    //
    // consumer/ is a separate package with its own manifest, depending on this
    // one by path and importing `dep.module("inchi")`. It cannot be a dependency
    // of this manifest: that would close a cycle, because its manifest points
    // back here by path. It is therefore built as its own `zig build`, with the
    // target, the optimisation mode and the system-integration choice
    // forwarded on the command line, and with the build runner's executor
    // switches forwarded alongside them, so the nested `run` executes the
    // consumer under the same executor `hostCanExecute` decided with.
    const consumer_step = b.step(
        "consumer",
        "Build the consumer/ package against the exported module, and run it when this host can execute the selected target",
    );
    consumer_step.dependOn(&runConsumer(b, target, optimize, use_system).step);
}

/// Compiles, but never runs, everything that makes up the public surface for
/// one target.
fn addTargetCheck(
    b: *std.Build,
    step: *std.Build.Step,
    label: []const u8,
    query: std.Target.Query,
    optimize: std.builtin.OptimizeMode,
) void {
    const cross_target = b.resolveTargetQuery(query);
    const cross = addInchi(b, .{
        .target = cross_target,
        .optimize = optimize,
        // A system library is by definition the host's, so the cross matrix
        // always builds the bundled sources.
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
    /// `-fsys=inchi`: bind to an installed libinchi and translate its headers
    /// instead of building this repository's copy.
    use_system: bool,
    /// Register the module as `dep.module("inchi")` for dependents. Only the
    /// package's own graph may do that: modules are registered by name against
    /// the whole build, so registering "inchi" once per cross target would
    /// leave only the last one reachable and silently stop checking the rest.
    register_module: bool,
};

fn addInchi(b: *std.Build, options: InchiOptions) InchiPackage {
    const root_source_file: std.Build.LazyPath =
        if (options.use_system)
            // The system mode translates the header that is actually installed
            // next to the library it links, so no in-tree include path is added:
            // an in-tree header is found first and would silently bind this
            // repository's 1.07.5 declarations to whatever libinchi is
            // installed. Upstream ships no pkg-config file and no install rules
            // (there is no `install(` in either CMakeLists.txt), so there is
            // nothing to ask pkg-config for and the header is taken from the
            // compiler's own system include path.
            systemTranslateHeader(b)
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

    module.addImport("c", translate_c.createModule());
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
    switch (options.target.result.os.tag) {
        .linux, .freebsd, .netbsd, .openbsd, .dragonfly, .illumos => {
            module.linkSystemLibrary("m", .{});
        },
        else => {},
    }
    if (!options.use_system) {
        // A dependent that compiles its own C against this module needs the
        // same header set the core was compiled with.
        module.addIncludePath(b.path(base_src));
    }

    var artifact: ?*std.Build.Step.Compile = null;
    if (options.use_system) {
        // `inchi` is the only name the linker can resolve: the libinchi CMake
        // target sets `PREFIX ""` (src/CMakeLists.txt:165) and produces
        // libinchi.so/.dylib/.dll, and `libinchi/gcc/makefile:77` names the
        // library libinchi as well. Upstream provides no pkg-config file, so
        // `-linchi` rather than a pkg-config query that would find nothing.
        module.linkSystemLibrary("inchi", .{ .use_pkg_config = .no });
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
        core.addCSourceFiles(.{ .root = b.path(api_src), .files = &api_sources, .flags = &c_flags });
        core.addCSourceFiles(.{ .root = b.path(ixa_src), .files = &ixa_sources, .flags = &c_flags });
        core.addCSourceFiles(.{ .root = b.path(base_src), .files = &base_sources, .flags = &c_flags });

        artifact = b.addLibrary(.{
            .name = "inchi",
            .linkage = .static,
            .version = upstream.version,
            .root_module = core,
        });
        // Linking the archive into the facade module is what lets a dependent
        // use nothing but `dep.module("inchi")`: it needs no `dep.artifact`, no
        // -linchi of its own and no extra include path.
        module.linkLibrary(artifact.?);
    }

    return .{ .module = module, .artifact = artifact };
}

/// The `#define` lines the system translation header carries, assembled at
/// comptime out of `core_macros` so that the header and the bundled compile can
/// never disagree about which target the API was built for.
const system_macro_defines = blk: {
    var out: []const u8 = "";
    for (core_macros) |macro| out = out ++ "#define " ++ macro[0] ++ " " ++ macro[1] ++ "\n";
    break :blk out;
};

const system_translate_text = "#ifndef FOUNDATION_INCHI_SYSTEM_TRANSLATE_H\n" ++
    "#define FOUNDATION_INCHI_SYSTEM_TRANSLATE_H\n" ++ system_macro_defines ++
    "\n#include <inchi_api.h>\n\n#endif\n";

/// The `-fsys=inchi` translation header.
///
/// It defines the same macros the bundled core is compiled with and then
/// includes the installed public header by its installed name. The macros
/// matter: `inchi_api.h` and `ixa.h` expand `INCHI_API`, `EXPIMP_TEMPLATE` and
/// `INCHI_DECL` (inchi_api.h:691-709), and a translation that saw
/// `BUILD_LINK_AS_DLL` defined would read `__declspec(dllimport)` declarations
/// that a static archive does not satisfy. Generated into the cache rather
/// than kept in the tree, so the repository holds exactly one translation
/// wrapper: translate.h, which names the in-tree sources.
fn systemTranslateHeader(b: *std.Build) std.Build.LazyPath {
    return b.addWriteFiles().add("inchi_system.h", system_translate_text);
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
/// The target, the optimisation mode and `-fsys`/`-fno-sys` are forwarded,
/// because the nested graph configures this package again as a path
/// dependency and each of the three is read there from its own options. The
/// build runner's executor switches and `--libc-runtimes` are forwarded for
/// the same reason: the nested build resolves its own copy of them, and the
/// step below has to reach the same decision this one did.
///
/// Run, or only install
/// --------------------
/// The question is whether *this host* can execute the selected target. It is
/// asked of the resolved target by `std.zig.system.getExternalExecutor`
/// (`lib/std/zig/system.zig:42`), the same function `std.Build.Step.Run` calls
/// when a spawned binary turns out to be foreign
/// (`lib/std/Build/Step/Run.zig:1268`). That replaces a predicate which could
/// not answer it: `Target.Query.isNative()`
/// (`lib/std/Target/Query.zig:396-398`) is `isNativeTriple() and ofmt == null`,
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

    // When the outer build was given an explicit cache directory, the nested
    // one gets a subdirectory of it rather than sharing it: two build graphs
    // must not write the same manifest directory.
    if (b.cache_root.path) |cache| {
        run.addArg("--cache-dir");
        run.addArg(b.fmt("{s}/consumer", .{cache}));
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
