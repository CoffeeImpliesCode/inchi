//! SPDX-License-Identifier: LicenseRef-InChI-MIT-Conditional
//! See FORK-LICENSE.md for the full grant and the owner authorization behind it.
//! Runtime-loader contract tests requiring provider paths.

const std = @import("std");
const builtin = @import("builtin");
const inchi = @import("inchi");
const testing = std.testing;

comptime {
    if (!inchi.runtime_loaded) {
        @compileError(
            "runtime/load_tests.zig is the runtime-loading test root. Build it " ++
                "with runtime loading configured; in a linked build there is no " ++
                "loader to test and `load` deliberately stops the program.",
        );
    }
}

/// Environment variable naming a real InChI provider.
const provider_variable = "INCHI_TEST_PROVIDER";
/// Environment variable naming a loadable object without InChI exports.
const alien_variable = "INCHI_TEST_ALIEN";

const absent_path = if (builtin.os.tag == .windows)
    "C:\\inchi-no-such-directory\\inchi.dll"
else
    "/inchi-no-such-directory/libinchi.so";

const Outcome = inchi.LoadError!void;

const Problem = error{
    NoRetainedRequest,
    RequestsWereEqual,
    ProviderDisagreesWithPubChem,
};

/// Copy an environment value into caller storage, or return null if missing or too long.
fn envCopy(buffer: []u8, key: []const u8) ?[]const u8 {
    const value = testing.environ.getAlloc(testing.allocator, key) catch return null;
    defer testing.allocator.free(value);
    if (value.len == 0 or value.len > buffer.len) return null;
    @memcpy(buffer[0..value.len], value);
    return buffer[0..value.len];
}

fn providerPath(buffer: []u8) []const u8 {
    return envCopy(buffer, provider_variable) orelse @panic(
        "runtime/load_tests.zig: " ++ provider_variable ++
            " is not set. These tests load a real provider by path; without one " ++
            "there is nothing to test and passing would mean nothing.",
    );
}

fn alienPath(buffer: []u8) []const u8 {
    return envCopy(buffer, alien_variable) orelse @panic(
        "runtime/load_tests.zig: " ++ alien_variable ++
            " is not set. Point it at any loadable object that is not libinchi; " ++
            "the partial-symbol case needs a file that opens and exports none " ++
            "of the declared entry points.",
    );
}

fn contendOn(path: []const u8, outcome: *Outcome) void {
    outcome.* = inchi.load(.{ .path = path });
}

fn retainedPath() Problem![]const u8 {
    const retained = inchi.loadedSource() orelse return error.NoRetainedRequest;
    return retained.path;
}

test "an empty request is refused before the platform is called" {
    try testing.expectError(error.EmptySource, inchi.load(.{ .path = "" }));
    try testing.expectError(error.EmptySource, inchi.load(.{ .system = "" }));
    try testing.expect(inchi.loadedSource() == null);
}

test "a request longer than the loader will remember is refused" {
    // Refuse truncation because it could load a different provider.
    var buffer: [64 * 1024]u8 = undefined;
    @memset(&buffer, 'x');
    try testing.expectError(
        error.SourceTooLong,
        inchi.load(.{ .path = buffer[0..] }),
    );
    try testing.expect(inchi.loadedSource() == null);
}

test "a file that is not there is refused, and nothing is published" {
    try testing.expectError(error.OpenFailed, inchi.load(.{ .path = absent_path }));
    try testing.expect(inchi.loadedSource() == null);
}

test "a provider that exports none of the header's symbols is refused" {
    var alien: [4096]u8 = undefined;
    const path = alienPath(&alien);
    try testing.expectError(error.MissingSymbol, inchi.load(.{ .path = path }));
    try testing.expect(inchi.loadedSource() == null);
}

test "threads contending on one failing attempt all get that attempt's result" {
    const ThreadCount = 8;
    var alien: [4096]u8 = undefined;
    const path = alienPath(&alien);

    var outcomes: [ThreadCount]Outcome = undefined;
    var threads: [ThreadCount]std.Thread = undefined;
    for (&threads, &outcomes) |*thread, *outcome| {
        thread.* = try std.Thread.spawn(.{}, contendOn, .{ path, outcome });
    }
    for (threads) |thread| thread.join();

    for (outcomes) |outcome| {
        try testing.expectError(error.MissingSymbol, outcome);
    }
    try testing.expect(inchi.loadedSource() == null);
}

test "an explicit retry after a failure succeeds and is retained" {
    var provider: [4096]u8 = undefined;
    const path = providerPath(&provider);
    try inchi.load(.{ .path = path });
    try testing.expectEqualStrings(path, try retainedPath());
}

