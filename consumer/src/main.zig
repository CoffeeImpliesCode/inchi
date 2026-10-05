//! SPDX-License-Identifier: LicenseRef-InChI-MIT-Conditional
//! See FORK-LICENSE.md for the full grant and the owner authorization behind it.
//
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
//!
//! The same source builds against a linked package and against a
//! runtime-loaded one. `inchi.runtime_loaded` is a comptime constant, so the
//! difference is one branch and no duplicated program: in the runtime-loaded
//! build the provider is named on the command line (`--provider <path>`) or in
//! `INCHI_TEST_PROVIDER`, loaded once, and the same published answers follow.

const std = @import("std");
const inchi = @import("inchi");

/// PubChem CID 962.
const water: Expected = .{ .inchi = "InChI=1S/H2O/h1H2", .key = "XLYOFNOQVPJJNP-UHFFFAOYSA-N" };
/// PubChem CID 297.
const methane: Expected = .{ .inchi = "InChI=1S/CH4/h1H4", .key = "VNWKTOKETHGBQD-UHFFFAOYSA-N" };
/// PubChem CID 702.
const ethanol: Expected = .{ .inchi = "InChI=1S/C2H6O/c1-2-3/h3H,2H2,1H3", .key = "LFQSCWFLJHTTHZ-UHFFFAOYSA-N" };
/// PubChem CID 241.
const benzene: Expected = .{ .inchi = "InChI=1S/C6H6/c1-2-4-6-5-3-1/h1-6H", .key = "UHOVQNZJYSORNB-UHFFFAOYSA-N" };
/// PubChem CID 24602.
const heavy_water: Expected = .{ .inchi = "InChI=1S/H2O/h1H2/i/hD2", .key = "XLYOFNOQVPJJNP-ZSJDYOACSA-N" };

/// A V2000 CTfile for ethanol, spelled out here so that every byte of the input
/// is next to the published identifier it has to produce.
const ethanol_molfile =
    "ethanol\n" ++
    "  pubchem known answer\n" ++
    "\n" ++
    "  3  2  0  0  0  0  0  0  0  0999 V2000\n" ++
    "    0.0000    0.0000    0.0000 C   0  0  0  0  0  0  0  0  0  0  0  0\n" ++
    "    1.0000    0.0000    0.0000 C   0  0  0  0  0  0  0  0  0  0  0  0\n" ++
    "    2.0000    0.0000    0.0000 O   0  0  0  0  0  0  0  0  0  0  0  0\n" ++
    "  1  2  1  0\n" ++
    "  2  3  1  0\n" ++
    "M  END\n" ++
    "$$$$\n";

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
        return self.bondOf(first, second, .single);
    }

    fn bondOf(self: *Molecule, first: usize, second: usize, kind: inchi.BondType) !void {
        try inchi.connect(self.atoms[0..self.atom_count], first, second, kind, .none);
    }

    fn view(self: *Molecule) inchi.Molecule {
        return .{
            .atoms = self.atoms[0..self.atom_count],
            .stereo0d = self.stereo0d[0..self.stereo_count],
        };
    }

    /// The mutable view `inchi.fromMolecule.extended` needs, because
    /// `GetINCHIEx` rewrites `*` element names in the caller's own storage.
    fn extendedView(self: *Molecule) inchi.ExtendedMolecule {
        return .{ .atoms = self.atoms[0..self.atom_count] };
    }
};

