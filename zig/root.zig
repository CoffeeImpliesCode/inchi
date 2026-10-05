//! SPDX-License-Identifier: LicenseRef-InChI-MIT-Conditional
//! See FORK-LICENSE.md for the full grant and the owner authorization behind it.
//!
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
//!     additionally allocates the atom and 0D-stereo arrays; and
//!     `GetStructFromINCHIEx` allocates the polymer and V3000 blocks beside
//!     them. `Output`, `Structure`, `ExtendedStructure` and `AuxStructure`
//!     carry which entry point produced them (`Origin`) and their `deinit`
//!     calls back through that same entry point, so the release always pairs
//!     with the creator. Each of those values has one owner and is released
//!     once: copying the struct copies its pointers, not the bytes, so a
//!     second `deinit` through a copy frees the same allocation twice.
//!     No string is copied on the way out and no Zig allocator is involved: the
//!     bytes come from upstream's `inchi_malloc` and go back to it. Two
//!     releases are required even on a refusal, and both are safe to make:
//!     `MakeINCHIFromMolfileText` writes `szLog` on every return including the
//!     failing ones, and the AuxInfo readers release their own arrays on a
//!     refusal and NULL both pointers so the caller's `deinit` finds nothing.
//!   * **Status.** Upstream's return value is a *classification*, not a boolean:
//!     `inchi_Ret_WARNING` (1) means an identifier was produced and something
//!     worth reading is in `szMessage`. It is not an error and this module never
//!     turns it into one. `Output.status` carries the exact code, including the
//!     codes `RetValGetINCHI` never names, and `Output.message` carries
//!     upstream's own words on the failure path.
//!   * **Bounds.** `elname` is six bytes, an adjacency list is twenty entries
//!     long, `num_atoms` is a `short`, an InChIKey is 27 characters. Each of
//!     those is checked where a caller can act on it, with an ordinary
//!     comparison rather than an assertion. What the facade counts is not
//!     always what the library accepts, and each boundary says which one it is.
//!
//! ## What the C leaves to the caller
//!
//!   * `Atom` is the raw `inchi_Atom`, so charge, radical, isotopic mass and the
//!     3D coordinates are written on it directly and mean exactly what
//!     `inchi_api.h:134-162` says they mean. Writing adjacency raw means
//!     bringing `num_bonds` with it: it is the count upstream reads, and it
//!     bounds `neighbor`, `bond_type` and `bond_stereo` together
//!     (`inchi_api.h:165-171`).
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
//! `ExtendedMolecule` borrows the same two arrays and the polymer and V3000
//! blocks with them, but takes its atoms mutably because `GetINCHIEx` rewrites
//! a `*` element name to `Zz` through that pointer before anything else
//! (`inchi_dll.c:325-340`); that type's own declaration says so where a caller
//! will see it.
//!
//! The option string is borrowed too: upstream copies it before parsing
//! (`inchi_dll.c:476-480`, `inchi_dll_a.c:314-321`, `inchi_dll.c:2216-2219`,
//! `inchi_dll.c:2586-2589`, `inchi_dll_b.c:308-316`), so a NUL-terminated
//! literal is safe to hand over even though the C declares the field `char *`.
//! The AuxInfo readers preserve the string they were given across the memset
//! that clears everything else (`ichilnct.c:118-121`), so it is still the
//! caller's bytes on the way back out and is never freed by this module.
//!
//! What is *not* borrowed is the `inchi_Input` / `inchi_InputINCHI` struct
//! itself: C declares every one of these parameters non-const
//! (`inchi_dll.c:242`, `inchi_dll.c:2114`), so each call builds that struct in
//! a mutable local of its own and hands C a pointer to it. It is five fields on
//! the stack -- no allocation, and no copy of the borrowed arrays.
//!
//! ## Sentinel strings
//!
//! Every `[:0]const u8` this module accepts -- `Molecule.options`, an
//! identifier, an option string -- reaches C as a `char *`, and C reads it as a
//! C string. A NUL inside one ends the text there: the bytes after the first
//! NUL are invisible to upstream, and nothing the module hands back reflects
//! them. The sentinel type guarantees the trailing terminator, not that the
//! caller left out the interior ones.
//!
//! ## Shortest sequence
//!
//! ```zig
//! const std = @import("std");
//! const inchi = @import("inchi");
//!
//! pub fn main() !void {
//!     // Ethanol, implicit hydrogens, no stereo or coordinates.
//!     var atoms = [_]inchi.Atom{
//!         try inchi.atom("C", .{ .ordinary = 3 }),
//!         try inchi.atom("C", .{ .ordinary = 2 }),
//!         try inchi.atom("O", .{ .ordinary = 1 }),
//!     };
//!     try inchi.connect(&atoms, 0, 1, .single, .none);
//!     try inchi.connect(&atoms, 1, 2, .single, .none);
//!     var output = try inchi.fromMolecule.standard(.{ .atoms = &atoms });
//!     defer output.deinit();
//!     const identifier = output.identifier() orelse return error.NoIdentifier;
//!     const computed = try inchi.key(identifier, .{});
//!     std.debug.print("{s}\n{s}\n", .{ identifier, computed.keyText() });
//! }
//! ```
//!
//! ## `c` is the escape hatch
//!
//! The complete translated declaration set is public: the IXA builder objects,
//! the `INCHIGEN_*` / `STDINCHIGEN_*` modularized generator, `GetStringLength`,
//! and the whole 0D-stereo surface. A caller going through `c` gets upstream's
//! behaviour with none of the contracts above. The typed surface covers the
//! four directions a caller actually composes -- structure to identifier,
//! identifier to structure, identifier to identifier, and AuxInfo to structure
//! -- plus the molfile shortcut and the extended polymer/V3000 input and
//! output; `GetStringLength` is left there on purpose, because it returns
//! `strlen` of a C string a Zig sentinel slice already carries and wrapping it
//! would re-derive a value upstream is not adding.
//!
//!
//! ## Two configurations: linked and runtime-loaded
//!
//! This module is built in one of two shapes, and `runtime_loaded` says which
//! at comptime.
//!
//! *Linked* is the default. The C library is linked, `c` is the translated
//! header, and every call below is an ordinary direct call with no table and no
//! readiness check.
//!
//! *Runtime-loaded* is opt-in. The library is not linked into the module; `c`
//! is a dispatch generated from the same translation step's output, and every
//! function `inchi_api.h` and `ixa.h` declares is resolved through the platform
//! loader when the caller calls
//!
//! ```zig
//! try inchi.load(.{ .path = "/usr/lib/libinchi.so.1.7.5" });
//! ```
//!
//! before using anything else. A call into a module that has not loaded stops
//! the program with a message naming the function, in every optimization mode.
//! That is a programming error rather than a recoverable condition: the table
//! does not exist yet and there is no partial state to fall back on. The load
//! itself reports a missing file, a provider that does not export what the
//! header declares, a provider whose own check declines it, a request that
//! cannot be honoured because a different provider already won, or a reentrant
//! call, as errors rather than as a different library being loaded instead.
//!
//! The provider is reached, never guessed. `.path` names a file and `.system`
//! names a library for the platform loader; neither falls back to the other,
//! there is no unload and no reset, and the handle and the loader's own copy of
//! the request live to the end of the process.
//!
//! What a provider must be -- the external ABI family, the struct layouts the
//! header macros fix, the scalar widths, the calling convention, the allocator
//! and the one symbol upstream's own export list leaves out -- is stated in
//! `runtime/library.zig`, next to the load-time check and to what that check
//! does and does not prove.
const std = @import("std");

