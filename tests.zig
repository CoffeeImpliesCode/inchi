//! Behavioural tests for the InChI facade.
//!
//! The oracle is `testdata/pubchem_known_answers.tsv`: identifiers and keys
//! read out of PubChem's own compound records, with the retrieval recorded in
//! the file's header. Nothing here asks the library what it thinks the answer
//! is and calls it correct. The molecules are built from element symbols,
//! bonds and implicit hydrogen counts in `zig/molecules.zig`; where a molecule
//! carries stereochemistry, the test asserts that the two parities of one
//! skeleton produce exactly the two identifiers PubChem publishes for that
//! pair of compounds, and that each identifier's key is the key published with
//! it. That is a complete known-answer statement about both parities without
//! the test having to predict which parity is which -- which it cannot, because
//! the parity is defined relative to the neighbour order and the canonical
//! ranking InChI computes from it (`inchi_api.h:255-256`).
//!
//! One round trip is included as a supplement rather than as the oracle: the
//! structure upstream rebuilds from L-alanine's identifier goes straight back
//! into a `Molecule` and regenerates that identifier, with no copy, which also
//! exercises `GetStructFromStdINCHI`'s output as `GetStdINCHI`'s input.
//! `GetINCHIfromINCHI` is exercised on the same published strings, with no
//! options and with upstream's own layer-keeping option string, because that
//! string is what decides whether the answer comes back standard.
//!
//! Every public entry point of the facade is called here, so `zig build check`
//! compiling this file is a check of the whole surface for each target.

const std = @import("std");
const inchi = @import("inchi");
const molecules = @import("zig/molecules.zig");
const testing = std.testing;

/// PubChem's published answers, embedded so no test needs a file system.
const fixture_text = @embedFile("testdata/pubchem_known_answers.tsv");

/// One published answer, terminated at exactly its own length.
///
/// The facade takes `[:0]const u8`, and a sentinel slice stops *before* its
/// terminator: the zero has to be the byte at `len`, not a byte the answer
/// ends with. Appending `"\x00"` to a fixture field would lengthen the slice
/// over the terminator instead, which is a different string from the published
/// one even though C reads both the same way. The value is comptime, so the
/// concatenation is a static constant, and the answer is not copied into
/// storage of a fixed size first.
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

/// The table parsed at comptime, so every answer below ends up in storage
/// that outlives the block and a NUL-terminated slice can be taken of it.
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

/// The same identifier without its `S`, i.e. the non-standard form
/// `InChI=1/...` that `CheckINCHI` classifies separately
/// (`inchi_dll.c:872-885`).
const non_standard_l_alanine: [:0]const u8 = blk: {
    const standard = compound("l_alanine").identifier;
    // Both operands are sentinel slices, so the concatenation is one and the
    // terminator is the published identifier's own: the byte one past its
    // last character, not a byte inside the answer.
    break :blk "InChI=1/" ++ standard[9..];
};

/// Asserts that two results are exactly the two published identifiers, one
/// each, and that each one's key is the key published beside it.
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

/// What a rebuilt structure is made of. The counts are of atoms, except the
/// last, which is the hydrogens the atoms carry implicitly.
const Composition = struct {
    carbons: usize = 0,
    nitrogens: usize = 0,
    oxygens: usize = 0,
    hydrogens: usize = 0,
    implicit_hydrogens: usize = 0,
};

/// Counts what a structure is made of. An element none of these fixtures
/// builds fails the test rather than being counted as nothing.
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

/// The two blocks an InChIKey's dashes separate: the first is the skeleton
/// hash and the second the hash of what the skeleton leaves out
/// (`ikey_dll.c:527-536`).
fn keyBlocks(text: []const u8) [2][]const u8 {
    const first = std.mem.findScalar(u8, text, '-') orelse return .{ text, text };
    const second = std.mem.findScalarPos(u8, text, first + 1, '-') orelse return .{ text[0..first], text[first + 1 ..] };
    return .{ text[0..first], text[first + 1 .. second] };
}

