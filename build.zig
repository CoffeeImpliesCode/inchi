//! SPDX-License-Identifier: LicenseRef-InChI-MIT-Conditional

const std = @import("std");

const manifest = @import("build.zig.zon");

const graph = @import("runtime/graph.zig");

const upstream = struct {
    const canonical_url = "https://github.com/IUPAC-InChI/InChI.git";
    const tag = "v1.07.5";
    const commit = "11a87982bb518f57ac013f0b258c283655e1ea1d";
    const version: std.SemanticVersion = .{ .major = 1, .minor = 7, .patch = 5 };
    /// `CURRENT_VER` is the software version; `INCHI_VERSION` is the InChI standard version.
    const current_ver = "1.07.5";
};

/// Upstream source roots, also used as C include paths.
const base_src = "INCHI-1-SRC/INCHI_BASE/src";
const api_src = "INCHI-1-SRC/INCHI_API/libinchi/src";
const ixa_src = api_src ++ "/ixa";

/// libinchi/src translation units listed by upstream CMake.
const api_sources = [_][]const u8{
    "ichilnct.c",
    "inchi_dll.c",
    "inchi_dll_a.c",
    "inchi_dll_a2.c",
    "inchi_dll_b.c",
    "inchi_dll_main.c",
};

/// IXA translation units listed by upstream CMake.
const ixa_sources = [_][]const u8{
    "ixa_builder.c",
    "ixa_inchikey_builder.c",
    "ixa_mol.c",
    "ixa_read_inchi.c",
    "ixa_read_mol.c",
    "ixa_status.c",
};

/// INCHI_BASE translation units; headers are included, not compiled.
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

/// Upstream C11 and aliasing flags.
/// Keep `-fno-strict-aliasing` for the varargs formatter and digest code.
const static_c_flags = [_][]const u8{
    "-std=c11",
    "-fno-strict-aliasing",
};

/// Add PIC to shared builds except on Windows; COFF does not use `-fPIC`.
const shared_c_flags = [_][]const u8{
    "-std=c11",
    "-fno-strict-aliasing",
    "-fPIC",
};

/// These API macros must match on C compilation and C translation.
const core_macros = [_][2][]const u8{
    .{ "TARGET_API_LIB", "1" },
    .{ "COMPILE_ANSI_ONLY", "1" },
};

/// MSVC DLL definitions; `_USRDLL` selects `dllexport` for the library.
/// MinGW skips these macros and uses linker auto-export.
const dll_export_macros = [_][2][]const u8{
    .{ "BUILD_LINK_AS_DLL", "1" },
    .{ "_USRDLL", "1" },
};

/// Import declaration macro for an MSVC DLL consumer.
const dll_import_macros = [_][2][]const u8{
    .{ "BUILD_LINK_AS_DLL", "1" },
};

/// Upstream's version script limits ELF shared-library exports to API symbols.
const library_map_path = "INCHI-1-SRC/INCHI_API/libinchi/gcc/libinchi.map";

/// ELF targets that need separate libm and upstream's version script.
/// Keep both target predicates aligned.
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

/// Recognize all MSVC ABI tags for Windows.
fn isWindowsMsvc(target: std.Build.ResolvedTarget) bool {
    return target.result.os.tag == .windows and
        std.mem.startsWith(u8, @tagName(target.result.abi), "msvc");
}

/// Targets compiled by `check`; binaries are not run.
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

const runtime_test_source = "runtime/load_tests.zig";
const misuse_source = "runtime/misuse.zig";

/// Documentation and licence files installed as source-to-name pairs.
const installed_doc_files = [_]struct { source: []const u8, installed: []const u8 }{
    .{ .source = "LICENSE", .installed = "LICENSE" },
    .{ .source = "NOTICE.md", .installed = "NOTICE.md" },
    .{ .source = "FORK-LICENSE.md", .installed = "FORK-LICENSE.md" },
    .{ .source = "UPSTREAM.md", .installed = "UPSTREAM.md" },
    .{ .source = "README.md", .installed = "README.md" },
    .{ .source = "README.upstream.md", .installed = "README.upstream.md" },
    // Apache-2.0 terms for the uncompiled TBB proxy header.
    .{ .source = "INCHI-1-SRC/INCHI_API/tbb/LICENSE", .installed = "tbb/LICENSE" },
};

/// Licence and provenance records installed under `share/licenses/inchi/`.
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

