//! SPDX-License-Identifier: LicenseRef-InChI-MIT-Conditional
//! See FORK-LICENSE.md for the full grant and the owner authorization behind it.
//! Typed Zig facade over upstream's InChI C API.
//! Results own upstream allocations; input slices are borrowed for each call.
const std = @import("std");

/// Translated upstream C declarations; runtime-loaded builds use a dispatch with the same namespace.
pub const c = @import("c");

/// Shared loader core; linked builds use its `LoadSource` and `LoadError` types.
const rt = @import("rt");

/// Whether native calls resolve through the platform loader at run time.
/// Linked builds are false; runtime-loaded builds require `load` before use.
pub const runtime_loaded: bool = if (@hasDecl(c, "rt_runtime_loaded")) c.rt_runtime_loaded else false;

/// Explicit library path or platform-loader name for `load`; no fallback is attempted.
pub const LoadSource = if (runtime_loaded) c.LoadSource else rt.LoadSource;

/// Errors returned when `load` cannot use the requested provider.
pub const LoadError = if (runtime_loaded) c.LoadError else rt.LoadError;

/// Loads the selected provider in a runtime-loaded build; the handle stays open until process exit.
/// Repeated identical requests succeed; other requests return errors, while linked builds panic.
pub fn load(source: LoadSource) LoadError!void {
    if (comptime !runtime_loaded) {
        std.debug.panic(
            "inchi: load was called on a linked build; this module is not " ++
                "runtime-loaded, so there is no library to load. Build with " ++
                "runtime loading configured, or do not call load.",
            .{},
        );
    }
    return c.load(source);
}

/// Returns the retained provider request, or null before loading or in a linked build.
/// The retained request remains valid for the process lifetime.
pub fn loadedSource() ?LoadSource {
    if (comptime !runtime_loaded) return null;
    return c.loadedSource();
}

/// Upstream's raw atom record; callers own and fill its fields.
/// Keep `num_bonds` within `0..max_bonds_per_atom`; `connect` enforces this for appended bonds.
pub const Atom = c.inchi_Atom;

/// Upstream's `inchi_Stereo0D`, unchanged.
pub const Stereo0D = c.inchi_Stereo0D;

/// Upstream's polymer-unit record; its arrays are borrowed for the call.
pub const PolymerUnit = c.inchi_Input_PolymerUnit;

/// Upstream's polymer input record; upstream copies its units during conversion.
pub const Polymer = c.inchi_Input_Polymer;

/// Upstream's V3000 input record; its arrays are borrowed for the call.
pub const V3000 = c.inchi_Input_V3000;

/// Upstream's AuxInfo input data, including the fixed diagnostic buffer.
pub const AuxData = c.InchiInpData;

/// `STR_ERR_LEN`, the length of `InchiInpData.szErrMsg` (`inchi_api.h:920`).
pub const error_buffer_len: usize = c.STR_ERR_LEN;

/// `MAXVAL`, the length of an adjacency list (`inchi_api.h:105`).
pub const max_bonds_per_atom: usize = c.MAXVAL;

/// `ATOM_EL_LEN`, the length of `Atom.elname` (`inchi_api.h:106`).
pub const element_symbol_len: usize = c.ATOM_EL_LEN;

/// `NO_ATOM`, the sentinel for a stereo descriptor without a central atom.
/// `doubleBondStereo` writes it for double-bond descriptors.
pub const no_atom: i16 = c.NO_ATOM;

/// `inchi_BondType` (`inchi_api.h:67-73`).
pub const BondType = enum(i8) {
    none = 0,
    single = 1,
    double = 2,
    triple = 3,
    /// Upstream discourages aromatic bonds; use a Kekule representation.
    altern = 4,
};

/// Upstream's 2D wedge-bond notation; ignored when coordinates are zero.
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

/// 0D parity is relative to the order of `Stereo0D.neighbor`.
/// Upstream defines the ordering at `inchi_api.h:255-256`.
pub const StereoParity0D = enum(i8) {
    none = 0,
    odd = 1,
    even = 2,
    unknown = 3,
    undefined = 4,
};

