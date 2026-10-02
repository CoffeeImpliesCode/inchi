//! A runnable, deterministic demonstration of the InChI facade.
//!
//! `zig build smoke` runs this. There is no input, no clock and no random
//! seed, so the same lines come out every time.
//!
//! Every identifier below is an expected answer, not a value this program
//! computed for comparison: they are PubChem's published standard InChI
//! strings and InChIKeys, the same facts `tests.zig` reads out of
//! `testdata/pubchem_known_answers.tsv`. The molecules are built here from
//! element symbols and implicit hydrogen counts, so a mismatch means the
//! library disagreed with PubChem, not with itself.

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
/// PubChem CID 24602: the same oxygen as water, both hydrogens deuterium.
const heavy_water_inchi = "InChI=1S/H2O/h1H2/i/hD2";
const heavy_water_key = "XLYOFNOQVPJJNP-ZSJDYOACSA-N";

pub fn main() !void {
    var threaded: std.Io.Threaded = .init(std.heap.page_allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(io, &buffer);
    const w = &stdout.interface;

    try w.print("inchi smoke\n", .{});

    var scratch: molecules.Scratch = .{};

    // One oxygen with two implicit hydrogens.
    try check(w, "water", try molecules.water(&scratch), water_inchi, water_key);
    // One carbon with four implicit hydrogens.
    try check(w, "methane", try molecules.methane(&scratch), methane_inchi, methane_key);
    // Three atoms: CH3-CH2-OH, hydrogens implicit, no stereo.
    try check(w, "ethanol", try molecules.ethanol(&scratch), ethanol_inchi, ethanol_key);
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

    try w.print("smoke ok\n", .{});
    try w.flush();
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
    if (!std.mem.eql(u8, identifier, want_inchi)) {
        std.debug.print("{s}: wanted identifier {s}, got {s}\n", .{ what, want_inchi, identifier });
        return error.SmokeCheckFailed;
    }
    if (!std.mem.eql(u8, computed.keyText(), want_key)) {
        std.debug.print("{s}: wanted key {s}, got {s}\n", .{ what, want_key, computed.keyText() });
        return error.SmokeCheckFailed;
    }
    if (inchi.checkKey(computed.keyText()) != .standard) {
        std.debug.print("{s}: the key the library produced does not validate\n", .{what});
        return error.SmokeCheckFailed;
    }
}
