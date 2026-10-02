//! Zig facade over the IUPAC/InChI `libinchi` C library (release v1.07.5).
//!
//! No chemistry is reimplemented here. Every identifier, structure and key this
//! module produces comes out of the canonical C in
//! `INCHI-1-SRC/INCHI_API/libinchi/src`, reached through `pub const c`, the
//! module `b.addTranslateC` builds from `translate.h` over `inchi_api.h`.
//!
//! ## What this module is for
//!
//! The C API is a set of free functions over caller-allocated structs whose
//! contents the caller must then release with a matching `Free*` call. Three
//! things are easy to get wrong in that shape and are what this module closes:
//!
//!   * **Ownership.** `GetStdINCHI` allocates `szInChI`, `szMessage` and
//!     `szLog`; `GetINCHI` allocates the same three; `GetStructFrom*`
//!     additionally allocates the atom and 0D-stereo arrays. `Output` and
//!     `Structure` carry which entry point produced them (`Origin`) and their
//!     `deinit` calls back through that same entry point, so the release always
//!     pairs with the creator. No string is copied on the way out and no Zig
//!     allocator is involved: the bytes come from upstream's `inchi_malloc` and
//!     go back to it.
//!   * **Status.** Upstream's return value is a *classification*, not a boolean:
//!     `inchi_Ret_WARNING` (1) means an identifier was produced and something
//!     worth reading is in `szMessage`. It is not an error and this module never
//!     turns it into one. `Output.status` carries the exact code, including the
//!     codes `RetValGetINCHI` never names, and `Output.message` carries
//!     upstream's own words on the failure path.
//!   * **Bounds.** `elname` is six bytes, an adjacency list is twenty entries
//!     long, `num_atoms` is a `short`, an InChIKey is 27 characters. Each of
//!     those is checked where a caller can act on it, with an ordinary
//!     comparison rather than an assertion.
//!
//! ## What the C leaves to the caller
//!
//!   * `Atom` is the raw `inchi_Atom`, so charge, radical, isotopic mass and the
//!     3D coordinates are written on it directly and mean exactly what
//!     `inchi_api.h:134-162` says they mean.
//!   * `ImplicitHydrogens` fills `num_iso_H[0..4]`, including the
//!     `ordinary = -1` sentinel that asks InChI to add the hydrogens itself
//!     (`inchi_api.h:151-157`).
//!   * `connect` appends a bond to *both* adjacency lists. Upstream accepts a
//!     bond in one list or in both (`inchi_api.h:174-177`); writing both is what
//!     every converter upstream ships does, and it keeps `num_bonds` and the
//!     three parallel arrays in agreement.
//!   * Coordinates. Leave them all zero and InChI takes the 0D parities in the
//!     molecule as the stereochemical input, which is the rule stated at
//!     `inchi_api.h:297-300`.
//!
//! ## Borrowed input
//!
//! `Molecule` borrows the atom and stereo arrays for the duration of the call.
//! The option string is borrowed too: upstream copies it before parsing
//! (`inchi_dll.c:476-480`, `inchi_dll_a.c:314-321`, `inchi_dll.c:2216-2219`,
//! `inchi_dll.c:2586-2589`), so a NUL-terminated literal is safe to hand over
//! even though the C declares the field `char *`.
//!
//! What is *not* borrowed is the `inchi_Input` / `inchi_InputINCHI` struct
//! itself: C declares every one of these parameters non-const
//! (`inchi_dll.c:242`, `inchi_dll.c:2114`), so each call builds that struct in
//! a mutable local of its own and hands C a pointer to it. It is five fields on
//! the stack -- no allocation, and no copy of the borrowed arrays.
//!
//! ## `c` is the escape hatch
//!
//! The complete translated declaration set is public: the IXA builder objects,
//! `MakeINCHIFromMolfileText`, `GetINCHIEx`, the polymer and V3000 extensions,
//! and the whole 0D-stereo surface. A caller going through `c` gets upstream's
//! behaviour with none of the contracts above.

const std = @import("std");

/// Every declaration `b.addTranslateC` produced from `inchi_api.h` (which ends
/// with `#include "ixa.h"`), i.e. upstream's ABI exactly as published.
pub const c = @import("c");

/// Upstream's `inchi_Atom`, unchanged. Coordinates, charge, radical and
/// isotopic mass are written on this type directly.
pub const Atom = c.inchi_Atom;

/// Upstream's `inchi_Stereo0D`, unchanged.
pub const Stereo0D = c.inchi_Stereo0D;

/// `MAXVAL`, the length of an adjacency list (`inchi_api.h:105`).
pub const max_bonds_per_atom: usize = c.MAXVAL;

/// `ATOM_EL_LEN`, the length of `Atom.elname` (`inchi_api.h:106`).
pub const element_symbol_len: usize = c.ATOM_EL_LEN;

/// `NO_ATOM`, upstream's sentinel for "no central atom"
/// (`inchi_api.h:404`). `doubleBondStereo` writes it for you; nothing
/// normalises it away.
pub const no_atom: i16 = c.NO_ATOM;

/// `inchi_BondType` (`inchi_api.h:67-73`).
pub const BondType = enum(i8) {
    none = 0,
    single = 1,
    double = 2,
    triple = 3,
    /// Upstream marks this bond type "avoid by all means"; a Kekule ring is
    /// the honest way to write an aromatic ring.
    altern = 4,
};