/// Upstream's result status; `warning` may include an identifier and message.
/// The non-exhaustive enum preserves codes not named by this release.
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

/// Return codes from `MakeINCHIFromMolfileText`, distinct from `Status`.
/// The producer may collapse read and generation failures to `rejected`.
pub const MolfileStatus = enum(c_int) {
    /// `mol2inchi_Ret_OKAY`: identifier produced, nothing to report.
    okay = 0,
    /// `mol2inchi_Ret_WARNING`: identifier produced, and `Output.message` says
    /// what was qualified.
    warning = 1,
    /// `mol2inchi_Ret_EOF`: generic error; no InChI has been created.
    no_data = -1,
    /// `mol2inchi_Ret_ERROR`: generic error; no InChI has been created.
    rejected = 2,
    /// Header's `mol2inchi_Ret_ERROR_get`; not emitted by the pinned producer.
    structure_failed = 4,
    /// Header's `mol2inchi_Ret_ERROR_comp`; not emitted by the pinned producer.
    generation_failed = 5,
    _,
};

/// Identifies the upstream entry point that allocated a result.
/// `deinit` uses the matching release function.
pub const Origin = enum { standard, non_standard };

/// Errors raised by facade-side validation; upstream statuses remain result values.
pub const Error = error{
    /// The element symbol exceeds `element_symbol_len`, including its terminator.
    ElementSymbolTooLong,
    /// A bond named an atom outside the molecule, or named the same atom twice.
    AtomIndexOutOfRange,
    /// Either adjacency count is negative or already at `max_bonds_per_atom`.
    /// `connect` rejects both lists before writing either one.
    TooManyNeighbors,
    /// Atom or stereo counts exceed the range representable by upstream's `AT_NUM`.
    /// Larger accepted molecule sizes are decided by upstream.
    TooManyAtoms,
};

/// Implicit hydrogen counts for the four isotopic categories.
/// `ordinary = -1` asks upstream to add hydrogens.
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

/// Input for `GetINCHI` and `GetStdINCHI`; atom and stereo slices are borrowed.
/// `options` is borrowed too; null and empty both mean no options.
pub const Molecule = struct {
    atoms: []const Atom,
    /// Borrowed 0D stereo descriptors; empty means no 0D stereo.
    stereo0d: []const Stereo0D = &.{},
    /// Borrowed upstream option string; prefixes are `/` on Windows and `-` elsewhere.
    /// Null and empty both request no options.
    options: ?[:0]const u8 = null,
};

/// Input for `GetINCHIEx`; upstream may rewrite `*` atoms to `Zz`.
/// Stereo, options, polymer, and V3000 data are borrowed for the call.
pub const ExtendedMolecule = struct {
    atoms: []Atom,
    /// Borrowed 0D stereo descriptors, as in `Molecule`.
    stereo0d: []const Stereo0D = &.{},
    /// Borrowed option string, as in `Molecule`.
    options: ?[:0]const u8 = null,
    /// Polymer Sgroups, or null for a structure that is not a polymer.
    polymer: ?*const Polymer = null,
    /// V3000 Molfile features, or null when there are none.
    v3000: ?*const V3000 = null,
};

/// Requests the optional first and second InChIKey extension hashes.
/// Unrequested hashes are not computed and are returned as null.
pub const Hashes = struct {
    first: bool = false,
    second: bool = false,
};

/// Errors from upstream's InChIKey functions; unknown codes map to `UnknownFailure`.
/// No key or hash value is returned on error.
pub const KeyError = error{
    /// Unknown upstream failure code.
    UnknownFailure,
    /// `INCHIKEY_INVALID_INCHI_PREFIX`.
    InvalidInchiPrefix,
    /// `INCHIKEY_NOT_ENOUGH_MEMORY`.
    NotEnoughMemory,
    /// `INCHIKEY_INVALID_INCHI`.
    InvalidInchi,
    /// The identifier is non-standard; only `standardKey` rejects this verdict.
    InvalidStdInchi,
};