test "the same request twice succeeds and changes nothing" {
    var provider: [4096]u8 = undefined;
    const path = providerPath(&provider);
    try inchi.load(.{ .path = path });
    try inchi.load(.{ .path = path });
    try testing.expectEqualStrings(path, try retainedPath());
}

test "threads contending after a load all succeed" {
    const ThreadCount = 8;
    var provider: [4096]u8 = undefined;
    const path = providerPath(&provider);

    var outcomes: [ThreadCount]Outcome = undefined;
    var threads: [ThreadCount]std.Thread = undefined;
    for (&threads, &outcomes) |*thread, *outcome| {
        thread.* = try std.Thread.spawn(.{}, contendOn, .{ path, outcome });
    }
    for (threads) |thread| thread.join();

    // Exercise the published-table fast path after load.
    for (outcomes) |outcome| try outcome;
    try testing.expectEqualStrings(path, try retainedPath());
}

test "a different request is refused once a provider is in use" {
    try testing.expectError(
        error.ProviderMismatch,
        inchi.load(.{ .system = "libinchi-not-installed.so" }),
    );
    try testing.expectError(
        error.ProviderMismatch,
        inchi.load(.{ .path = absent_path }),
    );
    const before = try retainedPath();
    try testing.expect(before.len != 0);
}

test "a request that is not the same byte sequence is a different request" {
    var provider: [4096]u8 = undefined;
    const path = providerPath(&provider);
    // Paths are compared byte-for-byte, without normalization.
    var decorated: [4200]u8 = undefined;
    const basename = std.fs.path.basename(path);
    const directory_len = path.len - basename.len;
    const longer = try std.fmt.bufPrint(
        &decorated,
        "{s}.{c}{s}",
        .{ path[0..directory_len], std.fs.path.sep, basename },
    );
    try testing.expect(std.fs.path.isAbsolute(longer));
    if (std.mem.eql(u8, longer, path)) return error.RequestsWereEqual;
    try testing.expectError(error.ProviderMismatch, inchi.load(.{ .path = longer }));
}

test "the loaded library reproduces PubChem's published identifier and key" {
    // Expected values are independent published PubChem results.
    const cases = [_]struct {
        elements: []const []const u8,
        hydrogens: []const i8,
        bonds: []const [2]usize,
        inchi: [:0]const u8,
        key: [:0]const u8,
    }{
        .{
            .elements = &.{"O"},
            .hydrogens = &.{2},
            .bonds = &.{},
            .inchi = "InChI=1S/H2O/h1H2",
            .key = "XLYOFNOQVPJJNP-UHFFFAOYSA-N",
        },
        .{
            .elements = &.{"C"},
            .hydrogens = &.{4},
            .bonds = &.{},
            .inchi = "InChI=1S/CH4/h1H4",
            .key = "VNWKTOKETHGBQD-UHFFFAOYSA-N",
        },
        .{
            .elements = &.{ "C", "C", "O" },
            .hydrogens = &.{ 3, 2, 1 },
            .bonds = &.{ .{ 0, 1 }, .{ 1, 2 } },
            .inchi = "InChI=1S/C2H6O/c1-2-3/h3H,2H2,1H3",
            .key = "LFQSCWFLJHTTHZ-UHFFFAOYSA-N",
        },
    };

    var atoms: [3]inchi.Atom = undefined;
    for (cases) |case| {
        for (case.elements, case.hydrogens, 0..) |element, hydrogens, index| {
            atoms[index] = try inchi.atom(element, .{ .ordinary = hydrogens });
        }
        const slice = atoms[0..case.elements.len];
        for (case.bonds) |bond| {
            try inchi.connect(slice, bond[0], bond[1], .single, .none);
        }

        var output = try inchi.fromMolecule.standard(.{ .atoms = slice });
        defer output.deinit();

        const identifier = output.identifier() orelse
            return error.ProviderDisagreesWithPubChem;
        if (!std.mem.eql(u8, identifier, case.inchi)) {
            std.debug.print(
                "loaded provider: expected {s}, computed {s}\n",
                .{ case.inchi, identifier },
            );
            return error.ProviderDisagreesWithPubChem;
        }
        const computed = try inchi.standardKey(identifier);
        if (!std.mem.eql(u8, computed.keyText(), case.key)) {
            std.debug.print(
                "loaded provider: expected key {s}, computed {s}\n",
                .{ case.key, computed.keyText() },
            );
            return error.ProviderDisagreesWithPubChem;
        }
    }
}