test "water built from one oxygen matches the identifier and key PubChem publishes" {
    const expected = compound("water");

    var scratch: molecules.Scratch = .{};
    var output = try inchi.fromMolecule.standard(try molecules.water(&scratch));
    defer output.deinit();

    try testing.expectEqual(inchi.Status.okay, output.status);
    try testing.expect(!output.isWarning());
    try testing.expectEqualStrings(expected.identifier, output.identifier().?);
    // A clean run has nothing to report, so nothing is reported.
    try testing.expectEqualStrings("", output.message());
    // The recognised options and the input echo are logged even on a clean
    // run (`PrintInputParms`, inchi_dll.c:590).
    try testing.expect(output.log().len > 0);
    // The auxiliary line is the tail of the identifier's own allocation,
    // written by upstream and split out here (`inchi_dll.c:764-771`).
    try testing.expect(std.mem.startsWith(u8, output.auxInfo().?, "AuxInfo="));

    const computed = try inchi.key(expected.identifier, .{});
    try testing.expectEqualStrings(expected.key, computed.keyText());
    try testing.expectEqual(inchi.KeyVerdict.standard, inchi.checkKey(computed.keyText()));
    try testing.expectEqual(inchi.IdentifierVerdict.standard, inchi.checkIdentifier(expected.identifier, false));
    // Strict mode regenerates the identifier and demands it back unchanged
    // (`inchi_dll.c:954-981`), and for a standard identifier it cannot: the
    // option string it builds there asks for the Fixed-H and Reconnected
    // layers, and either of those clears the standard flag as it is parsed
    // (`ichiparm.c:350-364`), so what comes back is the same compound as
    // `InChI=1/...`. A well-formed standard identifier is therefore a failed
    // conversion, and the layout verdict above is the one that classifies it.
    try testing.expectEqual(inchi.IdentifierVerdict.conversion_failed, inchi.checkIdentifier(expected.identifier, true));
}

test "methane built from one carbon matches the identifier and key PubChem publishes" {
    const expected = compound("methane");

    var scratch: molecules.Scratch = .{};
    var output = try inchi.fromMolecule.standard(try molecules.methane(&scratch));
    defer output.deinit();

    try testing.expectEqual(inchi.Status.okay, output.status);
    try testing.expectEqualStrings(expected.identifier, output.identifier().?);

    // The standard-key entry point computes no extension hash and refuses a
    // non-standard identifier, which is the whole difference from `key`.
    const computed = try inchi.standardKey(output.identifier().?);
    try testing.expectEqualStrings(expected.key, computed.keyText());
    try testing.expectEqual(@as(?[:0]const u8, null), computed.firstHash());
    try testing.expectEqual(@as(?[:0]const u8, null), computed.secondHash());
}

test "ethanol: the non-standard entry point agrees, and /AuxNone leaves the identifier alone" {
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

    // /AuxNone is a presentation switch (`ichiparm.c:211-216`): it cannot move
    // the identifier, so the identifier is what this asserts.
    var without_aux = try inchi.fromMolecule.full(.{
        .atoms = ethanol.atoms,
        .stereo0d = ethanol.stereo0d,
        .options = molecules.no_aux_options,
    });
    defer without_aux.deinit();
    try testing.expectEqualStrings(expected.identifier, without_aux.identifier().?);
}

test "benzene and glycine match the identifiers PubChem publishes" {
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
    const expected = compound("glycine");

    var scratch: molecules.Scratch = .{};

    var neutral = try inchi.fromMolecule.standard(try molecules.glycine(&scratch));
    defer neutral.deinit();
    var zwitterion = try inchi.fromMolecule.standard(try molecules.glycineZwitterion(&scratch));
    defer zwitterion.deinit();

    // A warning is a qualified success, not a failure: the identifier is
    // there, and it is the published one, because upstream neutralized
    // NH3(+)/COO(-) to exactly the skeleton `glycine` builds.
    try testing.expectEqual(inchi.Status.okay, neutral.status);
    try testing.expect(!neutral.isWarning());
    try testing.expectEqual(inchi.Status.warning, zwitterion.status);
    try testing.expect(zwitterion.isWarning());
    try testing.expectEqualStrings(expected.identifier, zwitterion.identifier().?);
    try testing.expectEqualStrings(neutral.identifier().?, zwitterion.identifier().?);

    // Upstream's own words about the protons normalization moved are not
    // asserted: the status above is the part of that message a caller acts
    // on, and the published identifier is the part that has to be right. The
    // neutral run has nothing to report and says nothing.
    try testing.expectEqualStrings("", neutral.message());
}