/// Verdicts from upstream's `CheckINCHI`; unknown codes are preserved.
/// Strict mode may return `conversion_failed` for a well-formed identifier.
pub const IdentifierVerdict = enum(c_int) {
    standard,
    non_standard,
    beta,
    invalid_prefix,
    invalid_version,
    invalid_layout,
    /// Strict regeneration did not reproduce the input identifier.
    conversion_failed,
    _,
};

/// Verdicts from upstream's `CheckINCHIKey`; unnamed codes are preserved.
/// Named variants retain their native integer values.
pub const KeyVerdict = enum(c_int) {
    standard = 0,
    non_standard = -1,
    invalid_length = 1,
    invalid_layout = 2,
    invalid_version = 3,
    _,
};

/// `CheckINCHIKey` requires exactly 27 characters plus the terminator.
pub const key_buffer_len = 28;

/// Capacity for each optional 64-character extension hash plus its terminator.
pub const hash_buffer_len = 65;

/// Result of identifier generation; owns upstream strings until `deinit`.
/// Accessor slices borrow those strings; a warning may still include an identifier.
pub const Output = struct {
    raw: c.inchi_Output,
    status: Status,
    origin: Origin,

    /// Returns the identifier, or null when upstream produced none.
    pub fn identifier(self: *const Output) ?[:0]const u8 {
        return spanOrNull(self.raw.szInChI);
    }

    /// Returns the borrowed `AuxInfo=` line, which shares the identifier allocation.
    /// It remains valid until `deinit`; do not free it separately.
    pub fn auxInfo(self: *const Output) ?[:0]const u8 {
        return spanOrNull(self.raw.szAuxInfo);
    }

    /// Upstream's warning or error text, or an empty string.
    pub fn message(self: *const Output) [:0]const u8 {
        return spanOrNull(self.raw.szMessage) orelse "";
    }

    /// The recognised options and the human-readable log, or "".
    pub fn log(self: *const Output) [:0]const u8 {
        return spanOrNull(self.raw.szLog) orelse "";
    }

    /// Whether the status is `warning`; the result may still contain an identifier.
    pub fn isWarning(self: *const Output) bool {
        return self.status == .warning;
    }

    /// Releases upstream strings through the matching free function.
    /// Call once per result; all borrowed slices expire afterwards.
    pub fn deinit(self: *Output) void {
        switch (self.origin) {
            .standard => c.FreeStdINCHI(&self.raw),
            .non_standard => c.FreeINCHI(&self.raw),
        }
    }
};

/// Result of `MakeINCHIFromMolfileText`; its status uses `MolfileStatus`.
/// Its strings are owned by the result and released by `deinit`.
pub const MolfileOutput = struct {
    raw: c.inchi_Output,
    status: MolfileStatus,

    /// Returns the identifier, or null when upstream produced none.
    pub fn identifier(self: *const MolfileOutput) ?[:0]const u8 {
        return spanOrNull(self.raw.szInChI);
    }

    /// Returns the borrowed `AuxInfo=` line, which shares the identifier allocation.
    /// It remains valid until `deinit`.
    pub fn auxInfo(self: *const MolfileOutput) ?[:0]const u8 {
        return spanOrNull(self.raw.szAuxInfo);
    }

    /// Upstream's error or warning text, or "".
    pub fn message(self: *const MolfileOutput) [:0]const u8 {
        return spanOrNull(self.raw.szMessage) orelse "";
    }

    /// Returns upstream's human-readable log, or an empty string.
    pub fn log(self: *const MolfileOutput) [:0]const u8 {
        return spanOrNull(self.raw.szLog) orelse "";
    }

    /// Whether the status is `warning`.
    pub fn isWarning(self: *const MolfileOutput) bool {
        return self.status == .warning;
    }

    /// Releases the upstream strings; call once, including after a refusal.
    /// The log may be allocated even when no identifier was produced.
    pub fn deinit(self: *MolfileOutput) void {
        c.FreeStdINCHI(&self.raw);
    }
};

