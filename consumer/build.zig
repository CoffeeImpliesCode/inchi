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
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const dep = b.dependency("inchi", .{
        .target = target,
        .optimize = optimize,
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
    const run_step = b.step("run", "Build and run the consumer program");
    run_step.dependOn(&run_exe.step);
}
