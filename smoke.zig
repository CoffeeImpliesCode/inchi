//! SPDX-License-Identifier: LicenseRef-InChI-MIT-Conditional
//! See FORK-LICENSE.md for the full grant and the owner authorization behind it.
//! Deterministic demonstration of facade operations against PubChem answers.
//! `zig build smoke` supports linked and runtime-loaded builds; runtime mode
//! requires an explicit provider.

const std = @import("std");
const inchi = @import("inchi");
const molecules = @import("zig/molecules.zig");

const water_inchi = "InChI=1S/H2O/h1H2";
const water_key = "XLYOFNOQVPJJNP-UHFFFAOYSA-N";
const methane_inchi = "InChI=1S/CH4/h1H4";
const methane_key = "VNWKTOKETHGBQD-UHFFFAOYSA-N";
const ethanol_inchi = "InChI=1S/C2H6O/c1-2-3/h3H,2H2,1H3";
const ethanol_key = "LFQSCWFLJHTTHZ-UHFFFAOYSA-N";
const benzene_inchi = "InChI=1S/C6H6/c1-2-4-6-5-3-1/h1-6H";
const benzene_key = "UHOVQNZJYSORNB-UHFFFAOYSA-N";
const heavy_water_inchi = "InChI=1S/H2O/h1H2/i/hD2";
const heavy_water_key = "XLYOFNOQVPJJNP-ZSJDYOACSA-N";

/// V2000 ethanol input for the published identifier.
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

const ConfigurationError = error{NoProviderConfigured};

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(io, &buffer);
    const w = &stdout.interface;

    // Runtime-loaded builds load the explicitly selected provider before use.
    if (comptime inchi.runtime_loaded) {
        const provider = try providerRequest(init);
        try inchi.load(.{ .path = provider });
    }

    try w.print("inchi smoke\n", .{});
    try w.print("{s}\n", .{
        if (inchi.runtime_loaded) "runtime-loaded provider" else "linked library",
    });

    var scratch: molecules.Scratch = .{};

    // Deuterium adds an isotope layer and changes the key's second block.
    try check(w, "water", try molecules.water(&scratch), water_inchi, water_key);
    try check(w, "methane", try molecules.methane(&scratch), methane_inchi, methane_key);
    try check(w, "ethanol", try molecules.ethanol(&scratch), ethanol_inchi, ethanol_key);
    try check(w, "benzene", try molecules.benzene(&scratch), benzene_inchi, benzene_key);
    try check(w, "heavy water", try molecules.heavyWater(&scratch), heavy_water_inchi, heavy_water_key);

    // Standard InChI canonicalizes equivalent atom numberings.
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

    // Rebuild water and regenerate its published identifier from borrowed atoms.
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

    // Extended glycine generation and reading report no polymer/V3000 blocks.
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

    // Water's AuxInfo line rebuilds the molecule and regenerates its identifier.
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

    // Convert the ethanol CTfile directly, without building a molecule.
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

/// Selects the runtime provider from `--provider <path>` or `INCHI_TEST_PROVIDER`.
/// No default path or linked fallback is used.
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
        "smoke: this is a runtime-loading build. Pass --provider <path>, or " ++
            "export INCHI_TEST_PROVIDER with a shared object exporting the entry " ++
            "points of INCHI-1-SRC/INCHI_BASE/src/inchi_api.h (and, through it, " ++
            "ixa.h). Nothing is loaded by default and no other file is tried.\n",
        .{},
    );
    return error.NoProviderConfigured;
}

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

fn expect(what: []const u8, got: [:0]const u8, want: [:0]const u8) !void {
    if (!std.mem.eql(u8, got, want)) {
        std.debug.print("{s}: wanted {s}, got {s}\n", .{ what, want, got });
        return error.SmokeCheckFailed;
    }
}