/// `inchi_BondStereo2D` (`inchi_api.h:74-86`), the 2D wedge notation. Zero
/// coordinates make 0D parities authoritative instead, so this is only read
/// when a caller supplies coordinates.
pub const BondStereo2D = enum(i8) {
    none = 0,
    single_1up = 1,
    single_1either = 4,
    single_1down = 6,
    single_2up = -1,
    single_2either = -4,
    single_2down = -6,
    double_either = 3,
};

/// `inchi_StereoType0D` (`inchi_api.h:407-412`).
pub const StereoType0D = enum(i8) {
    none = 0,
    double_bond = 1,
    tetrahedral = 2,
    allene = 3,
};

/// `inchi_StereoParity0D` (`inchi_api.h:415-422`).
///
/// The tetrahedral and stereobond values are relative to the order of
/// `Stereo0D.neighbor` and mean nothing outside it: `inchi_api.h:255-256`
/// states that `even` is the arrangement in which the neighbours after the
/// first read clockwise when seen from the first.
pub const StereoParity0D = enum(i8) {
    none = 0,
    odd = 1,
    even = 2,
    unknown = 3,
    undefined = 4,
};

/// Upstream's `RetValGetINCHI` (`inchi_api.h:722-733`).
///
/// This is a value channel, not an error channel: `warning` means an
/// identifier exists and `Output.message` says why it is qualified. The `_`
/// field keeps the codes `RetValGetINCHI` does not name -- `inchi_Ret_SKIP`
/// (-2) and `inchi_Ret_BREAK` (-100), `inchi_api.h:724-725` -- representable
/// rather than panicking, because upstream is free to return them and a caller
/// deserves to see what came back.
pub const Status = enum(c_int) {
    /// `inchi_Ret_EOF`: no structural data was provided.
    no_data = -1,
    /// `inchi_Ret_OKAY`: identifier produced, nothing to report.
    okay = 0,
    /// `inchi_Ret_WARNING`: identifier produced, and `message` says what was
    /// qualified. Not a failure.
    warning = 1,
    /// `inchi_Ret_ERROR`: nothing was produced; `message` says why.
    rejected = 2,
    /// `inchi_Ret_FATAL`: nothing was produced, typically allocation failure.
    fatal = 3,
    /// `inchi_Ret_UNKNOWN`.
    unknown = 4,
    /// `inchi_Ret_BUSY`: the previous call has not returned yet.
    busy = 5,
    _,
};

/// Which upstream entry point allocated a result, and therefore which one
/// releases it.
///
/// `FreeStdINCHI` is literally `FreeINCHI` (`inchi_dll.c:183-186`) and
/// `FreeStructFromStdINCHI` is literally `FreeStructFromINCHI`
/// (`inchi_dll.c:195-198`), so the tag changes no behaviour today. It is kept
/// because the pairing that matters is the one the creator promised in the
/// header, and `deinit` should honour that promise rather than a second entry
/// point that happens to agree today.
pub const Origin = enum { standard, non_standard };

/// Failures this module raises itself. Upstream's own statuses are not in this
/// set: they arrive as `Output.status` / `Structure.status` with their message
/// attached, because a warning is not a failure and an error is more than a
/// boolean.
pub const Error = error{
    /// The element symbol does not fit `Atom.elname`, which is
    /// `element_symbol_len` bytes including the terminator.
    ElementSymbolTooLong,
    /// A bond named an atom outside the molecule, or named the same atom twice.
    AtomIndexOutOfRange,
    /// An adjacency list already holds `max_bonds_per_atom` entries, so this
    /// bond has nowhere to go in one of the two atoms.
    TooManyNeighbors,
    /// More atoms than `inchi_Input.num_atoms`, an `AT_NUM`, can count.
    TooManyAtoms,
};

/// `Atom.num_iso_H[0..4]` (`inchi_api.h:151-157`).
///
/// All four counters are implicit hydrogens, so the total is their sum.
/// `ordinary = -1` is upstream's sentinel: it means "work the hydrogens out
/// yourself", which is what `SetAtomAndBondProperties` acts on when the
/// `/DoNotAddH` option is absent (`inchi_dll.c:1965-1970`).
pub const ImplicitHydrogens = struct {
    /// Implicit hydrogens of natural isotopic abundance. `-1` asks InChI to
    /// add them.
    ordinary: i8 = 0,
    /// Implicit protium, isotope 1.
    protium: i8 = 0,
    /// Implicit deuterium, isotope 2.
    deuterium: i8 = 0,
    /// Implicit tritium, isotope 3.
    tritium: i8 = 0,

    /// No implicit hydrogens at all.
    pub const none: ImplicitHydrogens = .{};
    /// Let InChI decide, upstream's `num_iso_H[0] = -1`.
    pub const automatic: ImplicitHydrogens = .{ .ordinary = -1 };
};

