//! SPDX-License-Identifier: LicenseRef-InChI-MIT-Conditional
//! See FORK-LICENSE.md for the full grant and the owner authorization behind it.
//! Tests compare facade results with PubChem identifiers and keys recorded in
//! `testdata/pubchem_known_answers.tsv`; round trips are supplementary checks.
//! Coverage includes stereo pairs, conversions, AuxInfo, molfiles, and extended data.

const std = @import("std");
const builtin = @import("builtin");
const inchi = @import("inchi");
const molecules = @import("zig/molecules.zig");
const testing = std.testing;

/// Load the explicit test provider once. Linked tests need no startup call.
fn nativeReady() void {
    if (comptime !inchi.runtime_loaded) return;
    if (inchi.loadedSource() != null) return;
    const path = testing.environ.getAlloc(testing.allocator, "INCHI_TEST_PROVIDER") catch
        @panic("Set INCHI_TEST_PROVIDER before running runtime-loaded tests");
    defer testing.allocator.free(path);
    inchi.load(.{ .path = path }) catch |err| {
        std.debug.print("INCHI_TEST_PROVIDER \"{s}\": {s}\n", .{ path, @errorName(err) });
        @panic("The explicit InChI test provider could not load");
    };
}

/// PubChem's published answers, embedded so no test needs a file system.
const fixture_text = @embedFile("testdata/pubchem_known_answers.tsv");

/// Makes a sentinel slice whose length excludes the appended terminator.
fn terminated(comptime value: []const u8) [:0]const u8 {
    return (value ++ "\x00")[0..value.len :0];
}

const Compound = struct {
    name: []const u8,
    cid: []const u8,
    formula: []const u8,
    identifier: [:0]const u8,
    key: [:0]const u8,
};

/// Compile-time parsed records with static lifetime.
const compounds = blk: {
    @setEvalBranchQuota(10_000);
    var list: [16]Compound = undefined;
    var count: usize = 0;
    var lines = std.mem.splitScalar(u8, fixture_text, '\n');
    while (lines.next()) |line| {
        if (line.len == 0 or line[0] == '#' or std.mem.startsWith(u8, line, "name\t")) continue;
        var fields = std.mem.splitScalar(u8, line, '\t');
        list[count] = .{
            .name = fields.next().?,
            .cid = fields.next().?,
            .formula = fields.next().?,
            .identifier = terminated(fields.next().?),
            .key = terminated(fields.next().?),
        };
        count += 1;
    }
    break :blk list[0..count].*;
};

/// Returns the published compound for a fixture key; a missing key fails loudly.
fn compound(name: []const u8) Compound {
    for (compounds) |entry| {
        if (std.mem.eql(u8, entry.name, name)) return entry;
    }
    @panic("known-answer compound is missing from testdata/pubchem_known_answers.tsv");
}

/// L-alanine identifier without the standard `S` prefix.
const non_standard_l_alanine: [:0]const u8 = blk: {
    const standard = compound("l_alanine").identifier;
    // Concatenation preserves the published identifier's sentinel boundary.
    break :blk "InChI=1/" ++ standard[9..];
};

/// Requires the two published identifiers and their keys, in either order.
fn expectPublishedPair(results: [2][:0]const u8, answers: [2]Compound) !void {
    var matched = [2]bool{ false, false };
    for (results) |got| {
        var hit = false;
        for (answers, 0..) |want, index| {
            if (!std.mem.eql(u8, got, want.identifier)) continue;
            try testing.expect(!matched[index]);
            matched[index] = true;
            hit = true;
            const computed = try inchi.key(want.identifier, .{});
            try testing.expectEqualStrings(want.key, computed.keyText());
            try testing.expectEqual(inchi.KeyVerdict.standard, inchi.checkKey(computed.keyText()));
        }
        try testing.expect(hit);
    }
    try testing.expect(matched[0] and matched[1]);
}

fn elementOf(atom: *const inchi.Atom) []const u8 {
    return std.mem.sliceTo(&atom.elname, 0);
}

/// Atom counts plus implicit hydrogens.
const Composition = struct {
    carbons: usize = 0,
    nitrogens: usize = 0,
    oxygens: usize = 0,
    hydrogens: usize = 0,
    implicit_hydrogens: usize = 0,
};

