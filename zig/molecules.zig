//! Molecule fixtures for `tests.zig` and `smoke.zig`.
//!
//! This is **not** part of the published `inchi` module: `zig/root.zig` does
//! not import it, and it imports `@import("inchi")` itself, so it only resolves
//! from a compilation that already provides that module -- which is exactly
//! what the test and smoke roots are. It lives beside the facade because both
//! of them build the same molecules and a second copy of those builders would
//! be free to drift from the first.
//!
//! Every molecule here is written as a chemist writes it: element symbols,
//! bonds, implicit hydrogen counts and, where the answer depends on it, the 0D
//! parity. Nothing here predicts what InChI will say. The expected identifiers
//! and keys live in `testdata/pubchem_known_answers.tsv`, which is what this
//! workspace consulted PubChem for and recorded; the two are compared in
//! `tests.zig`.

/// The option string upstream's own strict `CheckINCHI` builds before it calls
/// `GetINCHIfromINCHI` (`inchi_dll.c:954-981`). Upstream holds it as the
/// template `" ?FixedH ?RecMet ?SUU ?SLUUD"` and overwrites the four question
/// marks with `INCHI_OPTION_PREFX` at run time (`inchi_dll.c:965`); the arms
/// below are that string with the substitution already applied, because the C
/// recognises an option only by its first byte (`ichiparm.c:1221`) and would
/// report every `?`-prefixed token as unrecognised, leaving FixedH, RecMet,
/// SUU and SLUUD silently not applied.
///
/// It is worth keeping upstream's own spelling, because that spelling decides
/// which conversion happens at all: `FixedH` and `RecMet` are how a caller
/// asks for the Fixed-H and Reconnected layers to be kept
/// (`inchi_api.h:894-895`), and each of them clears the standard flag as the
/// options are parsed (`ichiparm.c:350-364`), so a conversion made with this
/// string answers `InChI=1/...` where the same conversion with no options at
/// all answers `InChI=1S/...`. That is also why `CheckINCHI` in strict mode
/// reports `INCHI_FAIL_I2I` for a standard identifier: it regenerates with
/// exactly this string and compares (`inchi_dll.c:954-981`). `tests.zig` runs
/// both conversions.
pub const strict_options: [:0]const u8 = switch (@import("builtin").target.os.tag) {
    .windows => "/FixedH /RecMet /SUU /SLUUD",
    else => "-FixedH -RecMet -SUU -SLUUD",
};

/// `"/AuxNone"`, upstream's switch for omitting the auxiliary information
/// (`inchi_api.h:824`). Written for the target, because the prefix is `/` on
/// Windows and `-` everywhere else (`INCHI_BASE/src/mode.h:262-267`) and the
/// C library compares against the one it was compiled with.
pub const no_aux_options: [:0]const u8 = switch (@import("builtin").target.os.tag) {
    .windows => "/AuxNone",
    else => "-AuxNone",
};

const inchi = @import("inchi");

/// Failures of the fixture builder. The first two are local bounds on the
/// scratch storage; the rest are the facade's own, re-exported so a caller of
/// these fixtures sees one error set.
pub const Error = error{
    TooManyAtoms,
    TooManyStereoDescriptors,
} || inchi.Error;

/// Fixed storage one molecule is built into.
///
/// The storage belongs to the caller and the `Molecule` a builder returns
/// borrows it, so the scratch must outlive the call. Nothing here allocates: a
/// molecule is a handful of `inchi_Atom` records and this is where they live.
pub const Scratch = struct {
    atoms: [32]inchi.Atom = undefined,
    stereo0d: [8]inchi.Stereo0D = undefined,
    atom_count: usize = 0,
    stereo_count: usize = 0,

    /// Appends an atom and returns its index.
    pub fn addAtom(
        self: *Scratch,
        element: []const u8,
        hydrogens: inchi.ImplicitHydrogens,
    ) Error!usize {
        if (self.atom_count == self.atoms.len) return error.TooManyAtoms;
        const slot = self.atom_count;
        self.atoms[slot] = try inchi.atom(element, hydrogens);
        self.atom_count += 1;
        return slot;
    }

    /// Appends a bond between two atoms added earlier.
    pub fn bond(self: *Scratch, first: usize, second: usize, kind: inchi.BondType) Error!void {
        try inchi.connect(self.atoms[0..self.atom_count], first, second, kind, .none);
    }

    /// Appends a 0D stereo descriptor.
    pub fn addStereo(self: *Scratch, element: inchi.Stereo0D) Error!void {
        if (self.stereo_count == self.stereo0d.len) return error.TooManyStereoDescriptors;
        self.stereo0d[self.stereo_count] = element;
        self.stereo_count += 1;
    }

    /// The molecule built so far, borrowing this scratch.
    pub fn molecule(self: *Scratch) inchi.Molecule {
        return .{
            .atoms = self.atoms[0..self.atom_count],
            .stereo0d = self.stereo0d[0..self.stereo_count],
        };
    }
};