/// A structure to hand to `GetINCHI` or `GetStdINCHI`.
///
/// Both arrays are borrowed and must outlive the call; nothing here copies
/// them, and nothing here frees them: they belong to whoever filled them.
///
/// `atoms` is `[]const Atom` because `GetStdINCHI` and `GetINCHI` do not write
/// through it: both copy the input into the library's own `inp_ATOM` array
/// before touching anything (`inchi_dll.c:1961-1996`). That is what lets a
/// structure rebuilt from an identifier go straight back into a `Molecule`
/// with no copy at all. The one upstream entry point that does write is
/// `GetINCHIEx`, which rewrites `*` element names to `Zz` in place
/// (`inchi_dll.c:330-336`); it is reachable through `c` and deliberately not
/// wrapped here, because wrapping it would make this contract a lie.
pub const Molecule = struct {
    atoms: []const Atom,
    /// 0D stereo descriptors. Empty means "no 0D stereo", which is what a NULL
    /// pointer with `num_stereo0D == 0` means upstream
    /// (`readinch.c:150`).
    stereo0d: []const Stereo0D = &.{},
    /// Upstream's own option string, verbatim: space delimited, every option
    /// preceded by `/` or `-` depending on the platform the caller builds for.
    /// Pass it through unchanged; this module adds and removes no option.
    options: ?[:0]const u8 = null,
};

/// Whether `GetINCHIKeyFromINCHI` should also produce the two SHA-256
/// extensions. They are two independent 256-bit digests of the two halves of
/// the identifier (`ikey_dll.c:459-475`), not a shorter form of the key.
pub const Hashes = struct {
    first: bool = false,
    second: bool = false,
};

/// Failures of `GetINCHIKeyFromINCHI` and `GetStdINCHIKeyFromStdINCHI`, one
/// error per `INCHIKEY_*` code the two functions can return
/// (`inchi_api.h:1050-1056`).
pub const KeyError = error{
    /// `INCHIKEY_UNKNOWN_ERROR`, and the landing place for a code this
    /// release does not name.
    UnknownFailure,
    // `INCHIKEY_EMPTY_INPUT` is absent on purpose: upstream returns it only for
    // a NULL source pointer (`ikey_dll.c:162-165`), and this module always hands
    // C a valid pointer, so a zero-length identifier arrives as
    // `InvalidInchiPrefix` instead.
    /// `INCHIKEY_INVALID_INCHI_PREFIX`.
    InvalidInchiPrefix,
    /// `INCHIKEY_NOT_ENOUGH_MEMORY`.
    NotEnoughMemory,
    /// `INCHIKEY_INVALID_INCHI`.
    InvalidInchi,
    /// `INCHIKEY_INVALID_STD_INCHI`: the identifier is not a standard InChI,
    /// which only `standardKey` can report.
    InvalidStdInchi,
};

/// `RetValCheckINCHI` (`inchi_api.h:751-760`).
///
/// `CheckINCHI` returns a plain `int`, so the enum has an explicit integer
/// backing type and a `_` field: a code this release does not name arrives as
/// an unnamed value the caller can report, exactly as `Status` reports an
/// unnamed `RetValGetINCHI`, rather than trapping in the middle of a report.
pub const IdentifierVerdict = enum(c_int) {
    standard,
    non_standard,
    beta,
    invalid_prefix,
    invalid_version,
    invalid_layout,
    /// `INCHI_FAIL_I2I`: the strict round trip through `GetINCHIfromINCHI`
    /// did not reproduce the input (`inchi_dll.c:954-981`).
    conversion_failed,
    _,
};

/// `RetValCheckINCHIKeyv` (`inchi_api.h:1060-1067`). `CheckINCHIKey` likewise
/// returns a plain `int`, and is declared for the same reason as
/// `IdentifierVerdict`.
pub const KeyVerdict = enum(c_int) {
    standard,
    non_standard,
    invalid_length,
    invalid_layout,
    invalid_version,
    _,
};

/// `szINCHIKey` must be at least 28 bytes (`inchi_api.h:1101`): 27 characters
/// plus the terminator. `CheckINCHIKey` rejects anything that is not exactly 27
/// characters long (`ikey_dll.c:521-525`).
pub const key_buffer_len = 28;

/// Each `szXtra` buffer must hold 64 characters plus the terminator
/// (`inchi_api.h:1104-1107`).
pub const hash_buffer_len = 65;

// ---------------------------------------------------------------------------
// Results
// ---------------------------------------------------------------------------

/// What one `GetINCHI` / `GetStdINCHI` / `GetINCHIfromINCHI` call produced.
///
/// Every string is a borrowed window on memory upstream allocated, and every
/// one of them is NUL-terminated by upstream itself, so each accessor hands
/// back a sentinel slice rather than a plain one and a caller can pass the
/// identifier straight to `key`, `standardKey`, `checkIdentifier` or back to
/// `fromIdentifier` with no copy in between. The proof is on `spanOrNull`.
///
/// `auxInfo` is not a second allocation: `produce_generation_output` splits
/// one buffer in two, writing a NUL where the line break was and pointing
/// `szAuxInfo` at the byte after it (`inchi_dll.c:764-777`), and `FreeINCHI`
/// frees `szInChI`, `szLog` and `szMessage` only (`inchi_dll.c:160-171`). So
/// `auxInfo` stays valid exactly as long as the whole value does, and must
/// never be freed on its own.
pub const Output = struct {
    raw: c.inchi_Output,
    status: Status,
    origin: Origin,

    /// The identifier, or null when upstream produced none. A `warning`
    /// status always has one.
    pub fn identifier(self: *const Output) ?[:0]const u8 {
        return spanOrNull(self.raw.szInChI);
    }

    /// The `AuxInfo=` line, or null when the run produced none (no AuxInfo
    /// layer, or `/AuxNone`). It is the tail of the same allocation as
    /// `identifier`, not a copy of it.
    pub fn auxInfo(self: *const Output) ?[:0]const u8 {
        return spanOrNull(self.raw.szAuxInfo);
    }

    /// Upstream's error or warning text, or "" when it wrote none. Retained on
    /// the failure path as well, so a rejection arrives with its reason.
    pub fn message(self: *const Output) [:0]const u8 {
        return spanOrNull(self.raw.szMessage) orelse "";
    }

    /// The recognised options and the human-readable log, or "".
    pub fn log(self: *const Output) [:0]const u8 {
        return spanOrNull(self.raw.szLog) orelse "";
    }

    /// Whether the identifier is usable but qualified. This is the state a
    /// caller must not treat as a failure: `identifier()` is still populated.
    pub fn isWarning(self: *const Output) bool {
        return self.status == .warning;
    }

    /// Releases every string through the entry point that allocated them.
    pub fn deinit(self: *Output) void {
        switch (self.origin) {
            .standard => c.FreeStdINCHI(&self.raw),
            .non_standard => c.FreeINCHI(&self.raw),
        }
    }
};