/// Counts atoms and implicit hydrogens; unknown elements fail the test.
fn composition(atoms: []const inchi.Atom) !Composition {
    var result: Composition = .{};
    for (atoms) |*atom| {
        const element = elementOf(atom);
        if (std.mem.eql(u8, element, "C")) {
            result.carbons += 1;
        } else if (std.mem.eql(u8, element, "N")) {
            result.nitrogens += 1;
        } else if (std.mem.eql(u8, element, "O")) {
            result.oxygens += 1;
        } else if (std.mem.eql(u8, element, "H")) {
            result.hydrogens += 1;
        } else {
            return error.UnexpectedElement;
        }
        result.implicit_hydrogens += @intCast(@max(atom.num_iso_H[0], 0));
    }
    return result;
}

/// Splits an InChIKey into its skeleton and remaining hash blocks.
fn keyBlocks(text: []const u8) [2][]const u8 {
    const first = std.mem.findScalar(u8, text, '-') orelse return .{ text, text };
    const second = std.mem.findScalarPos(u8, text, first + 1, '-') orelse return .{ text[0..first], text[first + 1 ..] };
    return .{ text[0..first], text[first + 1 .. second] };
}

test "water built from one oxygen matches the identifier and key PubChem publishes" {
    nativeReady();
    const expected = compound("water");

    var scratch: molecules.Scratch = .{};
    var output = try inchi.fromMolecule.standard(try molecules.water(&scratch));
    defer output.deinit();

    try testing.expectEqual(inchi.Status.okay, output.status);
    try testing.expect(!output.isWarning());
    try testing.expectEqualStrings(expected.identifier, output.identifier().?);
    try testing.expectEqualStrings("", output.message());

    const computed = try inchi.key(expected.identifier, .{});
    try testing.expectEqualStrings(expected.key, computed.keyText());
    try testing.expectEqual(inchi.KeyVerdict.standard, inchi.checkKey(computed.keyText()));
    try testing.expectEqual(inchi.IdentifierVerdict.standard, inchi.checkIdentifier(expected.identifier, false));
    // Strict checking regenerates with Fixed-H/Reconnected options, so a valid standard ID can fail conversion.
    try testing.expectEqual(inchi.IdentifierVerdict.conversion_failed, inchi.checkIdentifier(expected.identifier, true));
}

test "methane built from one carbon matches the identifier and key PubChem publishes" {
    nativeReady();
    const expected = compound("methane");

    var scratch: molecules.Scratch = .{};
    var output = try inchi.fromMolecule.standard(try molecules.methane(&scratch));
    defer output.deinit();

    try testing.expectEqual(inchi.Status.okay, output.status);
    try testing.expectEqualStrings(expected.identifier, output.identifier().?);

    // Standard-key conversion rejects non-standard identifiers and omits extension hashes.
    const computed = try inchi.standardKey(output.identifier().?);
    try testing.expectEqualStrings(expected.key, computed.keyText());
    try testing.expectEqual(@as(?[:0]const u8, null), computed.firstHash());
    try testing.expectEqual(@as(?[:0]const u8, null), computed.secondHash());
}

test "ethanol: the non-standard entry point agrees, and /AuxNone leaves the identifier alone" {
    nativeReady();
    const expected = compound("ethanol");

    var scratch: molecules.Scratch = .{};
    const ethanol = try molecules.ethanol(&scratch);

    var standard = try inchi.fromMolecule.standard(ethanol);
    defer standard.deinit();
    try testing.expectEqualStrings(expected.identifier, standard.identifier().?);

    var full = try inchi.fromMolecule.full(ethanol);
    defer full.deinit();
    try testing.expectEqual(inchi.Status.okay, full.status);
    try testing.expectEqualStrings(expected.identifier, full.identifier().?);

    // `/AuxNone` does not change the identifier.
    var without_aux = try inchi.fromMolecule.full(.{
        .atoms = ethanol.atoms,
        .stereo0d = ethanol.stereo0d,
        .options = molecules.no_aux_options,
    });
    defer without_aux.deinit();
    try testing.expectEqualStrings(expected.identifier, without_aux.identifier().?);
}

