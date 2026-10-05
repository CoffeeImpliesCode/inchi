//! SPDX-License-Identifier: LicenseRef-InChI-MIT-Conditional
//! See FORK-LICENSE.md for the full grant and the owner authorization behind it.
//
//! Behavioural tests for the runtime loader.
//!
//! ## What these tests are about
//!
//! The loader's contract is mostly about what happens *between* calls: a
//! failure that publishes nothing, a retry that is the caller's to make, a
//! second request for the provider already in use, a dozen threads arriving at
//! one attempt. None of that is observable from a single call, which is why
//! this is a separate test root instead of more cases in `tests.zig`.
//!
//! ## Real providers, no mock
//!
//! Every provider here is a real library that exists on the machine:
//!
//!   * `INCHI_TEST_PROVIDER` -- a shared object exporting the entry points
//!     `translate.h` over `inchi_api.h` declares. Nothing imitates the
//!     library's behaviour, and the answers checked below are PubChem's
//!     published identifiers and InChIKeys.
//!   * `INCHI_TEST_ALIEN` -- a loadable object that is not libinchi at all. It
//!     opens, and it exports none of those entry points, which is exactly the
//!     situation `MissingSymbol` exists for.
//!   * a path under a directory that does not exist, for `OpenFailed`. That one
//!     needs no configuration, because no machine has that directory.
//!
//! Nothing is skipped when a variable is missing. In a runtime-loading build a
//! test that cannot name a provider has nothing to say, and passing anyway
//! would mean nothing at all.
//!
//! ## Order is part of the contract
//!
//! There is one loader per process and no unload, so the first successful load
//! is a one-way door. The tests that need a module which has not loaded yet are
//! above the first successful load, and the test runner runs them in source
//! order. That is a property of the contract under test rather than a
//! convenience: any consumer with this lifecycle has the same constraint.

const std = @import("std");
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

/// A shared object exporting the entry points `inchi_api.h` declares.
const provider_variable = "INCHI_TEST_PROVIDER";
/// A loadable object that is not libinchi: it opens, and exports none of them.
const alien_variable = "INCHI_TEST_ALIEN";

/// No machine has this directory, which is what makes it a real `OpenFailed`
/// rather than a guess about what might be missing.
const absent_path = "/inchi-no-such-directory/libinchi.so";

/// What a thread stores when it comes back from a load.
const Outcome = inchi.LoadError!void;

/// What can be wrong with this file's own expectations.
const Problem = error{
    /// The loader was ready but reported no request, which the contract says
    /// cannot happen.
    NoRetainedRequest,
    /// A request that should have been different from the one in use turned out
    /// to be byte-identical, so the test would not be testing anything.
    RequestsWereEqual,
    /// The loaded provider produced an identifier for a molecule whose
    /// published one is known, and they differ.
    ProviderDisagreesWithPubChem,
};

/// Copy an environment variable into `buffer`, or return null when it is unset.
///
/// The value is copied rather than returned as a slice into the environment,
/// because the loader compares a request against its own retained copy and a
/// caller may hand it any bytes it likes.
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

/// One thread's whole job: load one path and store what came back.
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
    // The loader keeps its own copy of the request and refuses one that does
    // not fit, because a truncated path is a different path.
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
    // The candidate opened. Nothing about it reached the table, so there is
    // still no provider and no request.
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

    // Every one of them waited for the single attempt and received its error.
    // None of them started a competing attempt and none of them saw a different
    // outcome: that is what receiving that attempt's result means.
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

    // The loader is published here, so these take the lock-free path. They
    // still have to agree with each other and with the table.
    for (outcomes) |outcome| try outcome;
    try testing.expectEqualStrings(path, try retainedPath());
}

test "a different request is refused once a provider is in use" {
    // Both spellings are refused, and neither reaches the platform: the
    // provider in use stays in use.
    try testing.expectError(
        error.ProviderMismatch,
        inchi.load(.{ .system = "libinchi-not-installed.so" }),
    );
    try testing.expectError(
        error.ProviderMismatch,
        inchi.load(.{ .path = "/somewhere/else/libinchi.so" }),
    );
    const before = try retainedPath();
    try testing.expect(before.len != 0);
}

test "a request that is not the same byte sequence is a different request" {
    var provider: [4096]u8 = undefined;
    const path = providerPath(&provider);
    // The same file named differently. There is no normalization anywhere in
    // the loader, so this is a different request and is refused.
    var decorated: [4200]u8 = undefined;
    const longer = try std.fmt.bufPrint(&decorated, "./{s}", .{path});
    if (std.mem.eql(u8, longer, path)) return error.RequestsWereEqual;
    try testing.expectError(error.ProviderMismatch, inchi.load(.{ .path = longer }));
}

test "the loaded library reproduces PubChem's published identifier and key" {
    // Independent known answers, the same ones `tests.zig` reads out of
    // `testdata/pubchem_known_answers.tsv`. They are not derived by running
    // this library, so a provider that answers differently fails here rather
    // than agreeing with itself.
    const cases = [_]struct {
        /// The element symbols, in the order PubChem's formula lists them, and
        /// the ordinary implicit-hydrogen count for each. One atom per entry.
        elements: []const []const u8,
        hydrogens: []const i8,
        /// CH3-CH2-OH needs the bonds; the other two are single atoms.
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