test "renumbering the atoms of ethanol and benzene changes nothing" {
    var scratch: molecules.Scratch = .{};

    var ethanol = try inchi.fromMolecule.standard(try molecules.ethanol(&scratch));
    defer ethanol.deinit();
    var renumbered_ethanol = try inchi.fromMolecule.standard(try molecules.ethanolRenumbered(&scratch));
    defer renumbered_ethanol.deinit();
    try testing.expectEqualStrings(ethanol.identifier().?, renumbered_ethanol.identifier().?);
    // And both are the published answer, not just each other.
    try testing.expectEqualStrings(compound("ethanol").identifier, renumbered_ethanol.identifier().?);

    var benzene = try inchi.fromMolecule.standard(try molecules.benzene(&scratch));
    defer benzene.deinit();
    var renumbered_benzene = try inchi.fromMolecule.standard(try molecules.benzeneRenumbered(&scratch));
    defer renumbered_benzene.deinit();
    try testing.expectEqualStrings(benzene.identifier().?, renumbered_benzene.identifier().?);
    try testing.expectEqualStrings(compound("benzene").identifier, renumbered_benzene.identifier().?);
}

test "the tetrahedral 0D parity separates alanine into the two enantiomers PubChem publishes" {
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
    const expected = compound("l_alanine");

    var structure = try inchi.fromIdentifier.standard(expected.identifier, null);
    defer structure.deinit();

    try testing.expectEqual(inchi.Status.okay, structure.status);
    try testing.expect(!structure.isWarning());
    try testing.expect(structure.log().len > 0);
    // Nothing was dropped on the way from identifier to structure, which is
    // also what keeps upstream from reporting a warning here
    // (`inchi_dll.c:2829-2840`).
    for (structure.warnings()) |row| for (row) |flag| {
        try testing.expectEqual(@as(c_ulong, 0), flag);
    };

    // C3H7NO2 is six heavy atoms and seven hydrogens, and the rebuild carries
    // all seven -- but the one on the stereocentre is an atom of the structure
    // rather than an implicit count, because a tetrahedral parity has nothing
    // to be measured against otherwise (`inchi_api.h:248-270`). So what the
    // composition has to agree with is the published formula, not a length.
    const atoms = structure.atoms();
    const made = try composition(atoms);
    try testing.expectEqual(@as(usize, 3), made.carbons);
    try testing.expectEqual(@as(usize, 1), made.nitrogens);
    try testing.expectEqual(@as(usize, 2), made.oxygens);
    try testing.expectEqual(@as(usize, 1), made.hydrogens);
    try testing.expectEqual(@as(usize, 6), made.implicit_hydrogens);

    // One stereocentre, and it is a tetrahedral one.
    const stereo = structure.stereo0d();
    try testing.expectEqual(@as(usize, 1), stereo.len);
    try testing.expectEqual(inchi.StereoType0D.tetrahedral, @as(inchi.StereoType0D, @enumFromInt(stereo[0].type)));

    // Its central atom is the alpha carbon: the one carbon that has no
    // hydrogen of its own, because that hydrogen is the explicit atom counted
    // above, and it is bonded to it. Upstream fills the four neighbour slots
    // with the bond partners of a four-bonded central atom
    // (`readinch.c:1463-1472`).
    const centre: usize = @intCast(stereo[0].central_atom);
    try testing.expectEqualStrings("C", elementOf(&atoms[centre]));
    try testing.expect(atoms[centre].num_iso_H[0] == 0);
    var hydrogen: usize = 0;
    for (atoms, 0..) |*atom, index| {
        if (std.mem.eql(u8, elementOf(atom), "H")) hydrogen = index;
    }
    const bonds = atoms[centre].neighbor[0..@intCast(atoms[centre].num_bonds)];
    try testing.expect(std.mem.findScalar(c_short, bonds, @intCast(hydrogen)) != null);

    // The rebuilt atoms go straight back in, with no copy: `GetStdINCHI` reads
    // its input and never writes through it.
    var regenerated = try inchi.fromMolecule.standard(.{
        .atoms = atoms,
        .stereo0d = stereo,
    });
    defer regenerated.deinit();
    try testing.expectEqual(inchi.Status.okay, regenerated.status);
    try testing.expectEqualStrings(expected.identifier, regenerated.identifier().?);
}

