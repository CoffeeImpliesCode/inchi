//! SPDX-License-Identifier: LicenseRef-InChI-MIT-Conditional
//! See FORK-LICENSE.md for the full grant and the owner authorization behind it.
//! External-package example for the published `inchi` module.

const std = @import("std");
const inchi = @import("inchi");

const water: Expected = .{ .inchi = "InChI=1S/H2O/h1H2", .key = "XLYOFNOQVPJJNP-UHFFFAOYSA-N" };
const methane: Expected = .{ .inchi = "InChI=1S/CH4/h1H4", .key = "VNWKTOKETHGBQD-UHFFFAOYSA-N" };
const ethanol: Expected = .{ .inchi = "InChI=1S/C2H6O/c1-2-3/h3H,2H2,1H3", .key = "LFQSCWFLJHTTHZ-UHFFFAOYSA-N" };
const benzene: Expected = .{ .inchi = "InChI=1S/C6H6/c1-2-4-6-5-3-1/h1-6H", .key = "UHOVQNZJYSORNB-UHFFFAOYSA-N" };
const heavy_water: Expected = .{ .inchi = "InChI=1S/H2O/h1H2/i/hD2", .key = "XLYOFNOQVPJJNP-ZSJDYOACSA-N" };

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

/// Own atom and stereo storage borrowed by library calls.
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

    /// Borrow mutable atoms for `GetINCHIEx`, which may rewrite element names.
    fn extendedView(self: *Molecule) inchi.ExtendedMolecule {
        return .{ .atoms = self.atoms[0..self.atom_count] };
    }
};

const ConfigurationError = error{NoProviderConfigured};

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(io, &buffer);
    const w = &stdout.interface;

    // Runtime mode loads its configured provider before calling the API.
    if (comptime inchi.runtime_loaded) {
        try inchi.load(.{ .path = try providerRequest(init) });
    }

    try w.print("inchi consumer\n", .{});
    try w.print("{s}\n", .{
        if (inchi.runtime_loaded) "runtime-loaded provider" else "linked library",
    });

    var water_molecule: Molecule = .{};
    var ethanol_molecule: Molecule = .{};

    _ = try water_molecule.addAtom("O", .{ .ordinary = 2 });
    try expect(w, "water", water_molecule.view(), water);
    {
        var molecule: Molecule = .{};
        _ = try molecule.addAtom("C", .{ .ordinary = 4 });
        try expect(w, "methane", molecule.view(), methane);
    }
    {
        const methyl = try ethanol_molecule.addAtom("C", .{ .ordinary = 3 });
        const methylene = try ethanol_molecule.addAtom("C", .{ .ordinary = 2 });
        const hydroxyl = try ethanol_molecule.addAtom("O", .{ .ordinary = 1 });
        try ethanol_molecule.bond(methyl, methylene);
        try ethanol_molecule.bond(methylene, hydroxyl);
        try expect(w, "ethanol", ethanol_molecule.view(), ethanol);
    }
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
    {
        var molecule: Molecule = .{};
        _ = try molecule.addAtom("O", .{ .deuterium = 2 });
        try expect(w, "heavy water", molecule.view(), heavy_water);
    }

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

    try expectVerdict(w, "XLYOFNOQVPJJNP-UHFFFAOYSA-N", inchi.KeyVerdict.standard, inchi.checkKey("XLYOFNOQVPJJNP-UHFFFAOYSA-N"));
    try expectVerdict(w, "InChI=1S/H2O/h1H2", inchi.IdentifierVerdict.standard, inchi.checkIdentifier("InChI=1S/H2O/h1H2", false));

    try w.print("consumer ok\n", .{});
    try w.flush();
}

/// Return the configured provider path, or `NoProviderConfigured`.
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
