// SPDX-License-Identifier: LicenseRef-InChI-MIT-Conditional
// See FORK-LICENSE.md for the full grant and the owner authorization behind it.

const std = @import("std");

/// Build a dependent-package example using only `dep.module("inchi")`.
/// Its run step checks published results in linked and runtime-loading modes.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    // Forward dependency linkage options so the nested build uses this mode.
    const linkage = b.option(
        std.builtin.LinkMode,
        "linkage",
        "Link the libinchi artifact statically (default) or dynamically",
    ) orelse .static;
    // Forward runtime loading so the consumer matches the dependency mode.
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

    // The library module declares its own libc requirement.
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
    if (b.args) |args| run_exe.addArgs(args);
    const run_step = b.step("run", "Build and run the consumer program");
    run_step.dependOn(&run_exe.step);

}