test "benzene and glycine match the identifiers PubChem publishes" {
    nativeReady();
    var scratch: molecules.Scratch = .{};

    var benzene = try inchi.fromMolecule.standard(try molecules.benzene(&scratch));
    defer benzene.deinit();
    try testing.expectEqual(inchi.Status.okay, benzene.status);
    try testing.expectEqualStrings(compound("benzene").identifier, benzene.identifier().?);

    var glycine = try inchi.fromMolecule.standard(try molecules.glycine(&scratch));
    defer glycine.deinit();
    try testing.expectEqual(inchi.Status.okay, glycine.status);
    try testing.expectEqualStrings(compound("glycine").identifier, glycine.identifier().?);
}

test "glycine's zwitterion warns about the protons it moved and still yields glycine" {
    nativeReady();
    const expected = compound("glycine");

    var scratch: molecules.Scratch = .{};

    var neutral = try inchi.fromMolecule.standard(try molecules.glycine(&scratch));
    defer neutral.deinit();
    var zwitterion = try inchi.fromMolecule.standard(try molecules.glycineZwitterion(&scratch));
    defer zwitterion.deinit();

    // The zwitterion is normalized to glycine and reported as a warning.
    try testing.expectEqual(inchi.Status.okay, neutral.status);
    try testing.expect(!neutral.isWarning());
    try testing.expectEqual(inchi.Status.warning, zwitterion.status);
    try testing.expect(zwitterion.isWarning());
    try testing.expectEqualStrings(expected.identifier, zwitterion.identifier().?);
    try testing.expectEqualStrings(neutral.identifier().?, zwitterion.identifier().?);

    try testing.expectEqualStrings("", neutral.message());
}

test "renumbering the atoms of ethanol and benzene changes nothing" {
    nativeReady();
    var scratch: molecules.Scratch = .{};

    var ethanol = try inchi.fromMolecule.standard(try molecules.ethanol(&scratch));
    defer ethanol.deinit();
    var renumbered_ethanol = try inchi.fromMolecule.standard(try molecules.ethanolRenumbered(&scratch));
    defer renumbered_ethanol.deinit();
    try testing.expectEqualStrings(ethanol.identifier().?, renumbered_ethanol.identifier().?);
    // Confirm canonicalization matches the published answer.
    try testing.expectEqualStrings(compound("ethanol").identifier, renumbered_ethanol.identifier().?);

    var benzene = try inchi.fromMolecule.standard(try molecules.benzene(&scratch));
    defer benzene.deinit();
    var renumbered_benzene = try inchi.fromMolecule.standard(try molecules.benzeneRenumbered(&scratch));
    defer renumbered_benzene.deinit();
    try testing.expectEqualStrings(benzene.identifier().?, renumbered_benzene.identifier().?);
    try testing.expectEqualStrings(compound("benzene").identifier, renumbered_benzene.identifier().?);
}

test "the tetrahedral 0D parity separates alanine into the two enantiomers PubChem publishes" {
    nativeReady();
    var scratch: molecules.Scratch = .{};

    var even = try inchi.fromMolecule.standard(try molecules.alanine(&scratch, .even));
    defer even.deinit();
    var odd = try inchi.fromMolecule.standard(try molecules.alanine(&scratch, .odd));
    defer odd.deinit();

    try testing.expectEqual(inchi.Status.okay, even.status);
    try testing.expectEqual(inchi.Status.okay, odd.status);
    try testing.expect(!std.mem.eql(u8, even.identifier().?, odd.identifier().?));
    try expectPublishedPair(
        .{ even.identifier().?, odd.identifier().? },
        .{ compound("l_alanine"), compound("d_alanine") },
    );
}