/// Upstream warning flags indexed by layer and hydrogen treatment.
/// Entries are `INCHIDIFF_*` bits from `inchicmp.h`.
pub const Warnings = [2][2]c_ulong;

/// Result of identifier-to-structure conversion; owns upstream arrays and strings.
/// Accessor slices borrow this storage until `deinit`.
pub const Structure = struct {
    raw: c.inchi_OutputStruct,
    status: Status,
    origin: Origin,

    /// Borrowed atoms; empty when no structure was produced, valid until `deinit`.
    pub fn atoms(self: *const Structure) []const Atom {
        return borrowedArray(Atom, self.raw.atom, self.raw.num_atoms);
    }

    /// Borrowed 0D stereo descriptors; valid until `deinit`.
    pub fn stereo0d(self: *const Structure) []const Stereo0D {
        return borrowedArray(Stereo0D, self.raw.stereo0D, self.raw.num_stereo0D);
    }

    /// Upstream's warning or error text, or an empty string.
    pub fn message(self: *const Structure) [:0]const u8 {
        return spanOrNull(self.raw.szMessage) orelse "";
    }

    /// Upstream's log, or "". Terminated the same way as `Output.log`.
    pub fn log(self: *const Structure) [:0]const u8 {
        return spanOrNull(self.raw.szLog) orelse "";
    }

    /// Returns the per-layer difference flags from upstream.
    pub fn warnings(self: *const Structure) Warnings {
        return self.raw.WarningFlags;
    }

    /// Whether the status is `warning`; difference flags are separate.
    pub fn isWarning(self: *const Structure) bool {
        return self.status == .warning;
    }

    /// Releases upstream arrays and strings through the matching free function.
    /// Call once per result; all borrowed slices expire afterwards.
    pub fn deinit(self: *Structure) void {
        switch (self.origin) {
            .standard => c.FreeStructFromStdINCHI(&self.raw),
            .non_standard => c.FreeStructFromINCHI(&self.raw),
        }
    }
};

/// Extended structure result; owns atoms, strings, polymer, and V3000 data.
/// Accessors borrow this storage until `deinit`.
pub const ExtendedStructure = struct {
    raw: c.inchi_OutputStructEx,
    status: Status,
    origin: Origin,

    /// Borrowed atoms; empty when no structure was produced.
    pub fn atoms(self: *const ExtendedStructure) []const Atom {
        return borrowedArray(Atom, self.raw.atom, self.raw.num_atoms);
    }

    /// Borrowed 0D stereo descriptors, valid until `deinit`.
    pub fn stereo0d(self: *const ExtendedStructure) []const Stereo0D {
        return borrowedArray(Stereo0D, self.raw.stereo0D, self.raw.num_stereo0D);
    }

    /// Borrowed polymer block, or null when absent.
    pub fn polymer(self: *const ExtendedStructure) ?*const Polymer {
        return optionalStruct(Polymer, self.raw.polymer);
    }

    /// Borrowed V3000 block, or null when absent.
    pub fn v3000(self: *const ExtendedStructure) ?*const V3000 {
        return optionalStruct(V3000, self.raw.v3000);
    }

    /// Upstream's warning or error text, or an empty string.
    pub fn message(self: *const ExtendedStructure) [:0]const u8 {
        return spanOrNull(self.raw.szMessage) orelse "";
    }

    /// Upstream's log, or an empty string.
    pub fn log(self: *const ExtendedStructure) [:0]const u8 {
        return spanOrNull(self.raw.szLog) orelse "";
    }

    /// Returns the per-layer difference flags from upstream.
    pub fn warnings(self: *const ExtendedStructure) Warnings {
        return self.raw.WarningFlags;
    }

    /// Whether the status is `warning`.
    pub fn isWarning(self: *const ExtendedStructure) bool {
        return self.status == .warning;
    }

    /// Releases all upstream arrays and blocks; call once, including after refusal.
    /// Borrowed slices and pointers expire after `deinit`.
    pub fn deinit(self: *ExtendedStructure) void {
        c.FreeStructFromINCHIEx(&self.raw);
    }
};