test "isotopic hydrogens put water and heavy water in different classes" {
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

    // The connectivity layer is identical; only the isotope layer differs, and
    // the first two blocks of the keys differ because of it.
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
    // No options is the conversion that keeps every layer the identifier
    // already has, because none of them is filtered out
    // (`inchi_api.h:889-901`), and the comparison is against what PubChem
    // publishes rather than against the input, so this is a known-answer
    // statement and not a conversion that only agrees with itself.
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
    const water = compound("water").identifier;

    // `/FixedH` and `/RecMet` are how a caller asks for the Fixed-H and
    // Reconnected layers to be kept (`inchi_api.h:894-895`), and each of them
    // clears the standard flag while the options are parsed
    // (`ichiparm.c:350-364`). A `1S` identifier cannot be reproduced under
    // them, and that is also why upstream's own strict `CheckINCHI` reports
    // `INCHI_FAIL_I2I` for every standard identifier: it regenerates with
    // exactly this string and compares (`inchi_dll.c:954-981`).
    var with_layers = try inchi.fromIdentifier.converted(water, molecules.strict_options);
    defer with_layers.deinit();
    try testing.expectEqual(inchi.Status.okay, with_layers.status);
    try testing.expectEqualStrings("InChI=1/H2O/h1H2", with_layers.identifier().?);
    try testing.expectEqual(inchi.IdentifierVerdict.non_standard, inchi.checkIdentifier(with_layers.identifier().?, false));

    // The same input with no options at all stays standard.
    var without_layers = try inchi.fromIdentifier.converted(water, null);
    defer without_layers.deinit();
    try testing.expectEqual(inchi.Status.okay, without_layers.status);
    try testing.expectEqualStrings(water, without_layers.identifier().?);
}

test "a non-standard identifier is accepted by the general reader and refused by the standard one" {
    try testing.expectEqual(
        inchi.IdentifierVerdict.non_standard,
        inchi.checkIdentifier(non_standard_l_alanine, false),
    );

    // The standard-only entry point guards on the `S` before doing any work
    // (`inchi_dll.c:2464-2476`), so it produces no structure and no text at
    // all -- the struct it was handed is the one this facade zeroed, which is
    // why a refused structure has to answer with empty arrays rather than with
    // a cast of the null pointer it holds.
    var refused = try inchi.fromIdentifier.standard(non_standard_l_alanine, null);
    defer refused.deinit();
    try testing.expectEqual(inchi.Status.rejected, refused.status);
    try testing.expectEqual(@as(usize, 0), refused.atoms().len);
    try testing.expectEqual(@as(usize, 0), refused.stereo0d().len);
    try testing.expectEqualStrings("", refused.message());
    try testing.expectEqualStrings("", refused.log());

    // The general reader rebuilds what the standard-only entry point refused:
    // the same alanine, with the hydrogen its parity needs as an atom.
    var accepted = try inchi.fromIdentifier.full(non_standard_l_alanine, null);
    defer accepted.deinit();
    try testing.expectEqual(inchi.Status.okay, accepted.status);
    const rebuilt = try composition(accepted.atoms());
    try testing.expectEqual(@as(usize, 3), rebuilt.carbons);
    try testing.expectEqual(@as(usize, 1), rebuilt.nitrogens);
    try testing.expectEqual(@as(usize, 2), rebuilt.oxygens);
    try testing.expectEqual(@as(usize, 1), rebuilt.hydrogens);

    // The two key entry points disagree on exactly this, which is the only
    // thing `GetStdINCHIKeyFromStdINCHI` adds (`ikey_dll.c:95-102`).
    try testing.expectError(error.InvalidStdInchi, inchi.standardKey(non_standard_l_alanine));
    const non_standard_key = try inchi.key(non_standard_l_alanine, .{});
    try testing.expectEqual(@as(usize, 27), non_standard_key.keyText().len);
    try testing.expectEqual(inchi.KeyVerdict.non_standard, inchi.checkKey(non_standard_key.keyText()));
}