/// Upstream's `WarningFlags`, `unsigned long[2][2]` (`inchi_api.h:646-652`).
///
/// `[x][0]` is the disconnected/normal layer, `[x][1]` the reconnected layer,
/// `[0][*]` the fixed-H layer and `[1][*]` the mobile-H layer. `INCHIDIFF` in
/// `ichicant.h` names the bits.
pub const Warnings = [2][2]c_ulong;

/// What one `GetStructFromStdINCHI` / `GetStructFromINCHI` call produced.
///
/// The atom and 0D-stereo arrays are upstream allocations inside one buffer
/// each; they are borrowed, valid until `deinit`, and feed straight back into a
/// `Molecule` for the opposite direction.
pub const Structure = struct {
    raw: c.inchi_OutputStruct,
    status: Status,
    origin: Origin,

    /// The atoms, borrowed from upstream. Hydrogens are implicit unless the
    /// identifier listed them explicitly, exactly as upstream reports them,
    /// and empty when the call produced no structure at all.
    pub fn atoms(self: *const Structure) []const Atom {
        return borrowedArray(Atom, self.raw.atom, self.raw.num_atoms);
    }

    /// The 0D stereo descriptors, borrowed from upstream, and empty when the
    /// identifier carried none.
    pub fn stereo0d(self: *const Structure) []const Stereo0D {
        return borrowedArray(Stereo0D, self.raw.stereo0D, self.raw.num_stereo0D);
    }

    /// Upstream's error or warning text, or "". Upstream's own buffer, so the
    /// terminator is upstream's: `ReadWriteInChI` writes one on entry and
    /// again after every copy it makes (`ichiread.c:715`, `ichiread.c:11586`).
    pub fn message(self: *const Structure) [:0]const u8 {
        return spanOrNull(self.raw.szMessage) orelse "";
    }

    /// Upstream's log, or "". Terminated the same way as `Output.log`.
    pub fn log(self: *const Structure) [:0]const u8 {
        return spanOrNull(self.raw.szLog) orelse "";
    }

    /// The per-layer difference flags upstream set while rebuilding the
    /// structure.
    pub fn warnings(self: *const Structure) Warnings {
        return self.raw.WarningFlags;
    }

    /// Whether any difference flag is set, which is also what makes upstream
    /// return `inchi_Ret_WARNING` here (`inchi_dll.c:2829-2840`).
    pub fn isWarning(self: *const Structure) bool {
        return self.status == .warning;
    }

    /// Releases the arrays and strings through the entry point that allocated
    /// them.
    pub fn deinit(self: *Structure) void {
        switch (self.origin) {
            .standard => c.FreeStructFromStdINCHI(&self.raw),
            .non_standard => c.FreeStructFromINCHI(&self.raw),
        }
    }
};

/// An InChIKey and, on request, its two SHA-256 extensions.
///
/// The buffers are fixed at the sizes the header asks for, so there is nothing
/// to size and nothing to overflow. They live in the returned value, so the key
/// does not borrow from anything the caller has to keep alive.
pub const KeyResult = struct {
    key: [key_buffer_len]u8 = @splat(0),
    first_hash: ?[hash_buffer_len]u8 = null,
    second_hash: ?[hash_buffer_len]u8 = null,

    /// The 27-character key, without its terminator.
    pub fn keyText(self: *const KeyResult) [:0]const u8 {
        return terminated(&self.key);
    }

    /// The first extension hash, when it was asked for.
    pub fn firstHash(self: *const KeyResult) ?[:0]const u8 {
        if (self.first_hash) |*buffer| return terminated(buffer);
        return null;
    }

    /// The second extension hash, when it was asked for.
    pub fn secondHash(self: *const KeyResult) ?[:0]const u8 {
        if (self.second_hash) |*buffer| return terminated(buffer);
        return null;
    }
};

// ---------------------------------------------------------------------------
// Building a molecule
// ---------------------------------------------------------------------------