/// Result of AuxInfo-to-structure conversion; owns upstream atom and stereo arrays.
/// The options pointer remains borrowed from the caller.
pub const AuxStructure = struct {
    raw: c.inchi_Input,
    data: AuxData,
    status: Status,
    origin: Origin,

    /// Borrowed atoms; empty when no structure was produced.
    pub fn atoms(self: *const AuxStructure) []const Atom {
        return borrowedArray(Atom, self.raw.atom, self.raw.num_atoms);
    }

    /// Borrowed 0D stereo descriptors, valid until `deinit`.
    pub fn stereo0d(self: *const AuxStructure) []const Stereo0D {
        return borrowedArray(Stereo0D, self.raw.stereo0D, self.raw.num_stereo0D);
    }

    /// Returns the AuxInfo chiral mark, or zero when absent or refused.
    pub fn chiralMark(self: *const AuxStructure) u3 {
        return @truncate(self.data.bChiral);
    }

    /// Returns the parse diagnostic as a slice borrowed from the fixed buffer.
    pub fn parseMessage(self: *const AuxStructure) []const u8 {
        const field: []const u8 = &self.data.szErrMsg;
        const end = std.mem.indexOfScalar(u8, field, 0) orelse field.len;
        return field[0..end];
    }

    /// Returns a `Molecule` borrowing this result's atom and stereo arrays.
    /// Its options string remains borrowed from the original caller.
    pub fn molecule(self: *const AuxStructure) Molecule {
        const options: ?[:0]const u8 = if (@intFromPtr(self.raw.szOptions) == 0)
            null
        else
            std.mem.span(@as([*c]const u8, self.raw.szOptions));
        return .{
            .atoms = self.atoms(),
            .stereo0d = self.stereo0d(),
            .options = options,
        };
    }

    /// Releases the upstream arrays through the matching free function.
    /// Call once per result, including after refusal.
    pub fn deinit(self: *AuxStructure) void {
        switch (self.origin) {
            .standard => c.Free_std_inchi_Input(&self.raw),
            .non_standard => c.Free_inchi_Input(&self.raw),
        }
    }
};

/// InChIKey and optional extension hashes stored in this value.
/// The buffers are owned inline; copies are independent and need no release.
pub const KeyResult = struct {
    key: [key_buffer_len]u8 = @splat(0),
    first_hash: ?[hash_buffer_len]u8 = null,
    second_hash: ?[hash_buffer_len]u8 = null,

    /// Returns the 27-character key without its terminator.
    pub fn keyText(self: *const KeyResult) [:0]const u8 {
        return terminated(&self.key);
    }

    /// Returns the first extension hash, if requested.
    pub fn firstHash(self: *const KeyResult) ?[:0]const u8 {
        if (self.first_hash) |*buffer| return terminated(buffer);
        return null;
    }

    /// Returns the second extension hash, if requested.
    pub fn secondHash(self: *const KeyResult) ?[:0]const u8 {
        if (self.second_hash) |*buffer| return terminated(buffer);
        return null;
    }
};

/// Returns a zeroed atom with the requested hydrogens; rejects symbols too long for `elname`.
/// Other atom fields remain zero for callers to fill.
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

/// Adds the bond to both adjacency lists.
/// Invalid indices or full/invalid counts return an error without modifying either list.
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
    if (countOutOfRange(atoms[first].num_bonds) or
        countOutOfRange(atoms[second].num_bonds))
    {
        return error.TooManyNeighbors;
    }
    append(&atoms[first], second, kind, stereo2d);
    append(&atoms[second], first, kind, stereo2d);
}

/// Builds a tetrahedral 0D descriptor using the supplied neighbour order and parity.
/// An implicit hydrogen occupies the first neighbour slot upstream.
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

