//! Consumes the `inchi` package the way an outside project would.
//!
//! Everything here goes through the published surface only: `dep.module` in
//! `build.zig`, and `@import("inchi")` here. No path reaches into the
//! library's own tree, so if this builds and produces the answers below, the
//! module contract is real.
//!
//! The answers are PubChem's published identifiers and InChIKeys, so a mismatch
//! is a real fault rather than a restatement of what the library just did. The
//! molecules are built here from element symbols and implicit hydrogen counts
//! because a dependent cannot reach the library's own test fixtures, which is
//! exactly the point: the published module has to be enough on its own.

const std = @import("std");
const inchi = @import("inchi");

/// PubChem CID 962.
const water: Expected = .{ .inchi = "InChI=1S/H2O/h1H2", .key = "XLYOFNOQVPJJNP-UHFFFAOYSA-N" };
/// PubChem CID 297.
const methane: Expected = .{ .inchi = "InChI=1S/CH4/h1H4", .key = "VNWKTOKETHGBQD-UHFFFAOYSA-N" };
/// PubChem CID 702.
const ethanol: Expected = .{ .inchi = "InChI=1S/C2H6O/c1-2-3/h3H,2H2,1H3", .key = "LFQSCWFLJHTTHZ-UHFFFAOYSA-N" };
/// PubChem CID 24602.
const heavy_water: Expected = .{ .inchi = "InChI=1S/H2O/h1H2/i/hD2", .key = "XLYOFNOQVPJJNP-ZSJDYOACSA-N" };

const Expected = struct {
    inchi: [:0]const u8,
    key: [:0]const u8,
};

/// Atom and 0D-stereo storage for one molecule, owned here and borrowed by the
/// `inchi.Molecule` handed to the library.
const Molecule = struct {
    atoms: [8]inchi.Atom = undefined,
    stereo0d: [1]inchi.Stereo0D = undefined,
    atom_count: usize = 0,
    stereo_count: usize = 0,

    fn addAtom(self: *Molecule, element: []const u8, hydrogens: inchi.ImplicitHydrogens) !usize {
        const index = self.atom_count;
        self.atoms[index] = try inchi.atom(element, hydrogens);
        self.atom_count += 1;
        return index;
    }

    fn bond(self: *Molecule, first: usize, second: usize) !void {
        try inchi.connect(self.atoms[0..self.atom_count], first, second, .single, .none);
    }

    fn view(self: *Molecule) inchi.Molecule {
        return .{
            .atoms = self.atoms[0..self.atom_count],
            .stereo0d = self.stereo0d[0..self.stereo_count],
        };
    }
};

pub fn main() !void {
    var threaded: std.Io.Threaded = .init(std.heap.page_allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(io, &buffer);
    const w = &stdout.interface;

    try w.print("inchi consumer\n", .{});

    // One oxygen with two implicit hydrogens.
    {
        var molecule: Molecule = .{};
        _ = try molecule.addAtom("O", .{ .ordinary = 2 });
        try expect(w, "water", molecule.view(), water);
    }
    // One carbon with four implicit hydrogens.
    {
        var molecule: Molecule = .{};
        _ = try molecule.addAtom("C", .{ .ordinary = 4 });
        try expect(w, "methane", molecule.view(), methane);
    }
    // CH3-CH2-OH.
    {
        var molecule: Molecule = .{};
        const methyl = try molecule.addAtom("C", .{ .ordinary = 3 });
        const methylene = try molecule.addAtom("C", .{ .ordinary = 2 });
        const hydroxyl = try molecule.addAtom("O", .{ .ordinary = 1 });
        try molecule.bond(methyl, methylene);
        try molecule.bond(methylene, hydroxyl);
        try expect(w, "ethanol", molecule.view(), ethanol);
    }
    // The same oxygen as water, both hydrogens deuterium.
    {
        var molecule: Molecule = .{};
        _ = try molecule.addAtom("O", .{ .deuterium = 2 });
        try expect(w, "heavy water", molecule.view(), heavy_water);
    }

    // The library's own validation agrees with the answers above, which is what
    // a dependent would check before trusting a key it did not compute.
    try expectVerdict(w, "XLYOFNOQVPJJNP-UHFFFAOYSA-N", inchi.KeyVerdict.standard, inchi.checkKey("XLYOFNOQVPJJNP-UHFFFAOYSA-N"));
    try expectVerdict(w, "InChI=1S/H2O/h1H2", inchi.IdentifierVerdict.standard, inchi.checkIdentifier("InChI=1S/H2O/h1H2", false));

    try w.print("consumer ok\n", .{});
    try w.flush();
}

fn expect(
    w: *std.Io.Writer,
    what: []const u8,
    molecule: inchi.Molecule,
    expected: Expected,
) !void {
    var output = try inchi.fromMolecule.standard(molecule);
    defer output.deinit();

    const identifier = output.identifier() orelse {
        std.debug.print("{s}: no identifier, status {s}, message {s}\n", .{
            what, @tagName(output.status), output.message(),
        });
        return error.ConsumerCheckFailed;
    };
    const computed = try inchi.key(identifier, .{});
    try w.print("{s} = {s} {s}\n", .{ what, identifier, computed.keyText() });

    if (output.status != .okay) {
        std.debug.print("{s}: status {s}, message {s}\n", .{ what, @tagName(output.status), output.message() });
        return error.ConsumerCheckFailed;
    }
    if (!std.mem.eql(u8, identifier, expected.inchi)) {
        std.debug.print("{s}: wanted {s}, got {s}\n", .{ what, expected.inchi, identifier });
        return error.ConsumerCheckFailed;
    }
    if (!std.mem.eql(u8, computed.keyText(), expected.key)) {
        std.debug.print("{s}: wanted key {s}, got {s}\n", .{ what, expected.key, computed.keyText() });
        return error.ConsumerCheckFailed;
    }
}

fn expectVerdict(w: *std.Io.Writer, what: []const u8, want: anytype, got: anytype) !void {
    try w.print("check {s} = {s}\n", .{ what, @tagName(got) });
    if (got != want) {
        std.debug.print("{s}: wanted {s}, got {s}\n", .{ what, @tagName(want), @tagName(got) });
        return error.ConsumerCheckFailed;
    }
}