/// A zeroed atom of `symbol` with the given implicit hydrogens.
///
/// `symbol` is the chemical element name upstream stores in `Atom.elname`,
/// "C", "Cl", "Zz"; it must fit `element_symbol_len` bytes including the
/// terminator, which is the whole length contract the header states
/// (`inchi_api.h:147`). Everything else starts at zero: no coordinates (so
/// InChI reads the molecule's 0D parities, `inchi_api.h:297-300`), no bonds,
/// no charge, no radical, no isotopic mass. Those are raw fields on the
/// returned `Atom` for a caller to set.
pub fn atom(symbol: []const u8, hydrogens: ImplicitHydrogens) Error!Atom {
    if (symbol.len + 1 > element_symbol_len) return error.ElementSymbolTooLong;
    var result: Atom = std.mem.zeroes(Atom);
    for (symbol, 0..) |byte, index| result.elname[index] = byte;
    result.num_iso_H[0] = hydrogens.ordinary;
    result.num_iso_H[1] = hydrogens.protium;
    result.num_iso_H[2] = hydrogens.deuterium;
    result.num_iso_H[3] = hydrogens.tritium;
    return result;
}

/// Appends a bond between `first` and `second` to both adjacency lists.
///
/// Upstream accepts a bond recorded in one atom's list or in both
/// (`inchi_api.h:174-177`); both is what keeps `num_bonds`, `neighbor`,
/// `bond_type` and `bond_stereo` describing the same set of connections, and it
/// is what every converter upstream ships produces. The bond type is written
/// into both lists unchanged; `bond_stereo` is left at
/// `INCHI_BOND_STEREO_NONE`, because with zero coordinates the 2D wedge is not
/// read at all.
///
/// Either the bond lands in both lists or in neither: both capacities are
/// checked before anything is written.
pub fn connect(
    atoms: []Atom,
    first: usize,
    second: usize,
    kind: BondType,
    stereo2d: BondStereo2D,
) Error!void {
    if (first >= atoms.len or second >= atoms.len or first == second) {
        return error.AtomIndexOutOfRange;
    }
    if (used(atoms[first].num_bonds) >= max_bonds_per_atom or
        used(atoms[second].num_bonds) >= max_bonds_per_atom)
    {
        return error.TooManyNeighbors;
    }
    append(&atoms[first], second, kind, stereo2d);
    append(&atoms[second], first, kind, stereo2d);
}

/// A tetrahedral 0D stereo descriptor.
///
/// `neighbours` is the quadruple in the order the parity refers to. Four
/// explicit neighbours are listed as `{#W, #X, #Y, #Z}` with `central` at the
/// centre; a stereocentre with an implicit hydrogen writes `central` itself
/// into the first slot, which is upstream's form for that case
/// (`inchi_api.h:244-270`).
pub fn tetrahedralStereo(
    central: i16,
    neighbours: [4]i16,
    parity: StereoParity0D,
) Stereo0D {
    var result: Stereo0D = std.mem.zeroes(Stereo0D);
    result.neighbor = neighbours;
    result.central_atom = central;
    result.type = @intFromEnum(StereoType0D.tetrahedral);
    result.parity = @intFromEnum(parity);
    return result;
}

/// A stereogenic double bond 0D stereo descriptor. This is the
/// `INCHI_StereoType_DoubleBond` form only: an allene or cumulene is a
/// different descriptor and is not built here.
///
/// The quadruple is `{#X, #A, #B, #Y}`: the neighbour of the first end atom,
/// that end atom, the second end atom, and the neighbour of the second end
/// atom (`inchi_api.h:198-208`). `central_atom` is `no_atom`, upstream's
/// sentinel for "no central atom" (`inchi_api.h:404`), because a stereobond
/// has none.
///
/// The allene form keeps the same quadruple but sets
/// `type = INCHI_StereoType_Allene` and names the middle atom of the odd
/// double-bond chain in `central_atom` instead (`inchi_api.h:230-243`). Write
/// that descriptor on a `Stereo0D` directly -- the struct is public -- rather
/// than expecting this function to fill it in.
pub fn doubleBondStereo(x: i16, a: i16, b: i16, y: i16, parity: StereoParity0D) Stereo0D {
    var result: Stereo0D = std.mem.zeroes(Stereo0D);
    result.neighbor = .{ x, a, b, y };
    result.central_atom = no_atom;
    result.type = @intFromEnum(StereoType0D.double_bond);
    result.parity = @intFromEnum(parity);
    return result;
}

// ---------------------------------------------------------------------------
// Structure -> identifier
// ---------------------------------------------------------------------------

