//! Molecule fixtures for the tests and smoke program.

/// Options used by upstream's strict identifier conversion.
/// The option prefix is `/` on Windows and `-` elsewhere.
pub const strict_options: [:0]const u8 = switch (@import("builtin").target.os.tag) {
    .windows => "/FixedH /RecMet /SUU /SLUUD",
    else => "-FixedH -RecMet -SUU -SLUUD",
};

/// Upstream's option for omitting AuxInfo, with the target-specific prefix.
pub const no_aux_options: [:0]const u8 = switch (@import("builtin").target.os.tag) {
    .windows => "/AuxNone",
    else => "-AuxNone",
};

const inchi = @import("inchi");

/// Fixture errors and errors returned by the InChI facade.
pub const Error = error{
    TooManyAtoms,
    TooManyStereoDescriptors,
} || inchi.Error;

/// Fixed storage borrowed by each `Molecule` returned from a builder.
/// Keep it alive while the molecule is in use.
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

/// Ethanol with atom numbering reversed, for canonicalization tests.
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

/// Benzene with reverse adjacency order, for canonicalization tests.
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

/// Glycine zwitterion; upstream neutralizes it and reports a warning.
/// PubChem CID 750.
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

/// Alanine with a tetrahedral 0D descriptor set by `parity`.
/// An implicit hydrogen occupies the first neighbour slot upstream.
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

/// But-2-ene with a stereogenic double-bond descriptor set by `parity`.
/// The neighbour order is `{#CH3, #A, #B, #CH3}`; `central_atom` is `no_atom`.
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

/// A molecule with one pseudo-element atom (`*`).
/// Extended generation rewrites it to `Zz`; `NPZz` controls whether it is accepted.
pub fn pseudoAtom(scratch: *Scratch) Error!inchi.Molecule {
    scratch.* = .{};
    _ = try scratch.addAtom("*", .none);
    return scratch.molecule();
}
