// SPDX-License-Identifier: LicenseRef-InChI-MIT-Conditional
// See FORK-LICENSE.md for the full grant and the owner authorization behind it.

const std = @import("std");

/// A package that consumes `inchi` from outside.
///
/// This exists to prove one thing: that a dependent needs only
/// `dep.module("inchi")` and gets a working, correctly linked library. If the
/// facade module stopped carrying its C artifact, or the translated header
/// stopped matching the C sources, this would stop building or stop producing
/// the identifiers below, and nothing inside the library would notice.
///
/// Run it with `zig build run`. It exits non-zero if an identifier or a key
/// disagrees with the answer PubChem publishes for that compound, so this is a
/// check and not a demo.
///
/// `-Dlinkage=static|dynamic` is forwarded from the parent package's `consumer`
/// step and selects which kind of libinchi this proves: the default static
/// archive, or the shared library.
///
/// `-Druntime=true|false` is forwarded the same way. Under it this program
/// reaches libinchi through the platform loader rather than through a link, and
/// names the provider itself: `--provider <path>` on the command line, or
/// `INCHI_TEST_PROVIDER` in the environment. Nothing is loaded by default and no
/// other file is tried, so a runtime build with neither set says so and exits
/// non-zero rather than quietly falling back to a linked library.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    // The library's `-Dlinkage`, read here for the same reason it is forwarded:
    // this package configures the library as a path dependency, and a dependency
    // option has to be named in the `b.dependency` call that builds it. Without
    // it the nested graph would resolve its own default and could build the
    // static artifact while the outer graph built the shared one.
    const linkage = b.option(
        std.builtin.LinkMode,
        "linkage",
        "Link the libinchi artifact statically (default) or dynamically",
    ) orelse .static;
    // The library's `-Druntime`, forwarded for the same reason as the linkage
    // above and read from this package's own options so it can be passed to
    // `b.dependency`. Without it, `-Druntime=true` would reach this build and
    // stop here, and the consumer would prove a linked library under a name that
    // says it proved a runtime one.
    const runtime = b.option(
        bool,
        "runtime",
        "Resolve libinchi's symbols at run time through the platform loader " ++
            "instead of linking the artifact into the facade (default false)",
    ) orelse false;
    const dep = b.dependency("inchi", .{
        .target = target,
        .optimize = optimize,
        .linkage = linkage,
        .runtime = runtime,
    });

    // No `link_libc` here on purpose. The C requirement belongs to the library
    // module, which carries it; a dependent states its own, and this program
    // needs nothing beyond what the library already brings. Adding it would
    // hide a library that forgot to declare it.
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("inchi", dep.module("inchi"));

    const exe = b.addExecutable(.{
        .name = "inchi-consumer",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    // Arguments reach the program. `--provider <path>` is how a runtime build
    // names its provider, and without this the only way to give it one would be
    // the environment variable — which would make the documented command line
    // silently do nothing.
    if (b.args) |args| run_exe.addArgs(args);
    const run_step = b.step("run", "Build and run the consumer program");
    run_step.dependOn(&run_exe.step);

}