/// Structure to identifier: upstream's `GetStdINCHI` and `GetINCHI`.
///
/// Both take `inchi_Input *`, a pointer C declares non-const
/// (`inchi_dll.c:242`, `inchi_dll.c:270`), so the `inchi_Input` the call
/// hands over is a mutable local this function owns rather than a constant:
/// the declaration is upstream's and the binding has to match it. Nothing is
/// allocated for it and the caller's atoms are not copied -- upstream reads
/// every field out of the struct into its own `inchi_InputEx` before it uses
/// any of them (`inchi_dll.c:252-256`) and writes none of them back.
pub const fromMolecule = struct {
    /// Upstream's `GetStdINCHI`: a standard identifier and nothing else.
    ///
    /// Any creation option that would make the identifier non-standard is
    /// cleared before generation, whatever `Molecule.options` asks for
    /// (`inchi_dll.c:541-587`), so this and `full` differ only in whether they
    /// can produce a non-standard identifier, not in how they treat one input.
    pub fn standard(molecule: Molecule) Error!Output {
        var input = try inputStruct(molecule);
        var raw: c.inchi_Output = std.mem.zeroes(c.inchi_Output);
        const code = c.GetStdINCHI(&input, &raw);
        return .{ .raw = raw, .status = statusFrom(code), .origin = .standard };
    }

    /// Upstream's `GetINCHI`. With no creation or stereo-modifying option this
    /// produces a standard identifier; `Molecule.options` may ask for a
    /// non-standard one and upstream will then produce exactly that.
    pub fn full(molecule: Molecule) Error!Output {
        var input = try inputStruct(molecule);
        var raw: c.inchi_Output = std.mem.zeroes(c.inchi_Output);
        const code = c.GetINCHI(&input, &raw);
        return .{ .raw = raw, .status = statusFrom(code), .origin = .non_standard };
    }
};

// ---------------------------------------------------------------------------
// Identifier -> structure, and identifier -> identifier
// ---------------------------------------------------------------------------

/// The directions that start from an identifier string.
///
/// `GetINCHIfromINCHI` and both `GetStructFrom*` entry points take
/// `inchi_InputINCHI *` (`inchi_dll.c:2114`, `inchi_dll.c:2461`,
/// `inchi_dll.c:2856`), the same non-const declaration `GetStdINCHI` has, so
/// the struct handed over is a mutable local here for the same reason. Only
/// the two pointers in it are borrowed: upstream reads `szInChI` and
/// `szOptions` (`inchi_dll.c:2296-2309`, `inchi_dll.c:2660-2695`) and copies
/// `szOptions` into a buffer of its own before parsing it
/// (`inchi_dll.c:2212-2219`, `inchi_dll.c:2579-2589`).
pub const fromIdentifier = struct {
    /// Upstream's `GetStructFromStdINCHI`. A non-standard identifier is refused
    /// with `Status.rejected` before any conversion is attempted
    /// (`inchi_dll.c:2464-2476`).
    pub fn standard(text: [:0]const u8, options: ?[:0]const u8) Error!Structure {
        var input = identifierInput(text, options);
        // `GetStructFromStdINCHI` returns `inchi_Ret_ERROR` without touching
        // `*outStruct` at all on that early path (`inchi_dll.c:2475`), so the
        // struct is zeroed here: releasing it afterwards must not free whatever
        // happened to be on the stack.
        var raw: c.inchi_OutputStruct = std.mem.zeroes(c.inchi_OutputStruct);
        const code = c.GetStructFromStdINCHI(&input, &raw);
        return .{ .raw = raw, .status = statusFrom(code), .origin = .standard };
    }

    /// Upstream's `GetStructFromINCHI`, which accepts a standard or a
    /// non-standard identifier.
    pub fn full(text: [:0]const u8, options: ?[:0]const u8) Error!Structure {
        var input = identifierInput(text, options);
        var raw: c.inchi_OutputStruct = std.mem.zeroes(c.inchi_OutputStruct);
        const code = c.GetStructFromINCHI(&input, &raw);
        return .{ .raw = raw, .status = statusFrom(code), .origin = .non_standard };
    }

    /// Upstream's `GetINCHIfromINCHI`: regenerate an identifier from an
    /// identifier, which is how a caller validates one without re-deriving it.
    ///
    /// `options` filters layers, exactly as the header describes: omitting
    /// `/FixedH` and `/RecMet` drops those layers, and passing them keeps all
    /// of them (`inchi_api.h:889-901`). Those two clear the standard flag as
    /// the options are parsed (`ichiparm.c:350-364`), so a conversion made
    /// with them answers `InChI=1/...`; the standard `InChI=1S/...` is what
    /// no options at all produces. Upstream runs `CheckINCHI` on the input
    /// first and refuses anything that is not a well-formed identifier
    /// (`inchi_dll.c:2296-2312`).
    pub fn converted(text: [:0]const u8, options: ?[:0]const u8) Error!Output {
        var input = identifierInput(text, options);
        var raw: c.inchi_Output = std.mem.zeroes(c.inchi_Output);
        const code = c.GetINCHIfromINCHI(&input, &raw);
        return .{ .raw = raw, .status = statusFrom(code), .origin = .non_standard };
    }
};

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------

/// Upstream's `CheckINCHI`.
///
/// `strict` is upstream's own switch: false checks the layout only, true
/// regenerates the identifier with `GetINCHIfromINCHI` and requires the result
/// to equal the input (`inchi_dll.c:954-981`), which is a stronger claim and
/// can fail on a string the layout check accepts. It does fail on every
/// standard identifier: the option string that regeneration is built with asks
/// for the Fixed-H and Reconnected layers, and asking for either turns the
/// standard flag off (`ichiparm.c:350-364`), so what comes back is the
/// `InChI=1/...` form of the same compound. That verdict is
/// `conversion_failed`, and it says nothing about whether the identifier is
/// well formed.
///
/// A code upstream returns that this release does not name arrives as an
/// unnamed `IdentifierVerdict` value rather than as a panic.
pub fn checkIdentifier(text: [:0]const u8, strict: bool) IdentifierVerdict {
    const source: [*c]const u8 = text.ptr;
    const code = c.CheckINCHI(source, if (strict) 1 else 0);
    return switch (code) {
        c.INCHI_VALID_STANDARD => .standard,
        c.INCHI_VALID_NON_STANDARD => .non_standard,
        c.INCHI_VALID_BETA => .beta,
        c.INCHI_INVALID_PREFIX => .invalid_prefix,
        c.INCHI_INVALID_VERSION => .invalid_version,
        c.INCHI_INVALID_LAYOUT => .invalid_layout,
        c.INCHI_FAIL_I2I => .conversion_failed,
        else => @enumFromInt(code),
    };
}