/// Builds a double-bond 0D descriptor in `{X, A, B, Y}` order.
/// Allene descriptors require direct `Stereo0D` construction.
pub fn doubleBondStereo(x: i16, a: i16, b: i16, y: i16, parity: StereoParity0D) Stereo0D {
    var result: Stereo0D = std.mem.zeroes(Stereo0D);
    result.neighbor = .{ x, a, b, y };
    result.central_atom = no_atom;
    result.type = @intFromEnum(StereoType0D.double_bond);
    result.parity = @intFromEnum(parity);
    return result;
}

/// Structure-to-identifier operations backed by `GetStdINCHI` and `GetINCHI`.
/// Inputs are borrowed; extended input may be mutated by upstream.
pub const fromMolecule = struct {
    /// Produces a standard identifier with upstream's `GetStdINCHI`.
    /// Local input-size errors occur before the C call.
    pub fn standard(molecule: Molecule) Error!Output {
        var input = try inputStruct(molecule);
        var raw: c.inchi_Output = std.mem.zeroes(c.inchi_Output);
        const code = c.GetStdINCHI(&input, &raw);
        return .{ .raw = raw, .status = statusFrom(code), .origin = .standard };
    }

    /// Produces an identifier with upstream's `GetINCHI`; options may make it non-standard.
    pub fn full(molecule: Molecule) Error!Output {
        var input = try inputStruct(molecule);
        var raw: c.inchi_Output = std.mem.zeroes(c.inchi_Output);
        const code = c.GetINCHI(&input, &raw);
        return .{ .raw = raw, .status = statusFrom(code), .origin = .non_standard };
    }

    /// Produces an extended identifier; upstream may rewrite `*` atoms to `Zz`.
    /// Result strings are owned by `Output` and released by `deinit`.
    pub fn extended(molecule: ExtendedMolecule) Error!Output {
        var input = try extendedInputStruct(molecule);
        var raw: c.inchi_Output = std.mem.zeroes(c.inchi_Output);
        const code = c.GetINCHIEx(&input, &raw);
        return .{ .raw = raw, .status = statusFrom(code), .origin = .non_standard };
    }
};

/// Identifier-to-structure and identifier-to-identifier operations.
/// Input and option strings are borrowed; upstream outcomes are returned in result statuses.
pub const fromIdentifier = struct {
    /// Rebuilds a standard identifier; non-standard input returns `rejected`.
    pub fn standard(text: [:0]const u8, options: ?[:0]const u8) Error!Structure {
        var input = identifierInput(text, options);
        // Upstream may leave the output untouched on refusal; zero it before release.
        var raw: c.inchi_OutputStruct = std.mem.zeroes(c.inchi_OutputStruct);
        const code = c.GetStructFromStdINCHI(&input, &raw);
        return .{ .raw = raw, .status = statusFrom(code), .origin = .standard };
    }

    /// Rebuilds either a standard or non-standard identifier.
    pub fn full(text: [:0]const u8, options: ?[:0]const u8) Error!Structure {
        var input = identifierInput(text, options);
        var raw: c.inchi_OutputStruct = std.mem.zeroes(c.inchi_OutputStruct);
        const code = c.GetStructFromINCHI(&input, &raw);
        return .{ .raw = raw, .status = statusFrom(code), .origin = .non_standard };
    }

    /// Rebuilds atoms and any polymer or V3000 blocks described by the identifier.
    /// The result owns upstream allocations until `deinit`.
    pub fn extended(text: [:0]const u8, options: ?[:0]const u8) Error!ExtendedStructure {
        var input = identifierInput(text, options);
        var raw: c.inchi_OutputStructEx = std.mem.zeroes(c.inchi_OutputStructEx);
        const code = c.GetStructFromINCHIEx(&input, &raw);
        return .{ .raw = raw, .status = statusFrom(code), .origin = .non_standard };
    }

    /// Regenerates an identifier; options can filter layers and produce a non-standard result.
    /// Input and option strings are borrowed for the call.
    pub fn converted(text: [:0]const u8, options: ?[:0]const u8) Error!Output {
        var input = identifierInput(text, options);
        var raw: c.inchi_Output = std.mem.zeroes(c.inchi_Output);
        const code = c.GetINCHIfromINCHI(&input, &raw);
        return .{ .raw = raw, .status = statusFrom(code), .origin = .non_standard };
    }
};