/// Module and native build state shared by package facades.
const InchiPackage = struct {
    module: *std.Build.Module,
    /// Null when linking an installed system library.
    artifact: ?*std.Build.Step.Compile,
    /// Translation step shared by facades for the same target.
    /// Shared loader core; absent from runtime dispatch.
    translate_c: *std.Build.Step.TranslateC,
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
    // Link mode for an installed system library.
    const system_linkage = linkage_option orelse .dynamic;
    const use_system = b.systemIntegrationOption("inchi", .{});

    // Runtime loading changes dispatch, not the built artifact.
    const runtime = b.option(
        bool,
        "runtime",
        "Resolve libinchi's symbols at run time through the platform loader " ++
            "instead of linking the artifact into the facade (default false)",
    ) orelse false;
    // System linking and runtime loading are mutually exclusive.
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
        // Install the complete public header closure; inchi_api.h includes ixa.h.
        artifact.installHeader(b.path(base_src ++ "/inchi_api.h"), "inchi_api.h");
        artifact.installHeader(b.path(base_src ++ "/ixa.h"), "ixa.h");

        // Generate relocatable pkg-config metadata with target-specific libm.
        const install_pc = b.addInstallFileWithDir(addPkgConfig(b, target, linkage), .lib, "pkgconfig/inchi.pc");
        b.getInstallStep().dependOn(&install_pc.step);

        // Install documentation records.
        for (installed_doc_files) |doc| {
            b.installFile(doc.source, b.fmt("share/doc/inchi/{s}", .{doc.installed}));
        }

        // Install licence records under their standard path.
        installLicenceRecords(b);
    }

    // Installed `misuse` needs an install-tree rpath; other programs use the build-cache facade.
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
            // Reuse the library and translation step; only the rpath differs.
            .shared = &inchi,
        }).module
    else
        inchi.module;

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

    const smoke_exe = addSmokeExecutable(b, "inchi-smoke", target, optimize, inchi.module);
    b.getInstallStep().dependOn(&smoke_exe.step);

    const smoke_step = b.step("smoke", "Run the deterministic smoke program");
    const run_smoke = b.addRunArtifact(smoke_exe);
    smoke_step.dependOn(&run_smoke.step);
    if (b.args) |args| run_smoke.addArgs(args);

    // Runtime tests require a provider and are built only in runtime mode.
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

    // Cross-target checks compile the C core and facade without running binaries.
    // WASI cannot provide shared libraries or `dlopen`.
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

    // Build the consumer separately and forward the selected configuration.
    // Its path dependency points back here, so it cannot join this manifest.
    const consumer_step = b.step(
        "consumer",
        "Build the consumer/ package against the exported module, and run it when this host can execute the selected target",
    );
    consumer_step.dependOn(&runConsumer(b, target, optimize, use_system, linkage, runtime).step);
}