/// Every declaration `b.addTranslateC` produced from `inchi_api.h` (which ends
/// with `#include "ixa.h"`), i.e. upstream's ABI exactly as published.
///
/// This is the escape hatch for anything the typed surface below does not name:
/// the 110 `IXA_*` builder entry points, the `INCHIGEN_*` / `STDINCHIGEN_*`
/// modularized generator, `GetStringLength`, and the struct fields themselves.
/// It is the same module the facade calls, on the same library, so importing
/// the facade is all a dependent needs to reach it; it is not published under a
/// name of its own.
///
/// In a runtime-loading build this module is a generated dispatch instead of
/// the translation step's own output. It publishes the same namespace: every
/// type and constant is re-exported from the translated header rather than
/// restated, so `Atom` is the same nominal type either way and nothing here
/// needs a cast. What differs is how a name reaches the library. In the linked
/// configuration it is a direct call; in the runtime-loaded one it is a call
/// through a table that `load` fills, and a call before that fill stops the
/// program with a message naming the function. `runtime_loaded` says which
/// configuration this build is, at comptime.
pub const c = @import("c");

/// The loader core, which is where a linked build's two public types come from.
///
/// It is imported only by the linked configuration. In a runtime-loading build
/// the dispatch carries its own copy of the same declarations, and this module
/// is never referenced, so it is never resolved and never compiled. Either way
/// there is exactly one `LoadSource` and one `LoadError` in a build, which is
/// what keeps them one type for a consumer that names them.
const rt = @import("rt");

/// Whether this module was configured to resolve its native symbols at run
/// time.
///
/// False for the ordinary build, where the C library is linked and `c` is the
/// translated header itself. True when the build generated a dispatch that
/// resolves the same symbols through the platform loader, in which case `load`
/// is the call that makes the library usable.
///
/// It is a comptime constant, so a consumer can write two different code paths
/// and have only the one it chose analyzed.
pub const runtime_loaded: bool = if (@hasDecl(c, "rt_runtime_loaded")) c.rt_runtime_loaded else false;

/// Which native library `load` should open.
///
/// `.path` is an explicit file path and `.system` is an explicit name for the
/// platform loader. There is no path-to-system fallback and no implicit
/// fallback of any kind; a request that cannot be honoured is an error, not a
/// different library.
pub const LoadSource = if (runtime_loaded) c.LoadSource else rt.LoadSource;

/// Every way `load` can decline.
///
/// Declared here, in the module a consumer imports, rather than only inside the
/// loader: the caller names the failure it is handling.
pub const LoadError = if (runtime_loaded) c.LoadError else rt.LoadError;

/// Load the native library this module dispatches to.
///
/// In a runtime-loading build this is the whole contract: call it once, then
/// use this module as if it were linked. Calling it again with the same request
/// succeeds and changes nothing; calling it with a different request after a
/// success is `ProviderMismatch`, and the library already in use stays in use.
/// A failed attempt publishes nothing and can be retried explicitly, by
/// calling this again: there is no automatic retry, and no implicit second
/// source.
///
/// It keeps the process handle and its own copy of the request to the end of
/// the process. There is no unload and no reset, because the table is
/// process-global state that other code may already have called through.
///
/// Safe to call from any thread. A thread that arrives while an attempt for
/// the same request is in flight waits for that attempt and gets its result,
/// whatever it was. A call from the thread that is running the attempt is
/// `ReentrantLoad` rather than a deadlock.
///
/// In a linked build there is no provider, no table and nothing to resolve, so
/// this stops the program with a message saying so instead of quietly
/// succeeding. `runtime_loaded` is false there, so a consumer that supports
/// both configurations can tell the two apart at comptime instead of meeting
/// this at run time.
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

/// The request that succeeded, or null when nothing has loaded yet.
///
/// The answer is the loader's own retained copy and stays valid for the life of
/// the process. Null in a linked build, which has no request.
pub fn loadedSource() ?LoadSource {
    if (comptime !runtime_loaded) return null;
    return c.loadedSource();
}

/// Upstream's `inchi_Atom`, unchanged (`inchi_api.h:134-162`). Coordinates,
/// charge, radical and isotopic mass are written on this type directly.
///
/// Every field is reachable, so writing adjacency raw is a caller obligation:
/// `num_bonds` is the count upstream reads, and it counts the three parallel
/// arrays together -- `neighbor`, `bond_type` and `bond_stereo` entry `j` of
/// one atom describe its bond to `neighbor[j]` for `0 <= j < num_bonds`, and
/// nothing outside that range is read (`inchi_api.h:165-171`). A raw adjacency
/// list therefore stays within `max_bonds_per_atom` entries and keeps
/// `num_bonds` equal to the number of entries it filled; `connect` is what
/// maintains all three for you.
///
/// A `num_bonds` outside `0..max_bonds_per_atom` is refused by `connect` with
/// `error.TooManyNeighbors`, in every optimisation mode, and a refusal writes
/// to neither list.
///
/// `elname` is a zero-terminated field (`inchi_api.h:147`), so the first NUL in
/// it ends the element name however the bytes got there.
pub const Atom = c.inchi_Atom;

/// Upstream's `inchi_Stereo0D`, unchanged.
pub const Stereo0D = c.inchi_Stereo0D;

/// `inchi_Input_PolymerUnit`, unchanged (`inchi_api.h:493-510`): one CTfile
/// Sgroup, which is what upstream reads a polymer unit out of. Borrowed, and
/// read-only -- see `ExtendedMolecule`.
pub const PolymerUnit = c.inchi_Input_PolymerUnit;

/// `inchi_Input_Polymer`, unchanged (`inchi_api.h:513-518`): the unit list a
/// polymer input carries. Upstream copies every field of it, and every element
/// of `alist` and `blist`, into allocations of its own
/// (`inchi_dll.c:3030-3110`), so this stays borrowed for the call and is never
/// written through.
pub const Polymer = c.inchi_Input_Polymer;