/// Rebuilds a structure from AuxInfo; result arrays are owned by the returned value.
/// Input and options are borrowed; status and `parseMessage` describe upstream outcomes.
pub const fromAuxInfo = struct {
    /// Reads AuxInfo with upstream's standard-reader behavior.
    pub fn standard(
        aux_info: [:0]const u8,
        options: ?[:0]const u8,
        do_not_add_h: bool,
    ) Error!AuxStructure {
        var raw: c.inchi_Input = std.mem.zeroes(c.inchi_Input);
        raw.szOptions = optionsPointer(options);
        var data: AuxData = std.mem.zeroes(AuxData);
        data.pInp = &raw;
        const source: [*c]u8 = @constCast(aux_info.ptr);
        const code = c.Get_std_inchi_Input_FromAuxInfo(
            source,
            if (do_not_add_h) @as(c_int, 1) else @as(c_int, 0),
            &data,
        );
        return .{ .raw = raw, .data = data, .status = statusFrom(code), .origin = .standard };
    }

    /// Reads AuxInfo and optionally distinguishes unknown from undefined stereo.
    /// Result arrays are owned by the returned value.
    pub fn full(
        aux_info: [:0]const u8,
        options: ?[:0]const u8,
        do_not_add_h: bool,
        distinguish_unknown_undefined: bool,
    ) Error!AuxStructure {
        var raw: c.inchi_Input = std.mem.zeroes(c.inchi_Input);
        raw.szOptions = optionsPointer(options);
        var data: AuxData = std.mem.zeroes(AuxData);
        data.pInp = &raw;
        const source: [*c]u8 = @constCast(aux_info.ptr);
        const code = c.Get_inchi_Input_FromAuxInfo(
            source,
            if (do_not_add_h) @as(c_int, 1) else @as(c_int, 0),
            if (distinguish_unknown_undefined) @as(c_int, 1) else @as(c_int, 0),
            &data,
        );
        return .{ .raw = raw, .data = data, .status = statusFrom(code), .origin = .non_standard };
    }
};

/// Converts borrowed molfile text to an identifier.
/// Release returned strings with `deinit`, including after refusal.
pub fn fromMolfile(text: [:0]const u8, options: ?[:0]const u8) Error!MolfileOutput {
    var raw: c.inchi_Output = std.mem.zeroes(c.inchi_Output);
    const moltext: [*c]const u8 = text.ptr;
    const code = c.MakeINCHIFromMolfileText(moltext, optionsPointer(options), &raw);
    return .{ .raw = raw, .status = @enumFromInt(code) };
}

/// Classifies an InChI string; strict mode also regenerates it and may return `conversion_failed`.
/// Unnamed upstream codes are preserved.
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

/// Classifies an InChIKey; unnamed upstream codes are preserved.
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