/// Upstream's `CheckINCHIKey`. A code this release does not name arrives as an
/// unnamed `KeyVerdict` value rather than as a panic.
pub fn checkKey(text: [:0]const u8) KeyVerdict {
    const source: [*c]const u8 = text.ptr;
    const code = c.CheckINCHIKey(source);
    return switch (code) {
        c.INCHIKEY_VALID_STANDARD => .standard,
        c.INCHIKEY_VALID_NON_STANDARD => .non_standard,
        c.INCHIKEY_INVALID_LENGTH => .invalid_length,
        c.INCHIKEY_INVALID_LAYOUT => .invalid_layout,
        c.INCHIKEY_INVALID_VERSION => .invalid_version,
        else => @enumFromInt(code),
    };
}

// ---------------------------------------------------------------------------
// Keys
// ---------------------------------------------------------------------------

/// Upstream's `GetINCHIKeyFromINCHI`: the key of any identifier, standard or
/// not, plus the two extension hashes on request.
pub fn key(text: [:0]const u8, hashes: Hashes) KeyError!KeyResult {
    var result: KeyResult = .{};
    // Upstream zeroes `szXtra1`/`szXtra2` on entry whenever they are non-NULL
    // (`ikey_dll.c:150-157`) and writes a hash only when both the request flag
    // and a buffer are present (`ikey_dll.c:460-475`). Handing it real buffers
    // always therefore costs one byte of store and cannot change the answer,
    // while a null pointer would make the "requested but absent" case silently
    // produce no hash.
    var first: [hash_buffer_len]u8 = @splat(0);
    var second: [hash_buffer_len]u8 = @splat(0);
    const source: [*c]const u8 = text.ptr;
    const code = c.GetINCHIKeyFromINCHI(
        source,
        if (hashes.first) @as(c_int, 1) else @as(c_int, 0),
        if (hashes.second) @as(c_int, 1) else @as(c_int, 0),
        &result.key,
        &first,
        &second,
    );
    if (code != c.INCHIKEY_OK) return keyError(code);
    if (hashes.first) result.first_hash = first;
    if (hashes.second) result.second_hash = second;
    return result;
}

/// Upstream's `GetStdINCHIKeyFromStdINCHI`: the key of a standard identifier.
///
/// It refuses a non-standard identifier outright rather than producing the
/// non-standard key `key` would give (`ikey_dll.c:95-102`), and it computes no
/// extension hash.
pub fn standardKey(text: [:0]const u8) KeyError!KeyResult {
    var result: KeyResult = .{};
    const source: [*c]const u8 = text.ptr;
    const code = c.GetStdINCHIKeyFromStdINCHI(source, &result.key);
    if (code != c.INCHIKEY_OK) return keyError(code);
    return result;
}

// ---------------------------------------------------------------------------
// Internals
// ---------------------------------------------------------------------------

/// The empty option string, and the only storage this module owns.
///
/// Upstream reads `szOptions` and copies it into its own buffer before parsing
/// it (`inchi_dll.c:476-480`), and a zero-length option string parses to the
/// same single empty argument a NULL pointer produces: `parse_options_string`
/// returns `argc == 1` for it (`inchi_dll.c:1046-1062`), and
/// `ReadCommandLineParms` only ever reads `argv[1..argc-1]`
/// (`ichiparm.c`). So "no options" and "an empty option string" are the same
/// call, and this module never has to hand C a null pointer.
const no_options: [1:0]u8 = .{0};

fn optionsPointer(options: ?[:0]const u8) [*c]u8 {
    const text = options orelse return @constCast(&no_options);
    const borrowed: [*c]const u8 = text.ptr;
    return @constCast(borrowed);
}

/// Fills the `inchi_Input` the C entry points read, and returns it by value.
///
/// The caller must keep the result in mutable storage: `GetStdINCHI` and
/// `GetINCHI` take `inchi_Input *` (`inchi_dll.c:242`, `inchi_dll.c:270`) and
/// C cannot be asked for a `const` one. What is borrowed is the *contents*,
/// not the struct: upstream copies the caller's atoms into its own `inp_ATOM`
/// field by field (`inchi_dll.c:1933-1936`) and only reads the 0D
/// descriptors out of the caller's array (`inchi_dll.c:1990-1996`,
/// `readinch.c:158-188`), so neither array is copied and neither is written.
/// The `@constCast` below is the narrow one the C field type forces:
/// `inchi_Input.atom` is `inchi_Atom *`, not `const inchi_Atom *`, and the
/// one entry point that writes through it is `GetINCHIEx`
/// (`inchi_dll.c:330-336`), which is reachable through `c` and deliberately
/// not wrapped here so that this contract stays true.
fn inputStruct(molecule: Molecule) Error!c.inchi_Input {
    var input: c.inchi_Input = std.mem.zeroes(c.inchi_Input);
    const atoms: [*c]const Atom = molecule.atoms.ptr;
    input.atom = @constCast(atoms);
    const stereo: [*c]const Stereo0D = molecule.stereo0d.ptr;
    input.stereo0D = @constCast(stereo);
    input.szOptions = optionsPointer(molecule.options);
    input.num_atoms = std.math.cast(i16, molecule.atoms.len) orelse
        return error.TooManyAtoms;
    input.num_stereo0D = std.math.cast(i16, molecule.stereo0d.len) orelse
        return error.TooManyAtoms;
    return input;
}