/// Narrows an atom number to `AT_NUM`, the `short` upstream stores atom and
/// neighbour indices in (`inchi_api.h:124`). Named `index` because that is what
/// it converts; the local slot counter in `addAtom` is named `slot` so the two
/// never collide.
fn index(atom: usize) i16 {
    return @intCast(atom);
}

/// Water, one oxygen and two implicit hydrogens. PubChem CID 962.
pub fn water(scratch: *Scratch) Error!inchi.Molecule {
    scratch.* = .{};
    _ = try scratch.addAtom("O", .{ .ordinary = 2 });
    return scratch.molecule();
}

/// Heavy water: the same single oxygen, with both hydrogens deuterium in
/// `num_iso_H[2]` instead of in `num_iso_H[0]`. PubChem CID 24602.
pub fn heavyWater(scratch: *Scratch) Error!inchi.Molecule {
    scratch.* = .{};
    _ = try scratch.addAtom("O", .{ .deuterium = 2 });
    return scratch.molecule();
}

/// Methane, one carbon and four implicit hydrogens. PubChem CID 297.
pub fn methane(scratch: *Scratch) Error!inchi.Molecule {
    scratch.* = .{};
    _ = try scratch.addAtom("C", .{ .ordinary = 4 });
    return scratch.molecule();
}

/// Ethanol as CH3-CH2-OH, atoms numbered from the methyl end.
/// PubChem CID 702.
pub fn ethanol(scratch: *Scratch) Error!inchi.Molecule {
    scratch.* = .{};
    const methyl = try scratch.addAtom("C", .{ .ordinary = 3 });
    const methylene = try scratch.addAtom("C", .{ .ordinary = 2 });
    const hydroxyl = try scratch.addAtom("O", .{ .ordinary = 1 });
    try scratch.bond(methyl, methylene, .single);
    try scratch.bond(methylene, hydroxyl, .single);
    return scratch.molecule();
}

/// The same ethanol, numbered from the hydroxyl end: every atom index is
/// different and the bonds point the other way, so an answer that changed
/// under relabelling would show up here.
pub fn ethanolRenumbered(scratch: *Scratch) Error!inchi.Molecule {
    scratch.* = .{};
    const hydroxyl = try scratch.addAtom("O", .{ .ordinary = 1 });
    const methylene = try scratch.addAtom("C", .{ .ordinary = 2 });
    const methyl = try scratch.addAtom("C", .{ .ordinary = 3 });
    try scratch.bond(hydroxyl, methylene, .single);
    try scratch.bond(methylene, methyl, .single);
    return scratch.molecule();
}

/// Benzene as a six-membered Kekule ring, one implicit hydrogen per carbon,
/// double bonds on the even edges. PubChem CID 241.
pub fn benzene(scratch: *Scratch) Error!inchi.Molecule {
    scratch.* = .{};
    for (0..6) |_| _ = try scratch.addAtom("C", .{ .ordinary = 1 });
    for (0..6) |i| try scratch.bond(i, (i + 1) % 6, if (i % 2 == 0) .double else .single);
    return scratch.molecule();
}

/// The same benzene with every adjacency list in the opposite direction: the
/// bond set is identical and only the order the neighbours are listed in
/// differs, which is the permutation an InChI has to be blind to.
pub fn benzeneRenumbered(scratch: *Scratch) Error!inchi.Molecule {
    scratch.* = .{};
    for (0..6) |_| _ = try scratch.addAtom("C", .{ .ordinary = 1 });
    for (0..6) |i| try scratch.bond(i, (i + 5) % 6, if (i % 2 == 0) .double else .single);
    return scratch.molecule();
}

/// Glycine, NH2-CH2-COOH, no stereo. PubChem CID 750.
pub fn glycine(scratch: *Scratch) Error!inchi.Molecule {
    scratch.* = .{};
    const amino = try scratch.addAtom("N", .{ .ordinary = 2 });
    const methylene = try scratch.addAtom("C", .{ .ordinary = 2 });
    const carboxyl = try scratch.addAtom("C", .none);
    const carbonyl = try scratch.addAtom("O", .none);
    const hydroxyl = try scratch.addAtom("O", .{ .ordinary = 1 });
    try scratch.bond(amino, methylene, .single);
    try scratch.bond(methylene, carboxyl, .single);
    try scratch.bond(carboxyl, carbonyl, .double);
    try scratch.bond(carboxyl, hydroxyl, .single);
    return scratch.molecule();
}