/// Computes an InChIKey and requested extension hashes into inline result buffers.
/// Borrows `text`; errors return no value and require no release.
pub fn key(text: [:0]const u8, hashes: Hashes) KeyError!KeyResult {
    var result: KeyResult = .{};
    // Upstream writes requested hashes only when given non-null buffers.
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

/// Computes a key for a standard identifier; non-standard input returns an error.
/// Result buffers are owned inline and need no release.
pub fn standardKey(text: [:0]const u8) KeyError!KeyResult {
    var result: KeyResult = .{};
    const source: [*c]const u8 = text.ptr;
    const code = c.GetStdINCHIKeyFromStdINCHI(source, &result.key);
    if (code != c.INCHIKEY_OK) return keyError(code);
    return result;
}

/// Single non-null empty string used when a call has no options.
const no_options: [1:0]u8 = .{0};

fn optionsPointer(options: ?[:0]const u8) [*c]u8 {
    const text = options orelse return @constCast(&no_options);
    const borrowed: [*c]const u8 = text.ptr;
    return @constCast(borrowed);
}

/// C requires a mutable input struct; atom and stereo slices remain borrowed.
/// `GetINCHIEx` is separate because it may mutate atoms.
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

/// Builds extended input with mutable atoms because upstream rewrites `*` to `Zz`.
/// Polymer and V3000 records remain borrowed and read-only.
fn extendedInputStruct(molecule: ExtendedMolecule) Error!c.inchi_InputEx {
    var input: c.inchi_InputEx = std.mem.zeroes(c.inchi_InputEx);
    const atoms: [*c]Atom = molecule.atoms.ptr;
    input.atom = atoms;
    const stereo: [*c]const Stereo0D = molecule.stereo0d.ptr;
    input.stereo0D = @constCast(stereo);
    input.szOptions = optionsPointer(molecule.options);
    input.num_atoms = std.math.cast(i16, molecule.atoms.len) orelse
        return error.TooManyAtoms;
    input.num_stereo0D = std.math.cast(i16, molecule.stereo0d.len) orelse
        return error.TooManyAtoms;
    input.polymer = if (molecule.polymer) |polymer| @constCast(polymer) else null;
    input.v3000 = if (molecule.v3000) |v3000| @constCast(v3000) else null;
    return input;
}

fn identifierInput(text: [:0]const u8, options: ?[:0]const u8) c.inchi_InputINCHI {
    var input: c.inchi_InputINCHI = std.mem.zeroes(c.inchi_InputINCHI);
    // Upstream reads the borrowed identifier through a non-const C field.
    const borrowed: [*c]const u8 = text.ptr;
    input.szInChI = @constCast(borrowed);
    input.szOptions = optionsPointer(options);
    return input;
}

fn statusFrom(code: c_int) Status {
    // Preserve unnamed codes through the non-exhaustive `Status` enum.
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

/// Checks the count before forming a slice from a translated C pointer.
/// Upstream uses a null array only with a non-positive count.
fn borrowedArray(comptime T: type, pointer: [*c]T, count: anytype) []const T {
    if (count <= 0) return &.{};
    const base: [*]const T = pointer;
    return base[0..@intCast(count)];
}

/// Converts an optional translated C pointer to a borrowed block.
/// Upstream uses null when polymer or V3000 data are absent.
fn optionalStruct(comptime T: type, pointer: [*c]T) ?*const T {
    if (@intFromPtr(pointer) == 0) return null;
    return pointer;
}

/// Returns zero for non-positive raw counts, which are representable in `num_bonds`.
/// `connect` rejects such counts before appending.
fn used(count: i16) usize {
    return if (count <= 0) 0 else @intCast(count);
}

fn countOutOfRange(count: i16) bool {
    return count < 0 or used(count) >= max_bonds_per_atom;
}

fn append(target: *Atom, neighbor: usize, kind: BondType, stereo2d: BondStereo2D) void {
    const slot = used(target.num_bonds);
    target.neighbor[slot] = @intCast(neighbor);
    target.bond_type[slot] = @intFromEnum(kind);
    target.bond_stereo[slot] = @intFromEnum(stereo2d);
    target.num_bonds = @intCast(slot + 1);
}

/// Returns null for a null translated pointer; otherwise borrows its NUL-terminated string.
/// The pointer is checked before `std.mem.span`.
fn spanOrNull(pointer: [*c]u8) ?[:0]const u8 {
    if (@intFromPtr(pointer) == 0) return null;
    const borrowed: [*c]const u8 = pointer;
    return std.mem.span(borrowed);
}

fn terminated(buffer: []const u8) [:0]const u8 {
    const end = std.mem.indexOfScalar(u8, buffer, 0) orelse buffer.len;
    return buffer[0..end :0];
}