test "the structure upstream rebuilds from L-alanine regenerates L-alanine" {
    nativeReady();
    const expected = compound("l_alanine");

    var structure = try inchi.fromIdentifier.standard(expected.identifier, null);
    defer structure.deinit();

    try testing.expectEqual(inchi.Status.okay, structure.status);
    try testing.expect(!structure.isWarning());
    // The rebuild preserves every layer and reports no differences.
    for (structure.warnings()) |row| for (row) |flag| {
        try testing.expectEqual(@as(c_ulong, 0), flag);
    };

    // Tetrahedral parity requires the stereocentre's hydrogen as an explicit atom.
    const atoms = structure.atoms();
    const made = try composition(atoms);
    try testing.expectEqual(@as(usize, 3), made.carbons);
    try testing.expectEqual(@as(usize, 1), made.nitrogens);
    try testing.expectEqual(@as(usize, 2), made.oxygens);
    try testing.expectEqual(@as(usize, 1), made.hydrogens);
    try testing.expectEqual(@as(usize, 6), made.implicit_hydrogens);

    const stereo = structure.stereo0d();
    try testing.expectEqual(@as(usize, 1), stereo.len);
    try testing.expectEqual(inchi.StereoType0D.tetrahedral, @as(inchi.StereoType0D, @enumFromInt(stereo[0].type)));

    // The alpha carbon's four neighbors include the explicit hydrogen.
    const centre: usize = @intCast(stereo[0].central_atom);
    try testing.expectEqualStrings("C", elementOf(&atoms[centre]));
    try testing.expect(atoms[centre].num_iso_H[0] == 0);
    var hydrogen: usize = 0;
    for (atoms, 0..) |*atom, index| {
        if (std.mem.eql(u8, elementOf(atom), "H")) hydrogen = index;
    }
    const bonds = atoms[centre].neighbor[0..@intCast(atoms[centre].num_bonds)];
    try testing.expect(std.mem.findScalar(c_short, bonds, @intCast(hydrogen)) != null);

    // `GetStdINCHI` reads these rebuilt arrays without modifying them.
    var regenerated = try inchi.fromMolecule.standard(.{
        .atoms = atoms,
        .stereo0d = stereo,
    });
    defer regenerated.deinit();
    try testing.expectEqual(inchi.Status.okay, regenerated.status);
    try testing.expectEqualStrings(expected.identifier, regenerated.identifier().?);
}

test "isotopic hydrogens put water and heavy water in different classes" {
    nativeReady();
    const light = compound("water");
    const heavy = compound("heavy_water");

    var scratch: molecules.Scratch = .{};
    var ordinary = try inchi.fromMolecule.standard(try molecules.water(&scratch));
    defer ordinary.deinit();
    var labelled = try inchi.fromMolecule.standard(try molecules.heavyWater(&scratch));
    defer labelled.deinit();

    try testing.expectEqualStrings(light.identifier, ordinary.identifier().?);
    try testing.expectEqualStrings(heavy.identifier, labelled.identifier().?);
    try testing.expect(!std.mem.eql(u8, ordinary.identifier().?, labelled.identifier().?));

    // The isotope layer changes the first two InChIKey blocks, not connectivity.
    try testing.expect(std.mem.startsWith(u8, labelled.identifier().?, "InChI=1S/H2O/h1H2/i/hD2"));
    const light_key = try inchi.key(ordinary.identifier().?, .{});
    const heavy_key = try inchi.key(labelled.identifier().?, .{});
    try testing.expectEqualStrings(light.key, light_key.keyText());
    try testing.expectEqualStrings(heavy.key, heavy_key.keyText());
    const light_blocks = keyBlocks(light_key.keyText());
    const heavy_blocks = keyBlocks(heavy_key.keyText());
    try testing.expectEqualStrings(light_blocks[0], heavy_blocks[0]);
    try testing.expect(!std.mem.eql(u8, light_blocks[1], heavy_blocks[1]));
}

test "the stereobond 0D parity separates but-2-ene into the two isomers PubChem publishes" {
    nativeReady();
    var scratch: molecules.Scratch = .{};

    var even = try inchi.fromMolecule.standard(try molecules.but2ene(&scratch, .even));
    defer even.deinit();
    var odd = try inchi.fromMolecule.standard(try molecules.but2ene(&scratch, .odd));
    defer odd.deinit();

    try testing.expectEqual(inchi.Status.okay, even.status);
    try testing.expectEqual(inchi.Status.okay, odd.status);
    try testing.expect(!std.mem.eql(u8, even.identifier().?, odd.identifier().?));
    try expectPublishedPair(
        .{ even.identifier().?, odd.identifier().? },
        .{ compound("e_but2ene"), compound("z_but2ene") },
    );
}