/// The same glycine as its zwitterion: NH3(+)-CH2-COO(-), with the two
/// charges written on the raw `Atom.charge` field rather than as two ions.
///
/// Upstream's neutralization rule (TECHMAN-5.1 and 5.2, `ichi_bns.c:5445-5484`)
/// takes the proton off the ammonium and puts one on the carboxylate, so the
/// identifier it produces is neutral glycine's, and it reports that it did:
/// `FLAG_PROTON_NPO_SIMPLE_REMOVED` and `FLAG_PROTON_AC_SIMPLE_ADDED` are both
/// in `FLAG_NORM_CONSIDER_TAUT` and neither is `FLAG_PROTON_CHARGE_CANCEL`,
/// so `ichimak2.c:1162-1168` writes "Proton(s) added/removed" into the
/// message. That message is what makes the run a `warning` rather than an
/// error, with an identifier still in hand.
pub fn glycineZwitterion(scratch: *Scratch) Error!inchi.Molecule {
    scratch.* = .{};
    const amino = try scratch.addAtom("N", .{ .ordinary = 3 });
    const methylene = try scratch.addAtom("C", .{ .ordinary = 2 });
    const carboxyl = try scratch.addAtom("C", .none);
    const carbonyl = try scratch.addAtom("O", .none);
    const hydroxyl = try scratch.addAtom("O", .none);
    scratch.atoms[amino].charge = 1;
    scratch.atoms[hydroxyl].charge = -1;
    try scratch.bond(amino, methylene, .single);
    try scratch.bond(methylene, carboxyl, .single);
    try scratch.bond(carboxyl, carbonyl, .double);
    try scratch.bond(carboxyl, hydroxyl, .single);
    return scratch.molecule();
}

/// Alanine, CH3-CH(NH2)-COOH, with its one stereocentre given as a tetrahedral
/// 0D descriptor in `parity`.
///
/// The stereocentre has three explicit bonds and one implicit hydrogen, which
/// is upstream's three-neighbour form: the central atom is written into the
/// first slot of the quadruple and stands for the implicit hydrogen
/// (`inchi_api.h:244-270`). The four substituents are CH3, NH2, COOH and that
/// hydrogen.
pub fn alanine(scratch: *Scratch, parity: inchi.StereoParity0D) Error!inchi.Molecule {
    scratch.* = .{};
    const methyl = try scratch.addAtom("C", .{ .ordinary = 3 });
    const alpha = try scratch.addAtom("C", .{ .ordinary = 1 });
    const amino = try scratch.addAtom("N", .{ .ordinary = 2 });
    const carboxyl = try scratch.addAtom("C", .none);
    const carbonyl = try scratch.addAtom("O", .none);
    const hydroxyl = try scratch.addAtom("O", .{ .ordinary = 1 });
    try scratch.bond(methyl, alpha, .single);
    try scratch.bond(alpha, amino, .single);
    try scratch.bond(alpha, carboxyl, .single);
    try scratch.bond(carboxyl, carbonyl, .double);
    try scratch.bond(carboxyl, hydroxyl, .single);
    try scratch.addStereo(inchi.tetrahedralStereo(
        index(alpha),
        .{ index(alpha), index(methyl), index(amino), index(carboxyl) },
        parity,
    ));
    return scratch.molecule();
}

/// But-2-ene, CH3-CH=CH-CH3, with the stereogenic double bond given as a
/// stereobond 0D descriptor in `parity`.
///
/// The quadruple is `{#CH3, #A, #B, #CH3}` in the order `inchi_api.h:198-208`
/// requires, and the central atom is `no_atom` because a stereobond has none.
pub fn but2ene(scratch: *Scratch, parity: inchi.StereoParity0D) Error!inchi.Molecule {
    scratch.* = .{};
    const first_methyl = try scratch.addAtom("C", .{ .ordinary = 3 });
    const first_end = try scratch.addAtom("C", .{ .ordinary = 1 });
    const second_end = try scratch.addAtom("C", .{ .ordinary = 1 });
    const second_methyl = try scratch.addAtom("C", .{ .ordinary = 3 });
    try scratch.bond(first_methyl, first_end, .single);
    try scratch.bond(first_end, second_end, .double);
    try scratch.bond(second_end, second_methyl, .single);
    try scratch.addStereo(inchi.doubleBondStereo(
        index(first_methyl),
        index(first_end),
        index(second_end),
        index(second_methyl),
        parity,
    ));
    return scratch.molecule();
}

/// A molecule whose only atom carries the pseudo-element symbol `*`.
///
/// `GetStdINCHI` and `GetINCHI` both refuse it before generating anything
/// (`inchi_dll.c:247-250` and `inchi_dll.c:275-278`), because neither the
/// standard nor the non-standard entry point can represent a star atom; only
/// `GetINCHIEx` can, by rewriting it to `Zz`, which is
/// `inchi.fromMolecule.extended`. That one needs mutable atoms, so a caller
/// passes `scratch.atoms[0..scratch.atom_count]` rather than the `Molecule`
/// this returns.
pub fn pseudoAtom(scratch: *Scratch) Error!inchi.Molecule {
    scratch.* = .{};
    _ = try scratch.addAtom("*", .none);
    return scratch.molecule();
}
