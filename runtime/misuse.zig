//! SPDX-License-Identifier: LicenseRef-InChI-MIT-Conditional
//! See FORK-LICENSE.md for the full grant and the owner authorization behind it.
//! Child-process test of pre-load failure, post-load success, and linked-load rejection.

const std = @import("std");
const inchi = @import("inchi");

/// Published InChI for water used as the after-load control.
const water_inchi = "InChI=1S/H2O/h1H2";

const Mode = enum { pre_load, after_load, linked_load };

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    const mode: Mode = if (args.len < 2)
        .pre_load
    else if (std.mem.eql(u8, args[1], "pre-load"))
        .pre_load
    else if (std.mem.eql(u8, args[1], "after-load"))
        .after_load
    else if (std.mem.eql(u8, args[1], "linked-load"))
        .linked_load
    else {
        std.debug.print("misuse: unknown mode '{s}'\n", .{args[1]});
        return error.UnknownMode;
    };

    switch (mode) {
        .pre_load => {
            report("calling fromMolecule.standard() with no provider loaded");
            var atoms = [_]inchi.Atom{try inchi.atom("O", .{ .ordinary = 2 })};
            var output = try inchi.fromMolecule.standard(.{ .atoms = &atoms });
            defer output.deinit();
            std.debug.print("misuse: returned {s}\n", .{output.identifier() orelse "nothing"});
        },
        .after_load => {
            const path = if (args.len > 2) args[2] else "";
            if (path.len == 0) {
                std.debug.print("misuse: after-load needs the provider path\n", .{});
                return error.MissingProvider;
            }
            report("loading a provider");
            try inchi.load(.{ .path = path });
            report("calling fromMolecule.standard() with the provider loaded");
            var atoms = [_]inchi.Atom{try inchi.atom("O", .{ .ordinary = 2 })};
            var output = try inchi.fromMolecule.standard(.{ .atoms = &atoms });
            defer output.deinit();
            const identifier = output.identifier() orelse {
                std.debug.print("misuse: the provider produced no identifier\n", .{});
                return error.NoIdentifier;
            };
            std.debug.print("misuse: {s}\n", .{identifier});
            if (!std.mem.eql(u8, identifier, water_inchi)) {
                std.debug.print("misuse: expected {s}\n", .{water_inchi});
                return error.UnexpectedIdentifier;
            }
        },
        .linked_load => {
            report("calling load() on a linked build");
            inchi.load(.{ .path = "unused" }) catch |err| {
                std.debug.print("misuse: load reported {t}\n", .{err});
                return;
            };
            std.debug.print("misuse: load returned without an error\n", .{});
        },
    }
}

fn report(what: []const u8) void {
    std.debug.print("misuse: {s}\n", .{what});
}