fn identifierInput(text: [:0]const u8, options: ?[:0]const u8) c.inchi_InputINCHI {
    var input: c.inchi_InputINCHI = std.mem.zeroes(c.inchi_InputINCHI);
    // The C field is `char *` but the library only reads it: it is passed to
    // `CheckINCHI`, whose own parameter is `const char *`
    // (`inchi_dll.c:2304`), and to an input stream as a read-only source
    // (`inchi_dll.c:2322-2325`).
    const borrowed: [*c]const u8 = text.ptr;
    input.szInChI = @constCast(borrowed);
    input.szOptions = optionsPointer(options);
    return input;
}

fn statusFrom(code: c_int) Status {
    // `Status` has a catch-all field, so `@enumFromInt` is total here and a
    // status this release does not name is reported rather than trapped.
    return @enumFromInt(code);
}

fn keyError(code: c_int) KeyError {
    return switch (code) {
        c.INCHIKEY_INVALID_INCHI_PREFIX => error.InvalidInchiPrefix,
        c.INCHIKEY_NOT_ENOUGH_MEMORY => error.NotEnoughMemory,
        c.INCHIKEY_INVALID_INCHI => error.InvalidInchi,
        c.INCHIKEY_INVALID_STD_INCHI => error.InvalidStdInchi,
        else => error.UnknownFailure,
    };
}

/// Borrows one of upstream's output arrays, and answers an empty slice when
/// there is no array to borrow.
///
/// "No array" upstream is a null pointer with a count of zero, and both
/// `GetStructFrom*` paths produce exactly that: `GetStructFromStdINCHI` returns
/// `inchi_Ret_ERROR` without writing to `*outStruct` at all when it refuses an
/// identifier (`inchi_dll.c:2472-2476`), and the header lets `stereo0D` be
/// NULL (`inchi_api.h:642`). A translated C pointer carries no null in its
/// type, so the count is what has to be read first: casting a null `[*c]T` to
/// a non-optional `[*]const T` is a safety-check panic, not an empty slice.
/// Upstream never pairs a positive count with a null pointer, so the count
/// alone decides.
fn borrowedArray(comptime T: type, pointer: [*c]T, count: anytype) []const T {
    if (count <= 0) return &.{};
    const base: [*]const T = pointer;
    return base[0..@intCast(count)];
}

fn used(count: i16) usize {
    return @intCast(count);
}

fn append(target: *Atom, neighbor: usize, kind: BondType, stereo2d: BondStereo2D) void {
    const slot = used(target.num_bonds);
    target.neighbor[slot] = @intCast(neighbor);
    target.bond_type[slot] = @intFromEnum(kind);
    target.bond_stereo[slot] = @intFromEnum(stereo2d);
    target.num_bonds = @intCast(slot + 1);
}

/// Borrows one of upstream's output strings as a NUL-terminated slice.
///
/// The sentinel is upstream's own, not a re-derivation, and each of the four
/// strings reaches it a different way:
///
///   * `szInChI` and `szAuxInfo` are one string-stream buffer split in two.
///     `produce_generation_output` overwrites the line break with `'\0'` and
///     points `szAuxInfo` at the byte after it, then terminates the AuxInfo
///     line the same way (`inchi_dll.c:764-777`); `GetINCHIfromINCHI` repeats
///     the split (`inchi_dll.c:2354-2370`). The buffer is a C string before
///     the split too: every append to a string stream is a `vsprintf`, which
///     writes its own terminator (`ichi_io.c:757`).
///   * `szMessage` is a `strlen + 1` allocation filled by `strcpy`
///     (`inchi_dll.c:750-753`, `inchi_dll.c:306-309`) or the `MAX_MSG_LEN`
///     buffer `ReadWriteInChI` terminates on entry and after each copy
///     (`inchi_dll.c:2328`, `ichiread.c:715`, `ichiread.c:11586-11596`).
///   * `szLog` is the log stream, whose trailing line feeds upstream overwrites
///     with `'\0'` before handing the buffer over (`inchi_dll.c:791-806`,
///     `inchi_dll.c:2791-2800`).
///
/// So a caller may hand any of them straight to a `const char *` parameter.
/// Nothing is allocated and nothing is copied to make that true.
fn spanOrNull(pointer: [*c]u8) ?[:0]const u8 {
    // A translated C pointer carries no null in its type, so the address is
    // what is compared.
    if (@intFromPtr(pointer) == 0) return null;
    const borrowed: [*c]const u8 = pointer;
    return std.mem.span(borrowed);
}

fn terminated(buffer: []const u8) [:0]const u8 {
    const end = std.mem.indexOfScalar(u8, buffer, 0) orelse buffer.len;
    return buffer[0..end :0];
}