/// Compile the public surface for one target without running it.
fn addTargetCheck(
    b: *std.Build,
    step: *std.Build.Step,
    label: []const u8,
    query: std.Target.Query,
    linkage: std.builtin.LinkMode,
    optimize: std.builtin.OptimizeMode,
    /// Thread the selected dispatch mode into every target check.
    runtime: bool,
) void {
    const cross_target = b.resolveTargetQuery(query);
    const cross = addInchi(b, .{
        .target = cross_target,
        .optimize = optimize,
        .linkage = linkage,
        .runtime = runtime,
        // Cross-target checks always build the bundled library.
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
    /// Kind of artifact this graph builds.
    linkage: std.builtin.LinkMode,
    /// Select loader dispatch independently of artifact linkage.
    /// Link mode for an installed system library.
    /// Use an installed libinchi instead of the bundled sources.
    /// Register the module for dependents, not cross-target sub-builds.
    /// Search-path policy for programs that use this facade.
    /// Reuse an existing graph's library, translation, and loader core.
    runtime: bool = false,
    system_linkage: std.builtin.LinkMode = .dynamic,
    use_system: bool,
    register_module: bool,
    loader: Loader = .build_cache,
    shared: ?*const InchiPackage = null,
};

fn addInchi(b: *std.Build, options: InchiOptions) InchiPackage {
    // Only installed MSVC DLL consumers need import declarations.
    const system_import_declarations = options.use_system and
        options.system_linkage == .dynamic and
        isWindowsMsvc(options.target);

    // Bundled builds use plain declarations; MSVC DLLs need export decoration.

    // Reuse graph state when both build-cache and install-tree facades are needed.
    const reused = options.shared;
    const translate_c = if (reused) |previous| previous.translate_c else translate: {
        const root_source_file: std.Build.LazyPath =
            if (options.use_system)
                // Translate the installed header in system mode, not the in-tree header.
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
        // Use pkg-config's include paths for the installed library.
        if (options.use_system) {
            translate_c.linkSystemLibrary("inchi", .{
                .use_pkg_config = .yes,
                .preferred_link_mode = options.system_linkage,
            });
        }
        break :translate translate_c;
    };

    // The module needs its resolved target before system libraries are attached.
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

    // Bind the same translation output to the runtime dispatch.
    // The linked facade shares one loader core so its types stay identical.
    var rt_core: ?*std.Build.Module = null;
    if (options.runtime) {
        module.addImport("c", graph.createModule(b, translate_c, options.target, options.optimize));
    } else {
        module.addImport("c", translate_c.createModule());
        // Share one loader core, and therefore one set of public loader types.
        rt_core = if (reused) |previous|
            previous.rt_core.?
        else
            graph.createCoreModule(b, options.target, options.optimize);
        module.addImport("rt", rt_core.?);
    }
    module.link_libc = true;
    // Link libm on the module so dependent executables receive the dependency.
    if (isElfUnix(options.target)) {
        module.linkSystemLibrary("m", .{});
    }
    if (!options.use_system) {
        // Dependents need the same public C header include path.
        module.addIncludePath(b.path(base_src));
    }

    var artifact: ?*std.Build.Step.Compile = null;
    if (reused) |previous| {
        artifact = previous.artifact;
    } else if (options.use_system) {
        // Resolve the installed library and its include flags through pkg-config.
        module.linkSystemLibrary("inchi", .{
            .use_pkg_config = .yes,
            .preferred_link_mode = options.system_linkage,
        });
    } else {
        const core = b.createModule(.{
            .target = options.target,
            .optimize = options.optimize,
            .link_libc = true,
            .sanitize_c = .off,
        });
        for ([_][]const u8{ base_src, api_src, ixa_src }) |dir| core.addIncludePath(b.path(dir));
        for (core_macros) |macro| core.addCMacro(macro[0], macro[1]);
        // Add export decoration only for MSVC-ABI Windows DLLs.
        if (options.linkage == .dynamic and isWindowsMsvc(options.target)) {
            for (dll_export_macros) |macro| core.addCMacro(macro[0], macro[1]);
        }

        // Shared non-Windows builds need position-independent code.
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
        // Apply upstream's export list to ELF shared libraries.
        if (options.linkage == .dynamic and isElfUnix(options.target)) {
            artifact.?.setVersionScript(b.path(library_map_path));
        }

    }

    // Link only for linked dispatch; runtime mode resolves symbols after load.
    // Use an install-tree rpath only for the installed program.
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

/// Search path for an installed program to find its shared library.
/// ELF uses `$ORIGIN`; Mach-O uses `@loader_path`; Windows searches beside the executable.
fn installedProgramRPath(target: std.Build.ResolvedTarget) ?[]const u8 {
    return switch (target.result.os.tag) {
        .windows, .wasi, .uefi => null,
        else => if (target.result.os.tag.isDarwin()) "@loader_path/../lib" else "$ORIGIN/../lib",
    };
}

/// Select the library search path for the importing program.
/// Installed programs use a relative path; other programs use the build cache.
const Loader = enum {
    /// Relocatable search path from the installed program to its library.
    install_tree,
    /// Search the build-cache directory for non-installed programs.
    build_cache,
};

/// Link a library using this loader's search-path policy.
fn linkForLoader(
    module: *std.Build.Module,
    library: *std.Build.Step.Compile,
    target: std.Build.ResolvedTarget,
    loader: Loader,
) void {
    // Windows uses an import library and searches for the DLL beside the executable.
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

/// True when install-tree and build-cache programs need separate graphs.
fn needsBothLoaders(
    linked: ?*std.Build.Step.Compile,
    target: std.Build.ResolvedTarget,
) bool {
    const library = linked orelse return false;
    return library.linkage == .dynamic and target.result.os.tag != .windows;
}

/// Format C preprocessor definitions for a translation header.
fn macroDefinesText(macros: []const [2][]const u8) []const u8 {
    var out: []const u8 = "";
    for (macros) |macro| out = out ++ "#define " ++ macro[0] ++ " " ++ macro[1] ++ "\n";
    return out;
}

const system_translate_prefix = "#ifndef FOUNDATION_INCHI_SYSTEM_TRANSLATE_H\n" ++
    "#define FOUNDATION_INCHI_SYSTEM_TRANSLATE_H\n";
const system_translate_suffix = "\n#include <inchi_api.h>\n\n#endif\n";

/// Translation header for an installed archive or non-MSVC library.
const system_translate_text_plain = system_translate_prefix ++
    macroDefinesText(core_macros[0..]) ++ system_translate_suffix;

/// Translation header for an installed MSVC DLL.
const system_translate_text_import = system_translate_prefix ++
    macroDefinesText(core_macros[0..]) ++ macroDefinesText(dll_import_macros[0..]) ++
    system_translate_suffix;

/// Generate a translation header for an installed system library.
fn systemTranslateHeader(b: *std.Build, import_declarations: bool) std.Build.LazyPath {
    return b.addWriteFiles().add("inchi_system.h", if (import_declarations)
        system_translate_text_import
    else
        system_translate_text_plain);
}

/// Generate relocatable pkg-config metadata from the target and linkage.
/// Include libm and API macros only where the installed library needs them.
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

/// Install all licence and provenance records.
fn installLicenceRecords(b: *std.Build) void {
    for (licence_records) |record| {
        b.installFile(record.source, b.fmt("share/licenses/inchi/{s}", .{record.installed}));
    }
}

fn parseTriple(b: *std.Build, triple: []const u8) std.Target.Query {
    return std.Build.parseTargetQuery(.{ .arch_os_abi = triple }) catch |err| {
        @panic(b.fmt("build.zig: {s} is not a target triple: {s}", .{ triple, @errorName(err) }));
    };
}

/// Run the consumer package as a nested Zig build with matching options.
/// Forward executor and cache settings so both builds make the same decisions.
fn runConsumer(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    use_system: bool,
    linkage: std.builtin.LinkMode,
    runtime: bool,
) *std.Build.Step.Run {
    const query = target.query;
    // addArg copies arguments, so these temporary strings can be freed.
    const triple = query.zigTriple(b.allocator) catch @panic("OOM");
    defer b.allocator.free(triple);
    const cpu = query.serializeCpuAlloc(b.allocator) catch @panic("OOM");
    defer b.allocator.free(cpu);

    // Use the compiler running this build for the nested build.
    const run = b.addSystemCommand(&.{ b.graph.zig_exe, "build" });
    run.setName("consumer package");
    run.setCwd(b.path(consumer_dir));
    run.addArg(if (hostCanExecute(b, target)) "run" else "install");
    run.addArg(b.fmt("-Dtarget={s}", .{triple}));
    run.addArg(b.fmt("-Dcpu={s}", .{cpu}));
    run.addArg(b.fmt("-Doptimize={s}", .{@tagName(optimize)}));

    run.addArg(b.fmt("-Dlinkage={s}", .{@tagName(linkage)}));

    run.addArg(b.fmt("-Druntime={}", .{runtime}));

    run.addArg(if (use_system) "-fsys=inchi" else "-fno-sys=inchi");

    // Forward the executor settings used by this build.
    if (b.enable_darling) run.addArg("-fdarling");
    if (b.enable_qemu) run.addArg("-fqemu");
    if (b.enable_rosetta) run.addArg("-frosetta");
    if (b.enable_wasmtime) run.addArg("-fwasmtime");
    if (b.enable_wine) run.addArg("-fwine");
    if (b.libc_runtimes_dir) |runtimes| run.addArgs(&.{ "--libc-runtimes", runtimes });

    run.addArg("-j8");
    run.addArgs(&.{ "--summary", "all" });
    // Give the nested build its own cache directory.
    if (b.cache_root.path) |cache| {
        run.addArg("--cache-dir");
        run.addArg(b.fmt("{s}/consumer", .{cache}));
    }
    if (b.graph.global_cache_root.path) |global_cache| {
        run.addArg("--global-cache-dir");
        run.addArg(global_cache);
    }
    // Resolve a caller's relative prefix against the outer build root.
    const default_prefix = b.build_root.join(b.allocator, &.{"zig-out"}) catch @panic("OOM");
    if (!std.mem.eql(u8, b.install_prefix, default_prefix)) {
        const prefix = if (std.fs.path.isAbsolute(b.install_prefix))
            b.install_prefix
        else
            b.pathJoin(&.{ b.graph.cache.cwd, b.install_prefix });
        run.addArg("--prefix");
        run.addArg(prefix);
    }
    // Forward program arguments after `--`.
    if (b.args) |args| {
        run.addArg("--");
        run.addArgs(args);
    }
    run.has_side_effects = true;
    return run;
}

/// Check whether the host has an enabled executor for the target.
/// GNU-libc QEMU runs need `libc_runtimes_dir`.
fn hostCanExecute(b: *std.Build, target: std.Build.ResolvedTarget) bool {
    const host = &b.graph.host.result;
    const candidate = &target.result;
    const options: std.zig.system.GetExternalExecutorOptions = .{
        .allow_darling = b.enable_darling,
        .allow_qemu = b.enable_qemu,
        .allow_wasmtime = b.enable_wasmtime,
        .allow_wine = b.enable_wine,
        // Match Run's libc/runtime requirement for QEMU.
        .qemu_fixes_dl = candidate.isGnuLibC() and b.libc_runtimes_dir != null,
        .link_libc = true,
    };
    return switch (std.zig.system.getExternalExecutor(b.graph.io, host, candidate, options)) {
        .native, .rosetta => true,
        // GNU-libc QEMU needs libc runtimes or Run fails instead of skipping.
        .qemu => !candidate.isGnuLibC() or b.libc_runtimes_dir != null,
        // Only executors enabled above reach this arm.
        .wine, .wasmtime, .darling => true,
        // No dynamic loader or enabled executor exists.
        .bad_dl, .bad_os_or_cpu => false,
    };
}