/// `inchi_Input_V3000`, unchanged (`inchi_api.h:527-555`): the V3000 Molfile
/// features upstream reads but, as the header itself says, does not yet use
/// ("supported only provisionally: the data are read but not used"). Upstream
/// copies it field by field (`inchi_dll.c:3113-3133` and following), so a
/// caller keeps ownership of every array in it.
pub const V3000 = c.inchi_Input_V3000;

/// `InchiInpData`, unchanged (`inchi_api.h:923-927`). The three fields are the
/// whole contract of the AuxInfo direction: `pInp` is where the caller puts
/// the address of a zeroed `inchi_Input` and where upstream writes the rebuilt
/// structure, `bChiral` is what the source said about chirality, and
/// `szErrMsg` is upstream's own fixed `STR_ERR_LEN`-byte buffer.
pub const AuxData = c.InchiInpData;

/// `STR_ERR_LEN`, the length of `InchiInpData.szErrMsg` (`inchi_api.h:920`).
pub const error_buffer_len: usize = c.STR_ERR_LEN;

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

/// `RetValMol2INCHI` (`inchi_api.h:738-746`), the return codes of
/// `MakeINCHIFromMolfileText`.
///
/// This type preserves the whole header namespace, which is different from
/// `Status`: it includes read and generation failure codes and has no
/// `inchi_Ret_FATAL` or `inchi_Ret_BUSY`. The pinned producer does not emit
/// those distinct failure codes: `MakeINCHIFromMolfileText` collapses both
/// reading and generation failures to `mol2inchi_Ret_ERROR` (`inchi_dll_b.c:184-197`,
/// `inchi_dll_b.c:229-232`), so a caller cannot distinguish them by status.
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
    /// `element_symbol_len` bytes including the terminator. This is the length
    /// failure and nothing else: a symbol carrying an interior NUL is not this
    /// error, it is an atom whose element name ends at that NUL.
    ElementSymbolTooLong,
    /// A bond named an atom outside the molecule, or named the same atom twice.
    AtomIndexOutOfRange,
    /// An adjacency list's `num_bonds` is outside `0..max_bonds_per_atom`, so
    /// this bond has nowhere to go in one of the two atoms. Two records reach
    /// it: a list already holding `max_bonds_per_atom` entries, and a list whose
    /// raw `num_bonds` is negative. The second is not a shorter list -- upstream
    /// reads the field as `for (j = 0; j < num_bonds; j++)`, and the API states
    /// the range at `inchi_api.h:171`, "Index j is in the range 0 <= j <=
    /// (atom[i].num_bonds-1)" -- so a negative count reads nothing at all. It is
    /// a record that counts no entries, and so it has none to append to either.
    TooManyNeighbors,
    /// More atoms, or more 0D stereo descriptors, than the matching `AT_NUM`
    /// field -- `num_atoms` or `num_stereo0D` -- can count. `AT_NUM` is a
    /// `signed short` (`inchi_api.h:124`) and so admits 32767. That is this
    /// facade's representable count, not the library's accepted molecule size:
    /// upstream's own structural ceiling is `MAX_ATOMS`, 32766
    /// (`ichisize.h:50`), and the size it treats as the ordinary input is
    /// `NORMALLY_ALLOWED_INP_MAX_ATOMS`, 1024 (`ichisize.h:51`). A molecule
    /// between those is not refused here; it reaches upstream and whatever
    /// upstream makes of it arrives as an `Output.status` or `Structure.status`.
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
/// with no copy at all. `GetINCHIEx` is the one upstream entry point that
/// writes, which is why it takes an `ExtendedMolecule` with mutable atoms
/// instead of this one.
pub const Molecule = struct {
    atoms: []const Atom,
    /// 0D stereo descriptors. Empty means "no 0D stereo", which is what a NULL
    /// pointer with `num_stereo0D == 0` means upstream
    /// (`readinch.c:150`).
    stereo0d: []const Stereo0D = &.{},
    /// Upstream's own option string, verbatim: space delimited, every option
    /// preceded by `/` or `-` depending on the platform the caller builds for.
    /// Pass it through unchanged; this module adds and removes no option.
    ///
    /// `null` and `""` are the same call -- no options at all -- but they get
    /// there differently: a null string takes upstream's branch that fixes
    /// `argc` at 1 without parsing anything (`inchi_dll.c:488-492`), while an
    /// empty one is copied and parsed and comes back with the same `argc == 1`
    /// because `parse_options_string` finds no argument in it
    /// (`inchi_dll.c:1046-1062`). Neither is a way to ask for an empty
    /// argument list or to suppress an option.
    options: ?[:0]const u8 = null,
};

/// A structure to hand to `GetINCHIEx`, upstream's v1.05+ extended input
/// (`inchi_InputEx`, `inchi_api.h:561-580`).
///
/// `atoms` is `[]Atom` and not `[]const Atom` because `GetINCHIEx` writes
/// through it: before anything else it rewrites every `*` element name in
/// place to `Zz`, which is what lets a wildcard atom reach normalization at
/// all (`inchi_dll.c:325-340`). That rewrite is the entry point's documented
/// behaviour and not an accident, so a caller whose atom names must survive
/// the call has to hand over a copy; `Molecule` is the type that promises the
/// names are only read, and this one does not promise that.
///
/// `polymer` and `v3000` are borrowed and read-only. Upstream copies each
/// polymer unit field by field, and every element of its `alist` and `blist`,
/// into allocations of its own (`inchi_dll.c:3054-3110`), and copies the
/// V3000 block the same way (`inchi_dll.c:3113-3133`); nothing in either is
/// written and nothing in either is freed on this side. A null one is what
/// `inchi_InputEx.polymer == NULL` means: "not a polymer" / "no V3000
/// extensions present" (`inchi_api.h:576-579`).
///
/// This is the input the IXA builder itself uses: `IXA_USES_NON_EX_CORE_API`
/// is commented out at `ixa.h:230-231`, so `IXA_INCHIBUILDER` generates
/// through `GetINCHIEx` (`ixa/ixa_builder.c:740-745`) and `IXA_MOL_ReadInChI`
/// rebuilds through `GetStructFromINCHIEx` (`ixa/ixa_read_inchi.c:220-223`).
/// That is why the polymer and V3000 routes are genuinely enabled in this
/// configuration rather than compiled out.
pub const ExtendedMolecule = struct {
    atoms: []Atom,
    /// 0D stereo descriptors, with the same meaning as in `Molecule`.
    stereo0d: []const Stereo0D = &.{},
    /// The option string, with the same meaning and the same `null` / `""`
    /// equivalence as in `Molecule`: upstream copies it into a buffer of its
    /// own before parsing.
    options: ?[:0]const u8 = null,
    /// Polymer Sgroups, or null for a structure that is not a polymer.
    polymer: ?*const Polymer = null,
    /// V3000 Molfile features, or null when there are none.
    v3000: ?*const V3000 = null,
};