/// A runtime-loading build has no provider until one is named.
const ConfigurationError = error{NoProviderConfigured};

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(io, &buffer);
    const w = &stdout.interface;

    // In a runtime-loading build every call below goes through a table that
    // this one call fills. In a linked build the branch is not analyzed at all.
    if (comptime inchi.runtime_loaded) {
        try inchi.load(.{ .path = try providerRequest(init) });
    }

    try w.print("inchi consumer\n", .{});
    try w.print("{s}\n", .{
        if (inchi.runtime_loaded) "runtime-loaded provider" else "linked library",
    });

    var water_molecule: Molecule = .{};
    var ethanol_molecule: Molecule = .{};

    // One oxygen with two implicit hydrogens.
    _ = try water_molecule.addAtom("O", .{ .ordinary = 2 });
    try expect(w, "water", water_molecule.view(), water);
    // One carbon with four implicit hydrogens.
    {
        var molecule: Molecule = .{};
        _ = try molecule.addAtom("C", .{ .ordinary = 4 });
        try expect(w, "methane", molecule.view(), methane);
    }
    // CH3-CH2-OH, kept for the round trips below.
    {
        const methyl = try ethanol_molecule.addAtom("C", .{ .ordinary = 3 });
        const methylene = try ethanol_molecule.addAtom("C", .{ .ordinary = 2 });
        const hydroxyl = try ethanol_molecule.addAtom("O", .{ .ordinary = 1 });
        try ethanol_molecule.bond(methyl, methylene);
        try ethanol_molecule.bond(methylene, hydroxyl);
        try expect(w, "ethanol", ethanol_molecule.view(), ethanol);
    }
    // A six-membered ring with a double bond on every other edge. All single
    // bonds would be cyclohexane, and a different published answer.
    {
        var molecule: Molecule = .{};
        for (0..6) |_| _ = try molecule.addAtom("C", .{ .ordinary = 1 });
        for (0..6) |index| {
            try molecule.bondOf(
                index,
                (index + 1) % 6,
                if (index % 2 == 0) .double else .single,
            );
        }
        try expect(w, "benzene", molecule.view(), benzene);
    }
    // The same oxygen as water, both hydrogens deuterium.
    {
        var molecule: Molecule = .{};
        _ = try molecule.addAtom("O", .{ .deuterium = 2 });
        try expect(w, "heavy water", molecule.view(), heavy_water);
    }

    // A dependent's first real need is the other direction: an identifier
    // someone else computed, back into a molecule, with the structure released
    // through the matching `Free*`.
    {
        var structure = try inchi.fromIdentifier.standard(water.inchi, null);
        defer structure.deinit();
        if (structure.status != .okay or structure.atoms().len != 1) {
            std.debug.print("water rebuild: status {s}, {d} atoms, {s}\n", .{
                @tagName(structure.status), structure.atoms().len, structure.message(),
            });
            return error.ConsumerCheckFailed;
        }
        var again = try inchi.fromMolecule.standard(.{
            .atoms = structure.atoms(),
            .stereo0d = structure.stereo0d(),
        });
        defer again.deinit();
        try expectString("water regenerated", again.identifier().?, water.inchi);
        const computed = try inchi.standardKey(again.identifier().?);
        try expectString("water key", computed.keyText(), water.key);
    }

    // The auxiliary line that came out with an identifier is enough to rebuild
    // the molecule on its own, which is what a stored `InChI=...` plus
    // `AuxInfo=...` pair is for.
    {
        var output = try inchi.fromMolecule.standard(water_molecule.view());
        defer output.deinit();
        const aux_line = output.auxInfo() orelse {
            std.debug.print("water: no AuxInfo line\n", .{});
            return error.ConsumerCheckFailed;
        };
        try w.print("water aux = {s}\n", .{aux_line});
        var rebuilt = try inchi.fromAuxInfo.standard(aux_line, null, false);
        defer rebuilt.deinit();
        if (rebuilt.status != .okay and rebuilt.status != .warning) {
            std.debug.print("water aux: status {s}, {s}\n", .{
                @tagName(rebuilt.status), rebuilt.parseMessage(),
            });
            return error.ConsumerCheckFailed;
        }
        var again = try inchi.fromMolecule.standard(rebuilt.molecule());
        defer again.deinit();
        try expectString("water from AuxInfo", again.identifier().?, water.inchi);
    }

    // The extended polymer/V3000 input and output, with nothing extra attached:
    // the answer is the published one, and the reader reports no extensions
    // because the identifier described none.
    {
        var output = try inchi.fromMolecule.extended(ethanol_molecule.extendedView());
        defer output.deinit();
        try expectString("ethanol extended", output.identifier().?, ethanol.inchi);

        var structure = try inchi.fromIdentifier.extended(ethanol.inchi, null);
        defer structure.deinit();
        if (structure.status != .okay or
            structure.polymer() != null or
            structure.v3000() != null)
        {
            std.debug.print("ethanol extended read: status {s}, polymer {any}, v3000 {any}\n", .{
                @tagName(structure.status), structure.polymer(), structure.v3000(),
            });
            return error.ConsumerCheckFailed;
        }
        try w.print("ethanol extended rebuild = {d} atoms\n", .{structure.atoms().len});
    }

    // The molfile shortcut needs no molecule from the caller at all.
    {
        var output = try inchi.fromMolfile(ethanol_molfile, null);
        defer output.deinit();
        if (output.status != .okay) {
            std.debug.print("ethanol molfile: status {s}, message {s}\n", .{
                @tagName(output.status), output.message(),
            });
            return error.ConsumerCheckFailed;
        }
        try expectString("ethanol molfile", output.identifier().?, ethanol.inchi);
        const computed = try inchi.standardKey(output.identifier().?);
        try expectString("ethanol molfile key", computed.keyText(), ethanol.key);
    }

    // The library's own validation agrees with the answers above, which is what
    // a dependent would check before trusting a key it did not compute.
    try expectVerdict(w, "XLYOFNOQVPJJNP-UHFFFAOYSA-N", inchi.KeyVerdict.standard, inchi.checkKey("XLYOFNOQVPJJNP-UHFFFAOYSA-N"));
    try expectVerdict(w, "InChI=1S/H2O/h1H2", inchi.IdentifierVerdict.standard, inchi.checkIdentifier("InChI=1S/H2O/h1H2", false));

    try w.print("consumer ok\n", .{});
    try w.flush();
}

/// The provider this run should load, from `--provider <path>` or from
/// `INCHI_TEST_PROVIDER`.
///
/// Both are explicit. Nothing here looks in a default location, and a build
/// that was not told which file to load says so rather than loading something
/// else.
fn providerRequest(init: std.process.Init) ConfigurationError![]const u8 {
    const args = init.minimal.args.toSlice(init.arena.allocator()) catch
        return noProvider();
    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        if (std.mem.eql(u8, args[index], "--provider")) {
            if (index + 1 >= args.len) return noProvider();
            return args[index + 1];
        }
    }
    return init.environ_map.get("INCHI_TEST_PROVIDER") orelse
        return noProvider();
}

/// Say which variable is missing. An error name on its own would send the next
/// person into the loader instead of to the command line.
fn noProvider() ConfigurationError {
    std.debug.print(
        "consumer: this is a runtime-loading build. Pass --provider <path>, or " ++
            "export INCHI_TEST_PROVIDER with a shared object exporting the entry " ++
            "points of INCHI-1-SRC/INCHI_BASE/src/inchi_api.h (and, through it, " ++
            "ixa.h). Nothing is loaded by default and no other file is tried.\n",
        .{},
    );
    return error.NoProviderConfigured;
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
    try expectString(what, identifier, expected.inchi);
    try expectString(what, computed.keyText(), expected.key);
}

/// Compare one answer with the published one and say so when they differ.
fn expectString(what: []const u8, got: [:0]const u8, want: [:0]const u8) !void {
    if (!std.mem.eql(u8, got, want)) {
        std.debug.print("{s}: wanted {s}, got {s}\n", .{ what, want, got });
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