test "regenerating a published identifier reproduces it exactly" {
    nativeReady();
    // No options preserves every layer; the expected result is PubChem's published identifier.
    for ([_][]const u8{
        "water", "methane", "ethanol", "benzene", "glycine", "l_alanine", "heavy_water",
    }) |name| {
        const expected = compound(name);
        var regenerated = try inchi.fromIdentifier.converted(expected.identifier, null);
        defer regenerated.deinit();
        try testing.expectEqual(inchi.Status.okay, regenerated.status);
        try testing.expectEqualStrings(expected.identifier, regenerated.identifier().?);
    }
}

test "the layer-keeping option string is what makes the conversion non-standard" {
    nativeReady();
    const water = compound("water").identifier;

    // Keeping Fixed-H and Reconnected layers converts this standard identifier to non-standard.
    var with_layers = try inchi.fromIdentifier.converted(water, molecules.strict_options);
    defer with_layers.deinit();
    try testing.expectEqual(inchi.Status.okay, with_layers.status);
    try testing.expectEqualStrings("InChI=1/H2O/h1H2", with_layers.identifier().?);
    try testing.expectEqual(inchi.IdentifierVerdict.non_standard, inchi.checkIdentifier(with_layers.identifier().?, false));

    // No options preserves the standard identifier.
    var without_layers = try inchi.fromIdentifier.converted(water, null);
    defer without_layers.deinit();
    try testing.expectEqual(inchi.Status.okay, without_layers.status);
    try testing.expectEqualStrings(water, without_layers.identifier().?);
}

test "a non-standard identifier is accepted by the general reader and refused by the standard one" {
    nativeReady();
    try testing.expectEqual(
        inchi.IdentifierVerdict.non_standard,
        inchi.checkIdentifier(non_standard_l_alanine, false),
    );

    // The standard-only reader rejects `1/...` before writing output; empty accessors must be safe.
    var refused = try inchi.fromIdentifier.standard(non_standard_l_alanine, null);
    defer refused.deinit();
    try testing.expectEqual(inchi.Status.rejected, refused.status);
    try testing.expectEqual(@as(usize, 0), refused.atoms().len);
    try testing.expectEqual(@as(usize, 0), refused.stereo0d().len);
    try testing.expectEqualStrings("", refused.message());
    try testing.expectEqualStrings("", refused.log());

    // The general reader accepts the same identifier and rebuilds its explicit stereocentre hydrogen.
    var accepted = try inchi.fromIdentifier.full(non_standard_l_alanine, null);
    defer accepted.deinit();
    try testing.expectEqual(inchi.Status.okay, accepted.status);
    const rebuilt = try composition(accepted.atoms());
    try testing.expectEqual(@as(usize, 3), rebuilt.carbons);
    try testing.expectEqual(@as(usize, 1), rebuilt.nitrogens);
    try testing.expectEqual(@as(usize, 2), rebuilt.oxygens);
    try testing.expectEqual(@as(usize, 1), rebuilt.hydrogens);

    // Only `standardKey` rejects a non-standard identifier.
    try testing.expectError(error.InvalidStdInchi, inchi.standardKey(non_standard_l_alanine));
    const non_standard_key = try inchi.key(non_standard_l_alanine, .{});
    const non_standard_verdict = inchi.checkKey(non_standard_key.keyText());
    try testing.expectEqual(inchi.KeyVerdict.non_standard, non_standard_verdict);
    // Preserve the upstream numeric verdict, not only its enum tag.
    try testing.expectEqual(@as(c_int, -1), @intFromEnum(non_standard_verdict));
}