/// Whether `GetINCHIKeyFromINCHI` should also produce the two SHA-256
/// extensions. They are two independent 256-bit digests of the two halves of
/// the identifier (`ikey_dll.c:459-475`), not a shorter form of the key: `first`
/// is the `xtra1` 1st block and `second` the `xtra2` 2nd block, and each
/// defaults to false.
pub const Hashes = struct {
    first: bool = false,
    second: bool = false,
};

/// Failures of `GetINCHIKeyFromINCHI` and `GetStdINCHIKeyFromStdINCHI`, one
/// error per `INCHIKEY_*` code the two functions can return
/// (`inchi_api.h:1050-1056`).
///
/// This is the one channel in the module that cannot report a code it did not
/// anticipate: an error tag carries no number, so a code this release does not
/// name arrives here as `error.UnknownFailure` and the number is lost.
/// `Status`, `IdentifierVerdict` and `KeyVerdict` are non-exhaustive enums and
/// keep the raw value a caller did not see named; a caller that has to tell
/// two unmapped codes apart reads those, not a guess at this tag.
pub const KeyError = error{
    /// `INCHIKEY_UNKNOWN_ERROR`, and also the landing place for a code this
    /// release does not name, whose number no tag here can carry.
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

/// `RetValCheckINCHIKeyv` (`inchi_api.h:1060-1067`). Each named verdict keeps
/// its signed native code, including -1 for valid non-standard keys.
/// `CheckINCHIKey` returns a plain `int`; unnamed values are preserved for the
/// same reason as `IdentifierVerdict`.
pub const KeyVerdict = enum(c_int) {
    standard = 0,
    non_standard = -1,
    invalid_length = 1,
    invalid_layout = 2,
    invalid_version = 3,
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
/// One `Output` owns what upstream allocated for it, and one `Output` has one
/// owner, who calls `deinit` exactly once. Assigning or passing the value
/// copies the four pointer fields; the copy is not a second owner and a
/// second `deinit` reached through either name frees the same bytes again.
/// Release on every path that received a value, including the warning and
/// rejection paths: a warning is a qualified success and a rejection may still
/// carry a message.
///
/// Every string is a borrowed window on that allocation, and every one of them
/// is NUL-terminated by upstream itself, so each accessor hands back a sentinel
/// slice rather than a plain one and a caller can pass the identifier straight
/// to `key`, `standardKey`, `checkIdentifier` or back to `fromIdentifier` with
/// no copy in between. The proof is on `spanOrNull`. Every borrowed slice
/// dies at `deinit`.
///
/// `auxInfo` is not a second allocation and has no second release:
/// `produce_generation_output` splits one buffer in two, writing a NUL where
/// the line break was and pointing `szAuxInfo` at the byte after it
/// (`inchi_dll.c:764-777`), and `FreeINCHI` frees `szInChI`, `szLog` and
/// `szMessage` only (`inchi_dll.c:160-171`).
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
    /// layer, or `/AuxNone`). It is the tail of `identifier`'s own allocation,
    /// not a copy of it and not a separate one: it borrows the same bytes, is
    /// released by the same single `deinit`, and must never be freed on its
    /// own.
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

    /// Releases every string through the entry point that allocated them, so
    /// `origin` decides between `FreeStdINCHI` and `FreeINCHI`. Upstream zeroes
    /// the struct as it frees (`inchi_dll.c:173`), so the value holds nothing
    /// afterwards, and the borrowed slices it handed out are gone. Call this
    /// exactly once per value; a copy of the value is a second route to the
    /// same free, not a second owner.
    pub fn deinit(self: *Output) void {
        switch (self.origin) {
            .standard => c.FreeStdINCHI(&self.raw),
            .non_standard => c.FreeINCHI(&self.raw),
        }
    }
};

/// What one `MakeINCHIFromMolfileText` call produced.
///
/// The same allocation, the same four strings, the same accessors and the same
/// release as `Output`, and a different status type. It is a separate value
/// rather than an `Output` with a reinterpreted `status` because upstream
/// returns `RetValMol2INCHI` here and `RetValGetINCHI` everywhere else
/// (`inchi_api.h:711-746`), and folding two code sets into one enum would
/// give a caller a `status` whose arms do not mean the same thing in the two
/// directions. See `MolfileStatus` and `fromMolfile`.
///
/// There is no `origin`: `MakeINCHIFromMolfileText` is one function with one
/// release, `FreeStdINCHI`, which is the same function `FreeINCHI` is
/// (`inchi_dll.c:183-186`).
pub const MolfileOutput = struct {
    raw: c.inchi_Output,
    status: MolfileStatus,

    /// The identifier, or null when upstream produced none. A `warning` status
    /// always has one.
    pub fn identifier(self: *const MolfileOutput) ?[:0]const u8 {
        return spanOrNull(self.raw.szInChI);
    }

    /// The `AuxInfo=` line, or null. It is the tail of the identifier's own
    /// allocation, released by the same single `deinit`, exactly as for
    /// `Output`.
    pub fn auxInfo(self: *const MolfileOutput) ?[:0]const u8 {
        return spanOrNull(self.raw.szAuxInfo);
    }

    /// Upstream's error or warning text, or "".
    pub fn message(self: *const MolfileOutput) [:0]const u8 {
        return spanOrNull(self.raw.szMessage) orelse "";
    }

    /// The recognised options and the human-readable log, or "". This one is
    /// written on every return from the entry point, refusal included.
    pub fn log(self: *const MolfileOutput) [:0]const u8 {
        return spanOrNull(self.raw.szLog) orelse "";
    }

    /// Whether the identifier is usable but qualified.
    pub fn isWarning(self: *const MolfileOutput) bool {
        return self.status == .warning;
    }

    /// Releases the four strings through `FreeStdINCHI`, which zeroes the
    /// struct as it frees (`inchi_dll.c:160-173`). Call this exactly once per
    /// value, and call it on a refusal too: the log is written there.
    pub fn deinit(self: *MolfileOutput) void {
        c.FreeStdINCHI(&self.raw);
    }
};

/// Upstream's `WarningFlags`, `unsigned long[2][2]` (`inchi_api.h:646-652`),
/// copied out of the structure upstream filled.
///
/// The array is indexed `[x][y]`, and the header states both axes itself
/// (`inchi_api.h:647-652`):
///
///   * `x = 0` is the Reconnected layer where the identifier has one, and the
///     Disconnected/Normal layer where it does not; `x = 1` is the Disconnected
///     layer, and it carries a layer only when a Reconnected one is present.
///   * `y = 0` is the Fixed-H layer; `y = 1` is the Main layer, or Mobile-H.
///
/// Each cell is a bit set, and the bits are the `INCHIDIFF_*` names defined in
/// `inchicmp.h` (`inchicmp.h:47-93`). This module does not give those names Zig
/// values: the cell is upstream's raw word, and those definitions are where a
/// caller reads a bit against a fixed revision.
pub const Warnings = [2][2]c_ulong;

/// What one `GetStructFromStdINCHI` / `GetStructFromINCHI` call produced.
///
/// One `Structure` owns the atom array, the 0D-stereo array and the two strings
/// upstream allocated for it, and one `Structure` has one owner, who calls
/// `deinit` exactly once. Copying the value duplicates those pointers and is
/// not a second owner: a second `deinit` reached through either name frees the
/// same bytes again. Release on every path that received a value, including a
/// refusal, which still carries a message.
///
/// Every accessor borrows from that one ownership. The atom and 0D-stereo
/// arrays are upstream allocations inside one buffer each, valid until
/// `deinit` and dead after it, and they feed straight back into a `Molecule`
/// for the opposite direction with no copy at all.
pub const Structure = struct {
    raw: c.inchi_OutputStruct,
    status: Status,
    origin: Origin,

    /// The atoms, borrowed from this value's allocation. Hydrogens are implicit
    /// unless the identifier listed them explicitly, exactly as upstream
    /// reports them, and the slice is empty when the call produced no structure
    /// at all. It is valid until `deinit` and dead after it; it is `[]const`
    /// because nothing here writes through it.
    pub fn atoms(self: *const Structure) []const Atom {
        return borrowedArray(Atom, self.raw.atom, self.raw.num_atoms);
    }

    /// The 0D stereo descriptors, borrowed from this value's allocation and
    /// empty when the identifier carried none. Same lifetime as `atoms`.
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
    /// structure, by value; `Warnings` states what each index means and where
    /// the bits are named.
    pub fn warnings(self: *const Structure) Warnings {
        return self.raw.WarningFlags;
    }

    /// Whether the returned status is `inchi_Ret_WARNING`. Difference flags
    /// are a separate channel and can be set with a non-warning status
    /// (`inchi_dll.c:2818-2841`).
    pub fn isWarning(self: *const Structure) bool {
        return self.status == .warning;
    }

    /// Releases the arrays and strings through the entry point that allocated
    /// them, so `origin` decides between `FreeStructFromStdINCHI` and
    /// `FreeStructFromINCHI`. Upstream zeroes the struct as it frees
    /// (`inchi_dll.c:232`), so the value holds nothing afterwards and every
    /// borrowed slice it handed out is gone. Call this exactly once per value;
    /// a copy of the value is a second route to the same free, not a second
    /// owner.
    pub fn deinit(self: *Structure) void {
        switch (self.origin) {
            .standard => c.FreeStructFromStdINCHI(&self.raw),
            .non_standard => c.FreeStructFromINCHI(&self.raw),
        }
    }
};

/// What one `GetStructFromINCHIEx` call produced, upstream's
/// `inchi_OutputStructEx` (`inchi_api.h:657-676`).
///
/// Everything a `Structure` holds and two more members: the polymer and V3000
/// blocks upstream rebuilt alongside the atoms. Those two are upstream
/// allocations inside this value's ownership and are released by the same
/// `deinit`; they are borrowed slices of pointers here and must never be
/// freed by a caller.
///
/// `polymer` and `v3000` are borrowed from the provider and are valid until
/// `deinit`. Unlike the atom and 0D-stereo arrays they are *structures*, not
/// arrays, and what they contain is upstream's own reading of the identifier:
/// `inchi_Input_Polymer` and `inchi_Input_V3000` reused as the output types
/// (`inchi_api.h:599-601`). What a unit's `alist` and `blist` point at, and
/// what every V3000 `lists_*` row points at, are separate upstream
/// allocations released by the same call, so a caller reads through them and
/// does not own them.
///
/// Release it exactly once per value, as for `Output` and `Structure`. The
/// entry point is `FreeStructFromINCHIEx` in both cases; `origin` is kept
/// because the pairing the creator promised is the one `deinit` honours, and
/// because this type is the only result in the module that also has to reach
/// the polymer and V3000 blocks to be fully released.
pub const ExtendedStructure = struct {
    raw: c.inchi_OutputStructEx,
    status: Status,
    origin: Origin,

    /// The atoms, borrowed from this value's allocation, with the same
    /// lifetime and the same emptiness rule as `Structure.atoms`.
    pub fn atoms(self: *const ExtendedStructure) []const Atom {
        return borrowedArray(Atom, self.raw.atom, self.raw.num_atoms);
    }

    /// The 0D stereo descriptors, with the same lifetime as `atoms`.
    pub fn stereo0d(self: *const ExtendedStructure) []const Stereo0D {
        return borrowedArray(Stereo0D, self.raw.stereo0D, self.raw.num_stereo0D);
    }

    /// The polymer block, or null when the identifier carried none. Borrowed
    /// from the provider; see the type's own declaration.
    pub fn polymer(self: *const ExtendedStructure) ?*const Polymer {
        return optionalStruct(Polymer, self.raw.polymer);
    }

    /// The V3000 block, or null when the identifier carried none. Borrowed
    /// from the provider; see the type's own declaration.
    pub fn v3000(self: *const ExtendedStructure) ?*const V3000 {
        return optionalStruct(V3000, self.raw.v3000);
    }

    /// Upstream's error or warning text, or "". Upstream owns the terminator.
    pub fn message(self: *const ExtendedStructure) [:0]const u8 {
        return spanOrNull(self.raw.szMessage) orelse "";
    }

    /// Upstream's log, or "".
    pub fn log(self: *const ExtendedStructure) [:0]const u8 {
        return spanOrNull(self.raw.szLog) orelse "";
    }

    /// The per-layer difference flags, by value, with the same meaning as in
    /// `Structure.warnings`.
    pub fn warnings(self: *const ExtendedStructure) Warnings {
        return self.raw.WarningFlags;
    }

    /// Whether the returned status is `inchi_Ret_WARNING`.
    pub fn isWarning(self: *const ExtendedStructure) bool {
        return self.status == .warning;
    }

    /// Releases the arrays, the strings, the polymer block and the V3000 block
    /// through `FreeStructFromINCHIEx`, which zeroes the struct as it frees
    /// (`inchi_dll.c:2891-2920`). That call also runs upstream's own
    /// `FreeInChIExtInput` (`inchi_dll.c:2915`), which is the only reason a
    /// caller does not need that function -- and the only reason this type
    /// routes the release through the entry point rather than through it.
    ///
    /// Call this exactly once per value, on every path including the refusals.
    /// `FreeStructFromINCHIEx` frees each member only when it is non-null and
    /// then zeroes the whole struct (`inchi_dll.c:2891-2920`), so a partial
    /// result -- a log from a failed parse and no atoms, which is what
    /// `GetStructFromINCHIEx` leaves behind, unlike
    /// `GetStructFromStdINCHI` which refuses a non-standard identifier before
    /// writing anything at all (`inchi_dll.c:2464-2476`) -- is released
    /// exactly once and the value is empty afterwards, exactly as for `Output`
    /// and `Structure`.
    pub fn deinit(self: *ExtendedStructure) void {
        c.FreeStructFromINCHIEx(&self.raw);
    }
};

/// What one `Get_std_inchi_Input_FromAuxInfo` or
/// `Get_inchi_Input_FromAuxInfo` call produced.
///
/// This direction is different from the other two in a way that matters: the
/// structure does not arrive inside a fresh output struct. Upstream writes it
/// into an `inchi_Input` the *caller* supplied, through the `pInp` field of
/// `InchiInpData` (`inchi_api.h:923-927`, `ichilnct.c:113-122`), and it
/// memsets both structs first -- preserving only `pInp->szOptions`, which is
/// why this value keeps the options it was given rather than dropping them.
///
/// The atom and 0D-stereo arrays inside are upstream allocations and are this
/// value's to release; the `szOptions` pointer is still the caller's and is
/// never freed (`ichilnct.c:187-193`, which frees the atom and stereo pointers
/// and nothing else).
///
/// `deinit` is safe on every path, including the refusal ones, and is safe to
/// call after upstream already released internally: on any status other than
/// `okay` or `warning` upstream calls `Free_inchi_Input` itself
/// (`ichilnct.c:173-177`), and that release NULLs both pointers
/// (`inchi_dll_b.c:106-113`, `readinch.c:125-132`) and zeroes both counts
/// (`ichilnct.c:191-192`), so the second release finds nothing to release. A
/// release on the failure path is therefore required for symmetry and is not a
/// double free.
pub const AuxStructure = struct {
    raw: c.inchi_Input,
    data: AuxData,
    status: Status,
    origin: Origin,

    /// The atoms upstream rebuilt, borrowed from this value's allocation, with
    /// the same emptiness rule as `Structure.atoms`.
    pub fn atoms(self: *const AuxStructure) []const Atom {
        return borrowedArray(Atom, self.raw.atom, self.raw.num_atoms);
    }

    /// The 0D stereo descriptors, borrowed with the same lifetime as `atoms`.
    pub fn stereo0d(self: *const AuxStructure) []const Stereo0D {
        return borrowedArray(Stereo0D, self.raw.stereo0D, self.raw.num_stereo0D);
    }

    /// What the AuxInfo line said about chirality: 1 for chiral, 2 for not
    /// chiral, 0 for not marked (`inchi_api.h:925`). Upstream sets it from the
    /// parsed source and resets it to 0 on any refusal (`ichilnct.c:140`,
    /// `:176`).
    pub fn chiralMark(self: *const AuxStructure) u3 {
        return @truncate(self.data.bChiral);
    }

    /// Upstream's parse diagnostics, read out of the fixed `STR_ERR_LEN`-byte
    /// buffer `InchiInpData` carries.
    ///
    /// It is a plain slice and not a sentinel one on purpose: upstream zeroes
    /// the whole record before parsing (`ichilnct.c:118`) and fills the buffer
    /// with a terminating copy, so the bytes before the first NUL are the
    /// message and nothing beyond it is claimed to be anything. A caller that
    /// needs a C string can use the status instead.
    pub fn parseMessage(self: *const AuxStructure) []const u8 {
        const field: []const u8 = &self.data.szErrMsg;
        const end = std.mem.indexOfScalar(u8, field, 0) orelse field.len;
        return field[0..end];
    }

    /// A `Molecule` view of what upstream rebuilt, borrowing this value's
    /// arrays and the caller's own option string. Feeds straight back into
    /// `fromMolecule` with no copy, exactly as `Structure`'s does.
    ///
    /// The options are the ones the reader was given: upstream preserves
    /// `pInp->szOptions` across the memset that clears the rest of the record
    /// (`ichilnct.c:118-121`). They are borrowed caller bytes, not a copy, and
    /// are alive for as long as they were before the call.
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

    /// Releases the atom and 0D-stereo arrays through the entry point whose
    /// promise was made: `Free_std_inchi_Input` for the standard reader and
    /// `Free_inchi_Input` for the general one. They are the same function today
    /// (`ichilnct.c:182-185`), kept apart for the same reason `Output` and
    /// `Structure` keep their `origin`: the pairing that matters is the one the
    /// creator promised. Call exactly once per value.
    pub fn deinit(self: *AuxStructure) void {
        switch (self.origin) {
            .standard => c.Free_std_inchi_Input(&self.raw),
            .non_standard => c.Free_inchi_Input(&self.raw),
        }
    }
};

/// An InChIKey and, on request, its two SHA-256 extensions.
///
/// The buffers are fixed at the sizes the header asks for, so there is nothing
/// to size and nothing to overflow. They live in the returned value, so the key
/// does not borrow from anything the caller has to keep alive, and there is
/// nothing to release. Unlike `Output` and `Structure` this is an ordinary
/// value: a copy carries the bytes with it and is independently readable, so
/// any number of copies are safe and none of them owns anything.
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
/// (`inchi_api.h:147`). The bytes go into a zeroed field verbatim, so a NUL
/// inside `symbol` is neither rejected nor an error of its own: it ends the
/// element name there, and the atom InChI reads is the one named by the bytes
/// before it. Everything else starts at zero: no coordinates (so InChI reads
/// the molecule's 0D parities, `inchi_api.h:297-300`), no bonds, no charge, no
/// radical, no isotopic mass. Those are raw fields on the returned `Atom` for a
/// caller to set, and `num_bonds` is the raw count that goes with a raw
/// adjacency list.
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
/// Either the bond lands in both lists or in neither: both counts are checked
/// before anything is written. A count outside `0..max_bonds_per_atom` is
/// refused with `error.TooManyNeighbors` from both ends alike -- a list already
/// full, and a list whose raw `num_bonds` is negative -- and the two answers do
/// not depend on `-Doptimize`.
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
/// double-bond chain in `central_atom` instead (`inchi_api.h:272-290`). Write
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
///
/// The only error either entry point raises is `error.TooManyAtoms`, and it
/// is raised while the input struct is being filled, before upstream is
/// called. An `error` from here therefore leaves nothing allocated and nothing
/// to release; every other outcome is a returned `Output`, including the
/// rejection ones.
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

    /// Upstream's `GetINCHIEx`: the same generation as `full`, plus the
    /// polymer and V3000 extensions of `inchi_InputEx`.
    ///
    /// This is the only entry point in the module that writes through the
    /// caller's atoms -- it rewrites every `*` element name to `Zz` before
    /// anything else (`inchi_dll.c:325-340`) -- which is why it takes an
    /// `ExtendedMolecule` and not a `Molecule`. `origin` is `.non_standard`
    /// because this is the `GetINCHI` family and `FreeINCHI` is the release
    /// the header pairs with it (`inchi_api.h:840-851`); whether the
    /// identifier that comes back is standard is decided by the option string,
    /// exactly as for `full`.
    pub fn extended(molecule: ExtendedMolecule) Error!Output {
        var input = try extendedInputStruct(molecule);
        var raw: c.inchi_Output = std.mem.zeroes(c.inchi_Output);
        const code = c.GetINCHIEx(&input, &raw);
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
///
/// `text` and `options` are borrowed for the duration of the call and are not
/// retained. What comes back borrows memory upstream allocated; it never
/// borrows the caller's bytes.
///
/// `null` and `""` mean no options here as well, and they get there by a
/// different route than `Molecule.options` does: these entry points test the
/// input pointer, not the option pointer (`inchi_dll.c:2210`,
/// `inchi_dll.c:2579`), so a null option string and an empty one are both
/// copied into a buffer that upstream then appends its own main option to --
/// `" ?InChI2InChI"` or `" ?InChI2Struct"` (`inchi_dll.c:2120`,
/// `inchi_dll.c:2503`, `inchi_dll.c:2220`, `inchi_dll.c:2589`) -- and parses
/// that. An empty string is therefore nothing added, not anything cleared.
///
/// Nothing in this namespace raises `Error`: filling the input struct cannot
/// fail, and every failure these entry points report arrives as
/// `Structure.status` or `Output.status` with its message attached. The
/// `Error!` in each signature is therefore an upper bound over the module's
/// one set, not a list of reachable outcomes -- `error.TooManyAtoms` belongs
/// to the other direction only.
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

    /// Upstream's `GetStructFromINCHIEx`: rebuild a structure and, when the
    /// identifier carries them, the polymer and V3000 blocks beside it.
    ///
    /// Unlike `standard` it does not screen the identifier up front.
    /// `GetStructFromStdINCHI` checks the `InChI=1S/` prefix and refuses
    /// anything else before delegating (`inchi_dll.c:2464-2476`), and
    /// `GetStructFromINCHIEx` is not that wrapper: it is the worker itself
    /// (`inchi_dll.c:2484-2503`), so this is the reader that both a standard
    /// and a non-standard identifier reach.
    ///
    /// The result is released by `FreeStructFromINCHIEx`, which is what
    /// releases the polymer and V3000 blocks as well; `origin` is recorded for
    /// the same reason `Structure` records it, not because this entry point
    /// has a second release.
    pub fn extended(text: [:0]const u8, options: ?[:0]const u8) Error!ExtendedStructure {
        var input = identifierInput(text, options);
        var raw: c.inchi_OutputStructEx = std.mem.zeroes(c.inchi_OutputStructEx);
        const code = c.GetStructFromINCHIEx(&input, &raw);
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
// AuxInfo -> structure, and molfile -> identifier
// ---------------------------------------------------------------------------

/// The direction that starts from an AuxInfo line rather than from an
/// identifier.
///
/// This is the only direction in the module that writes into a struct the
/// *caller* supplied. Both readers take an `InchiInpData` whose `pInp` must be
/// a valid pointer to an `inchi_Input` the caller owns, and they fill that
/// struct in place (`inchi_api.h:948-955`, `ichilnct.c:113-126`): with a null
/// `pInp` upstream answers `Status.rejected` and touches nothing. This module
/// supplies the struct itself, so a caller passes the text and gets a value
/// that owns the result.
///
/// `aux_info` may be either the two-line InChI-plus-AuxInfo output of a run or
/// the `AuxInfo=` line alone (`inchi_api.h:942-943`); upstream reads a leading
/// `InChI=` line and skips it if it finds one. `options` is borrowed, copied by
/// upstream before parsing, and *survives* into the result: upstream preserves
/// `pInp->szOptions` across the memset that clears everything else
/// (`ichilnct.c:118-121`), which is why `AuxStructure.raw.szOptions` is a
/// pointer this module never owns and never frees.
///
/// `do_not_add_h` is upstream's own switch and not a re-derivation of anything
/// else here: zero lets InChI add the implicit hydrogens itself, non-zero means
/// every hydrogen in the AuxInfo line is explicit (`inchi_api.h:943-945`).
///
/// Nothing in this namespace raises `Error`. Every outcome is a returned
/// `AuxStructure`, refusals included, and `status` plus `parseMessage` say
/// what happened. The `Error!` in each signature is an upper bound over the
/// module's one error set, as in `fromIdentifier`.
pub const fromAuxInfo = struct {
    /// Upstream's `Get_std_inchi_Input_FromAuxInfo`, which is
    /// `Get_inchi_Input_FromAuxInfo` with `bDiffUnkUndfStereo` fixed at zero
    /// (`ichilnct.c:79-87`).
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

    /// Upstream's `Get_inchi_Input_FromAuxInfo`.
    ///
    /// `distinguish_unknown_undefined` is `bDiffUnkUndfStereo`: non-zero makes
    /// upstream read an unknown parity as `AB_PARITY_UNKN` where it otherwise
    /// reads it as `AB_PARITY_UNDF` (`ichilnct.c:104-109`). That is a
    /// difference in the *labels* it produces, so the structure it returns can
    /// differ in a stereo0D parity rather than only in a name.
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

/// Upstream's `MakeINCHIFromMolfileText`: an identifier straight out of a
/// molfile, with no structure built by the caller at all.
///
/// This is the entry point that needs no `inchi_Input` from the caller and no
/// `Molecule` in the caller's storage, and it is also the one that turns the
/// polymer extensions on by itself: it sets `valid_polymer = 1` for any polymer
/// the molfile's Sgroups describe, before processing (`inchi_dll_b.c:207-211`),
/// where the atom-array route has to be handed the polymer explicitly.
///
/// `text` is borrowed: upstream reads it into a string stream of its own and
/// never writes through it. `options` is borrowed and copied before parsing
/// (`inchi_dll_b.c:308-316`). Both are untouched afterwards.
///
/// The status is `MolfileStatus`, not `Status`, because upstream returns a
/// different code set here; see that type. The strings are allocated exactly as
/// `GetStdINCHI` allocates them -- `produce_generation_output`
/// (`inchi_dll_b.c:220-228`) and `copy_corrected_log_tail` -- so the release is
/// `FreeStdINCHI` and the accessors are the same as `Output`'s.
///
/// The struct is zeroed before the call and the result must be released on
/// every path, including a refusal, because `copy_corrected_log_tail` writes
/// `out->szLog` on every return from this function
/// (`inchi_dll_b.c:257-273`, `inchi_dll.c:787-800`) including the ones that
/// produced no identifier at all. That is the one place in this module where a
/// failed call still owns memory.
pub fn fromMolfile(text: [:0]const u8, options: ?[:0]const u8) Error!MolfileOutput {
    var raw: c.inchi_Output = std.mem.zeroes(c.inchi_Output);
    const moltext: [*c]const u8 = text.ptr;
    const code = c.MakeINCHIFromMolfileText(moltext, optionsPointer(options), &raw);
    return .{ .raw = raw, .status = @enumFromInt(code) };
}

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
///
/// Both hash fields of `hashes` default to false, and an unset one is not
/// computed and is not reported by `firstHash()` / `secondHash()`. `text` is
/// borrowed for the call. A `KeyError` returns no value and allocates nothing:
/// the key and the hashes live in buffers the returned value carries, so
/// neither path leaves anything to release.
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
/// extension hash, so `first_hash` and `second_hash` are always null on the
/// value it returns. `text` is borrowed for the call and an error allocates
/// nothing, as in `key`.
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
/// "No options" and "an empty option string" are the same call in both
/// directions, but upstream converges on that through different control flow,
/// and this module keeps the one normalisation rather than adding a second
/// layer for each. It never hands C a null option pointer, because neither
/// direction would gain anything from one:
///
///   * Structure to identifier. `GetStdINCHI` and `GetINCHI` test the option
///     pointer, so a null one skips the copy and the parse and fixes `argc` at
///     1 outright (`inchi_dll.c:474-493`), while a zero-length one is copied
///     and parsed (`inchi_dll.c:476-480`) into that same `argc == 1`:
///     `parse_options_string` finds no argument in an empty command
///     (`inchi_dll.c:1046-1062`) and `ReadCommandLineParms` only ever reads
///     `argv[1..argc-1]` (`ichiparm.c:776`).
///   * Identifier to structure, and identifier to identifier. Those entry
///     points test the input pointer, not the option pointer
///     (`inchi_dll.c:2210`, `inchi_dll.c:2579`), so both spellings are copied
///     into a buffer upstream then appends its own main option to
///     (`inchi_dll.c:2220`, `inchi_dll.c:2589`) and parses. An empty string
///     and a null one both leave the buffer holding that main option alone;
///     neither is an argument of its own.
///
/// Where a caller sees the consequence, `Molecule.options` and
/// `fromIdentifier` say so at their own declarations.
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
/// `inchi_Input.atom` is `inchi_Atom *`, not `const inchi_Atom *`. Nothing on
/// this path writes through it -- the one entry point that does is `GetINCHIEx`
/// (`inchi_dll.c:330-336`), and it is reachable only through
/// `ExtendedMolecule`, whose atoms are `[]Atom` precisely so that the cast is
/// not needed there either.
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

/// Fills the `inchi_InputEx` `GetINCHIEx` reads, and returns it by value.
///
/// Same non-const obligation as `inputStruct`, and the same narrow casts: the
/// C field types are `inchi_Atom *` and `inchi_Input_Polymer *`, not const
/// variants. What differs is what upstream does with them.
///
/// The atoms are handed over as the mutable slice they are, because
/// `GetINCHIEx` rewrites `*` to `Zz` through this pointer
/// (`inchi_dll.c:330-336`) and a `const` promise here would be false. The
/// polymer and V3000 blocks are cast the other way, to `*const`, and that
/// cast is true: upstream reads every scalar of a polymer unit and copies
/// every element of its `alist` and `blist` into its own allocation
/// (`inchi_dll.c:3054-3110`), and copies the V3000 block the same way
/// (`inchi_dll.c:3113-3133`), so no path writes through either pointer.
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
/// NULL (`inchi_api.h:640`). A translated C pointer carries no null in its
/// type, so the count is what has to be read first: casting a null `[*c]T` to
/// a non-optional `[*]const T` is a safety-check panic, not an empty slice.
/// Upstream never pairs a positive count with a null pointer, so the count
/// alone decides.
fn borrowedArray(comptime T: type, pointer: [*c]T, count: anytype) []const T {
    if (count <= 0) return &.{};
    const base: [*]const T = pointer;
    return base[0..@intCast(count)];
}

/// Borrows one of upstream's optional output blocks, and answers null when
/// there is none.
///
/// A translated C pointer carries no null in its type, so the address is what
/// is compared, exactly as in `spanOrNull`. `inchi_OutputStructEx.polymer` and
/// `.v3000` are null whenever the identifier described no polymer and no V3000
/// extensions (`inchi_api.h:674-675`, and `inchi_dll.c:2737-2760` for where
/// they are filled), and `FreeStructFromINCHIEx` tests each of them for null
/// before releasing it (`inchi_dll.c:2912-2916`), so "absent" is a state
/// upstream itself acts on rather than an empty record.
fn optionalStruct(comptime T: type, pointer: [*c]T) ?*const T {
    if (@intFromPtr(pointer) == 0) return null;
    return pointer;
}

/// The number of adjacency entries `count` names, as an index and as a length.
///
/// `Atom.num_bonds` is an `AT_NUM`, a `signed short` (`inchi_api.h:124`), and it
/// is a raw field on a caller-writable struct, so a negative value is
/// representable and this conversion has to be total. Casting one directly is
/// not: a checked `@intCast` traps on it in Debug and ReleaseSafe, while the
/// unchecked form wraps it to a huge value in ReleaseFast and ReleaseSmall, so
/// one `connect` call would answer two different ways according to
/// `-Doptimize`. Upstream never reads a negative count -- every adjacency loop
/// is `for (j = 0; j < num_bonds; j++)`, at
/// `INCHI-1-SRC/INCHI_API/libinchi/src/ichilnct.c:297` among them -- and visits
/// nothing when it is negative, so zero is the honest answer here. `connect`
/// refuses such a record before this is ever handed one.
fn used(count: i16) usize {
    return if (count <= 0) 0 else @intCast(count);
}

/// Whether an adjacency list cannot take another entry.
///
/// The count upstream reads is a count over `0..max_bonds_per_atom`, and the
/// API says so at `inchi_api.h:171`. The field holding it is a caller-writable
/// `AT_NUM`, so every value outside that range is representable and each is a
/// record this module cannot append to: a full list has nowhere to put the
/// bond, and a negative count is not a count of anything, so there is no entry
/// to append to at all. Both ends are compared with an ordinary comparison,
/// before either list is written.
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
