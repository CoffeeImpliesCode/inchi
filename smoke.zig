//! SPDX-License-Identifier: LicenseRef-InChI-MIT-Conditional
//! See FORK-LICENSE.md for the full grant and the owner authorization behind it.
//
//! A runnable, deterministic demonstration of the InChI facade.
//!
//! `zig build smoke` runs this. There is no clock, no random seed and no input,
//! so the same lines come out every time.
//!
//! Every identifier below is an expected answer, not a value this program
//! computed for comparison: they are PubChem's published standard InChI strings
//! and InChIKeys, the same facts `tests.zig` reads out of
//! `testdata/pubchem_known_answers.tsv`. The molecules are built here from
//! element symbols and implicit hydrogen counts, so a mismatch means the
//! library disagreed with PubChem, not with itself.
//!
//! The same source builds against a linked package and against a
//! runtime-loaded one. `inchi.runtime_loaded` is a comptime constant, so the
//! difference is one branch and no duplicated program: in the runtime-loaded
//! build the provider is named on the command line (`--provider <path>`) or in
//! `INCHI_TEST_PROVIDER`, loaded once, and the same published answers follow.

const std = @import("std");
const inchi = @import("inchi");
const molecules = @import("zig/molecules.zig");

/// PubChem CID 962.
const water_inchi = "InChI=1S/H2O/h1H2";
const water_key = "XLYOFNOQVPJJNP-UHFFFAOYSA-N";
/// PubChem CID 297.
const methane_inchi = "InChI=1S/CH4/h1H4";
const methane_key = "VNWKTOKETHGBQD-UHFFFAOYSA-N";
/// PubChem CID 702.
const ethanol_inchi = "InChI=1S/C2H6O/c1-2-3/h3H,2H2,1H3";
const ethanol_key = "LFQSCWFLJHTTHZ-UHFFFAOYSA-N";
/// PubChem CID 241.
const benzene_inchi = "InChI=1S/C6H6/c1-2-4-6-5-3-1/h1-6H";
const benzene_key = "UHOVQNZJYSORNB-UHFFFAOYSA-N";
/// PubChem CID 24602: the same oxygen as water, both hydrogens deuterium.
const heavy_water_inchi = "InChI=1S/H2O/h1H2/i/hD2";
const heavy_water_key = "XLYOFNOQVPJJNP-ZSJDYOACSA-N";

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