test "malformed identifiers and keys are reported as upstream reports them" {
    nativeReady();
    try testing.expectEqual(inchi.IdentifierVerdict.invalid_prefix, inchi.checkIdentifier("not an identifier", false));
    try testing.expectEqual(inchi.IdentifierVerdict.invalid_prefix, inchi.checkIdentifier("InChI=1", false));
    try testing.expectEqual(inchi.IdentifierVerdict.invalid_version, inchi.checkIdentifier("InChI=9S/H2O/h1H2", false));
    try testing.expectEqual(inchi.IdentifierVerdict.invalid_layout, inchi.checkIdentifier("InChI=1SX", false));

    try testing.expectError(error.InvalidInchiPrefix, inchi.key("", .{}));
    try testing.expectError(error.InvalidInchiPrefix, inchi.key("InChI=1", .{}));
    try testing.expectError(error.InvalidStdInchi, inchi.standardKey("InChI=1/H2O/h1H2"));

    const standard_verdict = inchi.checkKey(compound("water").key);
    try testing.expectEqual(inchi.KeyVerdict.standard, standard_verdict);
    try testing.expectEqual(@as(c_int, 0), @intFromEnum(standard_verdict));
    const length_verdict = inchi.checkKey("XLYOFNOQVPJJNP-UHFFFAOYSA");
    try testing.expectEqual(inchi.KeyVerdict.invalid_length, length_verdict);
    try testing.expectEqual(@as(c_int, 1), @intFromEnum(length_verdict));
    const layout_verdict = inchi.checkKey("XLYOFNOQVPJJNP-UHFFFAOYSA-n");
    try testing.expectEqual(inchi.KeyVerdict.invalid_layout, layout_verdict);
    try testing.expectEqual(@as(c_int, 2), @intFromEnum(layout_verdict));
    // The final character is the protonation flag, so this key has an invalid version, not layout.
    const version_verdict = inchi.checkKey("XLYOFNOQVPJJNP-UHFFFAOYSS-B");
    try testing.expectEqual(inchi.KeyVerdict.invalid_version, version_verdict);
    try testing.expectEqual(@as(c_int, 3), @intFromEnum(version_verdict));

    // The general reader reports no data for malformed input.
    var refused = try inchi.fromIdentifier.full("InChI=1SX", null);
    defer refused.deinit();
    try testing.expectEqual(inchi.Status.no_data, refused.status);
    try testing.expectEqual(@as(usize, 0), refused.atoms().len);
}

test "a pseudo-element is refused" {
    nativeReady();
    var scratch: molecules.Scratch = .{};
    const star = try molecules.pseudoAtom(&scratch);

    var output = try inchi.fromMolecule.standard(star);
    defer output.deinit();

    // The classic entry points reject a `*` atom before generation.
    try testing.expectEqual(inchi.Status.rejected, output.status);
    try testing.expectEqual(@as(?[:0]const u8, null), output.identifier());

    var full = try inchi.fromMolecule.full(star);
    defer full.deinit();
    try testing.expectEqual(inchi.Status.rejected, full.status);
}

test "the facade refuses input it cannot pass on faithfully" {
    nativeReady();
    try testing.expectError(error.ElementSymbolTooLong, inchi.atom("Ununbium", .none));

    var scratch: molecules.Scratch = .{};
    _ = try molecules.ethanol(&scratch);
    const filled = scratch.atoms[0..scratch.atom_count];
    try testing.expectError(error.AtomIndexOutOfRange, inchi.connect(filled, 0, 7, .single, .none));
    try testing.expectError(error.AtomIndexOutOfRange, inchi.connect(filled, 1, 1, .single, .none));

    // `max_bonds_per_atom` is the full adjacency-list capacity.
    var atoms: [2]inchi.Atom = undefined;
    atoms[0] = try inchi.atom("C", .none);
    atoms[1] = try inchi.atom("C", .none);
    var placed: usize = 0;
    while (placed < inchi.max_bonds_per_atom) : (placed += 1) {
        try inchi.connect(atoms[0..], 0, 1, .single, .none);
    }
    try testing.expectError(error.TooManyNeighbors, inchi.connect(atoms[0..], 0, 1, .single, .none));

    // Negative raw counts are representable; `connect` rejects them rather than treating them as empty lists.
    var negative: [2]inchi.Atom = undefined;
    negative[0] = try inchi.atom("C", .none);
    negative[1] = try inchi.atom("C", .none);
    negative[0].num_bonds = -1;
    try testing.expectError(error.TooManyNeighbors, inchi.connect(negative[0..], 0, 1, .single, .none));

    // The second-end check also leaves both counts unchanged.
    negative[0].num_bonds = 0;
    negative[1].num_bonds = -1;
    try testing.expectError(error.TooManyNeighbors, inchi.connect(negative[0..], 0, 1, .single, .none));
    try testing.expectEqual(@as(i16, 0), negative[0].num_bonds);
    try testing.expectEqual(@as(i16, -1), negative[1].num_bonds);
}