test "malformed identifiers and keys are reported as upstream reports them" {
    try testing.expectEqual(inchi.IdentifierVerdict.invalid_prefix, inchi.checkIdentifier("not an identifier", false));
    try testing.expectEqual(inchi.IdentifierVerdict.invalid_prefix, inchi.checkIdentifier("InChI=1", false));
    try testing.expectEqual(inchi.IdentifierVerdict.invalid_version, inchi.checkIdentifier("InChI=9S/H2O/h1H2", false));
    try testing.expectEqual(inchi.IdentifierVerdict.invalid_layout, inchi.checkIdentifier("InChI=1SX", false));

    try testing.expectError(error.InvalidInchiPrefix, inchi.key("", .{}));
    try testing.expectError(error.InvalidInchiPrefix, inchi.key("InChI=1", .{}));
    try testing.expectError(error.InvalidStdInchi, inchi.standardKey("InChI=1/H2O/h1H2"));

    try testing.expectEqual(inchi.KeyVerdict.standard, inchi.checkKey(compound("water").key));
    try testing.expectEqual(inchi.KeyVerdict.invalid_length, inchi.checkKey("XLYOFNOQVPJJNP-UHFFFAOYSA"));
    try testing.expectEqual(inchi.KeyVerdict.invalid_layout, inchi.checkKey("XLYOFNOQVPJJNP-UHFFFAOYSA-n"));
    // The version is the tenth character of the second block (index 24)
    // (`ikey_dll.c:577-581`), not the last character: that one is the
    // (de)protonation flag, and any base-26 letter is a legal one
    // (`ikey_dll.c:554-557`), so `-B` is a well formed key rather than a
    // malformed one.
    try testing.expectEqual(inchi.KeyVerdict.invalid_version, inchi.checkKey("XLYOFNOQVPJJNP-UHFFFAOYSS-B"));

    // The general reader reports EOF when no atoms were produced, including
    // this malformed layout (inchi_dll.c:2821-2825). The standard-only
    // reader's earlier rejection is exercised separately above.
    var refused = try inchi.fromIdentifier.full("InChI=1SX", null);
    defer refused.deinit();
    try testing.expectEqual(inchi.Status.no_data, refused.status);
    try testing.expectEqual(@as(usize, 0), refused.atoms().len);
}

test "a pseudo-element is refused" {
    var scratch: molecules.Scratch = .{};
    const star = try molecules.pseudoAtom(&scratch);

    var output = try inchi.fromMolecule.standard(star);
    defer output.deinit();

    // Neither entry point can represent a star atom; both refuse it before
    // generating anything (`inchi_dll.c:247-250`, `inchi_dll.c:275-278`).
    try testing.expectEqual(inchi.Status.rejected, output.status);
    try testing.expectEqual(@as(?[:0]const u8, null), output.identifier());

    var full = try inchi.fromMolecule.full(star);
    defer full.deinit();
    try testing.expectEqual(inchi.Status.rejected, full.status);
    try testing.expectEqualStrings("Unsupported in this mode element '*'", full.message());
}

test "the facade refuses input it cannot pass on faithfully" {
    try testing.expectError(error.ElementSymbolTooLong, inchi.atom("Ununbium", .none));

    var scratch: molecules.Scratch = .{};
    _ = try molecules.ethanol(&scratch);
    const filled = scratch.atoms[0..scratch.atom_count];
    try testing.expectError(error.AtomIndexOutOfRange, inchi.connect(filled, 0, 7, .single, .none));
    try testing.expectError(error.AtomIndexOutOfRange, inchi.connect(filled, 1, 1, .single, .none));

    // Twenty bonds is the whole adjacency list (`MAXVAL`, inchi_api.h:105).
    var atoms: [2]inchi.Atom = undefined;
    atoms[0] = try inchi.atom("C", .none);
    atoms[1] = try inchi.atom("C", .none);
    var placed: usize = 0;
    while (placed < inchi.max_bonds_per_atom) : (placed += 1) {
        try inchi.connect(atoms[0..], 0, 1, .single, .none);
    }
    try testing.expectError(error.TooManyNeighbors, inchi.connect(atoms[0..], 0, 1, .single, .none));
}