/// A runtime-loading build has no provider until one is named.
const ConfigurationError = error{NoProviderConfigured};

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(io, &buffer);
    const w = &stdout.interface;

    // In a runtime-loading build nothing below can run until a provider is
    // loaded, and the load is the one explicit step the contract asks for. In a
    // linked build this is a no-op at comptime and the module is already
    // usable.
    if (comptime inchi.runtime_loaded) {
        const provider = try providerRequest(init);
        try inchi.load(.{ .path = provider });
    }

    try w.print("inchi smoke\n", .{});
    try w.print("{s}\n", .{
        if (inchi.runtime_loaded) "runtime-loaded provider" else "linked library",
    });

    var scratch: molecules.Scratch = .{};

    // One oxygen with two implicit hydrogens.
    try check(w, "water", try molecules.water(&scratch), water_inchi, water_key);
    // One carbon with four implicit hydrogens.
    try check(w, "methane", try molecules.methane(&scratch), methane_inchi, methane_key);
    // Three atoms: CH3-CH2-OH, hydrogens implicit, no stereo.
    try check(w, "ethanol", try molecules.ethanol(&scratch), ethanol_inchi, ethanol_key);
    // A six-membered Kekule ring.
    try check(w, "benzene", try molecules.benzene(&scratch), benzene_inchi, benzene_key);
    // The same oxygen as water, both hydrogens deuterium in num_iso_H[2]: the
    // isotope layer appears and the key's second block changes with it.
    try check(w, "heavy water", try molecules.heavyWater(&scratch), heavy_water_inchi, heavy_water_key);

    // The same molecule numbered from the other end. A standard InChI is
    // canonical, so this has to come out identical.
    var first = try inchi.fromMolecule.standard(try molecules.ethanol(&scratch));
    defer first.deinit();
    var second = try inchi.fromMolecule.standard(try molecules.ethanolRenumbered(&scratch));
    defer second.deinit();
    try w.print("ethanol renumbered = {s}\n", .{second.identifier().?});
    if (!std.mem.eql(u8, first.identifier().?, second.identifier().?)) {
        std.debug.print("ethanol renumbered: wanted {s}, got {s}\n", .{
            first.identifier().?, second.identifier().?,
        });
        return error.SmokeCheckFailed;
    }

    // The identifier to structure direction: upstream rebuilds water's
    // published identifier, and the rebuilt atoms regenerate it with no copy
    // anywhere in between.
    var rebuilt = try inchi.fromIdentifier.standard(water_inchi, null);
    defer rebuilt.deinit();
    try w.print("water from identifier = {d} atoms\n", .{rebuilt.atoms().len});
    if (rebuilt.status != .okay or rebuilt.atoms().len != 1) {
        std.debug.print("water rebuild: status {s}, {d} atoms, {s}\n", .{
            @tagName(rebuilt.status), rebuilt.atoms().len, rebuilt.message(),
        });
        return error.SmokeCheckFailed;
    }
    var round_trip = try inchi.fromMolecule.standard(.{
        .atoms = rebuilt.atoms(),
        .stereo0d = rebuilt.stereo0d(),
    });
    defer round_trip.deinit();
    try expect("water regenerated", round_trip.identifier().?, water_inchi);

    // The extended polymer/V3000 route. With no polymer and no V3000 block the
    // extended input is the classic input, so it has to produce the same
    // published identifier; and the extended reader rebuilds it into the
    // extended structure, reporting no extensions because the identifier
    // described none.
    const glycine_inchi = "InChI=1S/C2H5NO2/c3-1-2(4)5/h1,3H2,(H,4,5)";
    const glycine = try molecules.glycine(&scratch);
    var extended = try inchi.fromMolecule.extended(.{ .atoms = @constCast(glycine.atoms) });
    defer extended.deinit();
    try w.print("glycine extended = {s}\n", .{extended.identifier().?});
    try expect("glycine extended", extended.identifier().?, glycine_inchi);

    var extended_read = try inchi.fromIdentifier.extended(glycine_inchi, null);
    defer extended_read.deinit();
    if (extended_read.status != .okay or
        extended_read.polymer() != null or
        extended_read.v3000() != null)
    {
        std.debug.print("glycine extended read: status {s}, polymer {any}, v3000 {any}\n", .{
            @tagName(extended_read.status),
            extended_read.polymer(),
            extended_read.v3000(),
        });
        return error.SmokeCheckFailed;
    }
    try w.print("glycine extended rebuild = {d} atoms\n", .{extended_read.atoms().len});

    // The AuxInfo line a water run produced rebuilds the molecule, and the
    // molecule regenerates the published identifier.
    var water_output = try inchi.fromMolecule.standard(try molecules.water(&scratch));
    defer water_output.deinit();
    const aux_line = water_output.auxInfo() orelse {
        std.debug.print("water: no AuxInfo line\n", .{});
        return error.SmokeCheckFailed;
    };
    try w.print("water aux = {s}\n", .{aux_line});
    var from_aux = try inchi.fromAuxInfo.standard(aux_line, null, false);
    defer from_aux.deinit();
    if (from_aux.status != .okay and from_aux.status != .warning) {
        std.debug.print("water aux: status {s}, {s}\n", .{
            @tagName(from_aux.status), from_aux.parseMessage(),
        });
        return error.SmokeCheckFailed;
    }
    var from_aux_inchi = try inchi.fromMolecule.standard(from_aux.molecule());
    defer from_aux_inchi.deinit();
    try expect("water from AuxInfo", from_aux_inchi.identifier().?, water_inchi);

    // The molfile shortcut: an identifier straight out of a CTfile, with no
    // molecule built here at all.
    var molfile = try inchi.fromMolfile(ethanol_molfile, null);
    defer molfile.deinit();
    try w.print("ethanol molfile = {s}\n", .{molfile.identifier() orelse "nothing"});
    if (molfile.status != .okay) {
        std.debug.print("ethanol molfile: status {s}, message {s}\n", .{
            @tagName(molfile.status), molfile.message(),
        });
        return error.SmokeCheckFailed;
    }
    try expect("ethanol molfile", molfile.identifier().?, ethanol_inchi);
    const molfile_key = try inchi.standardKey(molfile.identifier().?);
    try expect("ethanol molfile key", molfile_key.keyText(), ethanol_key);

    try w.print("every identifier matched the published answer\n", .{});
    try w.flush();
}

/// The provider this run should load, from `--provider <path>` or from
/// `INCHI_TEST_PROVIDER`.
///
/// Both are explicit. Nothing here looks in a default location or falls back
/// to a linked copy: a runtime-loading build that was not told which file to
/// load reports that it was not told, rather than loading something else.
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
        "smoke: this is a runtime-loading build. Pass --provider <path>, or " ++
            "export INCHI_TEST_PROVIDER with a shared object exporting the entry " ++
            "points of INCHI-1-SRC/INCHI_BASE/src/inchi_api.h (and, through it, " ++
            "ixa.h). Nothing is loaded by default and no other file is tried.\n",
        .{},
    );
    return error.NoProviderConfigured;
}

/// Generates an identifier from `molecule` and prints it with its key, then
/// checks both against the answers PubChem publishes.
fn check(
    w: *std.Io.Writer,
    what: []const u8,
    molecule: inchi.Molecule,
    want_inchi: [:0]const u8,
    want_key: [:0]const u8,
) !void {
    var output = try inchi.fromMolecule.standard(molecule);
    defer output.deinit();

    const identifier = output.identifier() orelse {
        std.debug.print("{s}: no identifier, status {s}\n", .{ what, @tagName(output.status) });
        return error.SmokeCheckFailed;
    };

    const computed = try inchi.key(identifier, .{});
    try w.print("{s} = {s} {s}\n", .{ what, identifier, computed.keyText() });

    if (output.status != .okay) {
        std.debug.print("{s}: status {s}, message {s}\n", .{ what, @tagName(output.status), output.message() });
        return error.SmokeCheckFailed;
    }
    try expect(what, identifier, want_inchi);
    try expect(what, computed.keyText(), want_key);
    if (inchi.checkKey(computed.keyText()) != .standard) {
        std.debug.print("{s}: the key the library produced does not validate\n", .{what});
        return error.SmokeCheckFailed;
    }
}

/// Compare one answer with the published one and say so when they differ.
fn expect(what: []const u8, got: [:0]const u8, want: [:0]const u8) !void {
    if (!std.mem.eql(u8, got, want)) {
        std.debug.print("{s}: wanted {s}, got {s}\n", .{ what, want, got });
        return error.SmokeCheckFailed;
    }
}