test "the AuxInfo line rebuilds each compound PubChem publishes" {
    nativeReady();
    // Compare with published identifiers, not only a self-consistent round trip.
    // Use non-stereo records because AuxInfo parity depends on its atom order.
    for ([_][]const u8{
        "water", "methane", "ethanol", "benzene", "glycine",
    }) |name| {
        const expected = compound(name);

        var scratch: molecules.Scratch = .{};
        var output = try inchi.fromMolecule.standard(if (std.mem.eql(u8, name, "water"))
            try molecules.water(&scratch)
        else if (std.mem.eql(u8, name, "methane"))
            try molecules.methane(&scratch)
        else if (std.mem.eql(u8, name, "ethanol"))
            try molecules.ethanol(&scratch)
        else if (std.mem.eql(u8, name, "benzene"))
            try molecules.benzene(&scratch)
        else
            try molecules.glycine(&scratch));
        defer output.deinit();

        // AuxInfo shares the identifier allocation and is consumed before `output` is released.
        const aux_line = output.auxInfo() orelse {
            std.debug.print("{s}: no AuxInfo line\n", .{name});
            return error.MissingAuxInfo;
        };

        var rebuilt = try inchi.fromAuxInfo.standard(aux_line, null, false);
        defer rebuilt.deinit();
        if (rebuilt.status != .okay and rebuilt.status != .warning) {
            std.debug.print("{s}: AuxInfo read answered {s}: {s}\n", .{
                name, @tagName(rebuilt.status), rebuilt.parseMessage(),
            });
            return error.AuxInfoRefused;
        }

        // Regenerate the published identifier directly from the rebuilt structure.
        var again = try inchi.fromMolecule.standard(rebuilt.molecule());
        defer again.deinit();
        try testing.expectEqualStrings(expected.identifier, again.identifier().?);
    }
}

test "an AuxInfo line that is not one is refused, and leaves nothing to release" {
    nativeReady();
    var refused = try inchi.fromAuxInfo.standard("not an auxiliary line", null, false);
    defer refused.deinit();

    try testing.expect(rejected(refused.status));
    try testing.expectEqual(@as(usize, 0), refused.atoms().len);
    try testing.expectEqual(@as(usize, 0), refused.stereo0d().len);

    // Upstream frees arrays on refusal; the result must still be safe to deinitialize.
    const released_atoms: usize = @intCast(refused.raw.num_atoms);
    try testing.expectEqual(@as(usize, 0), released_atoms);
    try testing.expectEqual(@as(usize, 0), @intFromPtr(refused.raw.atom));
    try testing.expectEqual(@as(usize, 0), @intFromPtr(refused.raw.stereo0D));
}

test "the molfile route produces PubChem's published identifier and key" {
    nativeReady();
    const molfile =
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

    const expected = compound("ethanol");

    var output = try inchi.fromMolfile(molfile, null);
    defer output.deinit();

    const identifier = output.identifier() orelse {
        std.debug.print("molfile: status {s}, message {s}\n", .{
            @tagName(output.status), output.message(),
        });
        return error.MissingIdentifier;
    };
    try testing.expectEqual(inchi.MolfileStatus.okay, output.status);
    try testing.expectEqualStrings(expected.identifier, identifier);

    const computed = try inchi.standardKey(identifier);
    try testing.expectEqualStrings(expected.key, computed.keyText());
}

test "the molfile route answers okay for text it runs out of, and refused for a counts line it cannot read" {
    nativeReady();
    // Upstream can return `okay` at EOF without an identifier; assert output fields separately.
    var exhausted = try inchi.fromMolfile("not a molfile\n", null);
    defer exhausted.deinit();

    try testing.expectEqual(inchi.MolfileStatus.okay, exhausted.status);
    try testing.expectEqual(@as(?[:0]const u8, null), exhausted.identifier());
    try testing.expect(exhausted.log().len != 0);

    // An unreadable counts line maps to `MolfileStatus.rejected`.
    const broken_counts =
        "broken counts\n" ++
        "\n" ++
        "\n" ++
        "  x  2  0  0  0  0  0  0  0  0999 V2000\n";

    var refused = try inchi.fromMolfile(broken_counts, null);
    defer refused.deinit();

    try testing.expectEqual(inchi.MolfileStatus.rejected, refused.status);
    try testing.expectEqual(@as(?[:0]const u8, null), refused.identifier());
    try testing.expect(refused.log().len != 0);
}

test "the extended route carries a pseudo-element only when NPZz lets it" {
    nativeReady();
    // The option prefix is `/` on Windows and `-` elsewhere.
    const npzz: [:0]const u8 = switch (builtin.target.os.tag) {
        .windows => "/NPZz",
        else => "-NPZz",
    };

    var scratch: molecules.Scratch = .{};
    _ = try molecules.pseudoAtom(&scratch);
    const atoms = scratch.atoms[0..scratch.atom_count];

    // `GetINCHIEx` rewrites input `*` atoms to `Zz`, so it requires mutable atoms.
    var refused = try inchi.fromMolecule.extended(.{ .atoms = atoms });
    defer refused.deinit();

    try testing.expectEqualStrings("Zz", elementOf(&atoms[0]));

    // A non-polymer `Zz` is rejected unless `NPZz` enables it.
    try testing.expectEqual(inchi.Status.rejected, refused.status);
    try testing.expectEqual(@as(?[:0]const u8, null), refused.identifier());

    // `NPZz` enables the pseudo-element.
    var allowed_scratch: molecules.Scratch = .{};
    _ = try molecules.pseudoAtom(&allowed_scratch);
    const allowed_atoms = allowed_scratch.atoms[0..allowed_scratch.atom_count];

    var allowed = try inchi.fromMolecule.extended(.{
        .atoms = allowed_atoms,
        .options = npzz,
    });
    defer allowed.deinit();

    try testing.expectEqualStrings("Zz", elementOf(&allowed_atoms[0]));
    try testing.expect(!rejected(allowed.status));

    // Non-polymer `Zz` identifiers use the beta prefix `InChI=1B/`.
    const identifier = allowed.identifier() orelse return error.MissingIdentifier;
    try testing.expect(std.mem.startsWith(u8, identifier, "InChI=1B/"));
}

test "the extended route reproduces the published identifier and reports no extensions" {
    nativeReady();
    const expected = compound("glycine");

    var scratch: molecules.Scratch = .{};
    const glycine = try molecules.glycine(&scratch);

    // Without polymer or V3000 data, extended generation matches classic generation.
    var generated = try inchi.fromMolecule.extended(.{ .atoms = @constCast(glycine.atoms) });
    defer generated.deinit();
    try testing.expectEqual(inchi.Status.okay, generated.status);
    try testing.expectEqualStrings(expected.identifier, generated.identifier().?);

    // The extended reader returns null polymer/V3000 blocks when the identifier has neither.
    var rebuilt = try inchi.fromIdentifier.extended(expected.identifier, null);
    defer rebuilt.deinit();
    try testing.expectEqual(inchi.Status.okay, rebuilt.status);
    try testing.expectEqual(@as(?*const inchi.Polymer, null), rebuilt.polymer());
    try testing.expectEqual(@as(?*const inchi.V3000, null), rebuilt.v3000());

    const made = try composition(rebuilt.atoms());
    try testing.expectEqual(@as(usize, 2), made.carbons);
    try testing.expectEqual(@as(usize, 1), made.nitrogens);
    try testing.expectEqual(@as(usize, 2), made.oxygens);

    // Standard generation from rebuilt arrays still matches the published identifier.
    var again = try inchi.fromMolecule.standard(.{
        .atoms = rebuilt.atoms(),
        .stereo0d = rebuilt.stereo0d(),
    });
    defer again.deinit();
    try testing.expectEqualStrings(expected.identifier, again.identifier().?);
}

/// Whether a status is one of the refusals: no data, rejected, or fatal.
fn rejected(status: inchi.Status) bool {
    return switch (status) {
        .no_data, .rejected, .fatal => true,
        else => false,
    };
}
