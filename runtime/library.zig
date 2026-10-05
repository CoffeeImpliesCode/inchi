//! SPDX-License-Identifier: LicenseRef-InChI-MIT-Conditional
//! See FORK-LICENSE.md for the full grant and the owner authorization behind it.
//
//! InChI's side of the runtime loader: the names its synchronization binding
//! has, and what it requires of a provider beyond resolving its symbols.
//!
//! Everything else about the runtime route is generic. `runtime/loader.zig` is
//! the state machine and the platform layer; `runtime/generate.zig` builds the
//! dispatch from whatever the translation step actually produced;
//! `runtime/graph.zig` wires them together. This file is what makes them InChI's,
//! and it is the file another SDK replaces.
//!
//! ## What a provider must export
//!
//! Every `extern` the translated header declares, which is `translate.h` over
//! `inchi_api.h` and, through `inchi_api.h:1413`, `ixa.h` as well. That is the
//! `GetINCHI` / `GetStdINCHI` / `GetINCHIEx` generation surface, the
//! `GetStructFrom*` rebuild surface, every `Free*`, the AuxInfo conversion pair
//! and its release pair, the key surface (`GetINCHIKeyFromINCHI`,
//! `GetStdINCHIKeyFromStdINCHI`, `CheckINCHIKey`), `CheckINCHI`,
//! `MakeINCHIFromMolfileText`, the whole `INCHIGEN_*` / `STDINCHIGEN_*`
//! modularized generator, and all 110 `IXA_*` entry points.
//!
//! One declared function is not on that list, and the reason is in upstream's
//! own files rather than in anything decided here:
//!
//!   * `FreeInChIExtInput` (`inchi_api.h:678`) is declared without the
//!     `EXPIMP_TEMPLATE INCHI_API` decoration the rest carry, is defined at
//!     `inchi_dll.c:2923`, and is *absent* from upstream's own export list --
//!     `INCHI_API/libinchi/gcc/libinchi.map` names 129 globals and this is not
//!     one of them, so the `local: *` on line 3 hides it from a shared ELF
//!     provider. `FreeStructFromINCHIEx` calls it internally
//!     (`inchi_dll.c:2915`), so a caller that releases a structure through the
//!     matching `Free*` needs it not at all. `runtime/graph.zig` therefore keeps
//!     the declaration direct rather than demanding a symbol a real provider
//!     does not export.
//!
//! ## The external ABI family, stated as the header states it
//!
//! The provider must be a C library built from the same `inchi_api.h` and
//! `ixa.h` with the same `MAXVAL` (20), `ATOM_EL_LEN` (6), `NUM_H_ISOTOPES`
//! (3), `STR_ERR_LEN` (256), `MAX_NUM_STEREO_ATOM_NEIGH` (4),
//! `MAX_NUM_STEREO_BONDS` (3), `INCHI_NUM` (2) and `FIND_RING_SYSTEMS` (1)
//! settings, because those are what fix the layouts of `inchi_Atom`,
//! `inchi_Stereo0D`, `InchiInpData`, `NORM_ATOM`, `NORM_ATOMS` and
//! `INCHIGEN_DATA` (`inchi_api.h:105-110`, `:151`, `:404-441`, `:646-668`,
//! `:923-927`, `:1172-1281`). The `inchi_Atom` layout is fixed by the C ABI's
//! own rules on every target this SDK builds for -- three `double`s, two
//! `AT_NUM` arrays of 20, three `S_CHAR` arrays of 20 and 4, a `char[6]`, two
//! `AT_NUM`s and two `S_CHAR`s -- and is what the facade's own `Atom` is, so a
//! provider built from a different header configuration would misread every
//! molecule handed to it.
//!
//! Scalars: `AT_NUM` and `NUM_HS` are `signed short`, `AT_NUMBR` is `unsigned
//! short`, `S_CHAR` is `signed char`, `U_CHAR` is `unsigned char`
//! (`inchi_api.h:113-124`, `:1183-1185`), `INCHI_MODES` and the
//! `WarningFlags` cells are `unsigned long` (`inchi_api.h:646`, `:1185`), and
//! every status is a plain `int`. Nothing here is width-configurable.
//!
//! Calling convention: plain C on every target. `EXPIMP_TEMPLATE`, `INCHI_API`
//! and `INCHI_DECL` are all empty on this build, because `BUILD_LINK_AS_DLL`
//! is not defined and the branch that would add `__declspec` at
//! `inchi_api.h:691-703` also requires `_WIN32` and `_MSC_VER`
//! (`translate.h` says so at length). A provider that *was* built as an
//! `__declspec(dllexport)` DLL is still callable through the table, because a
//! name and a calling convention are all a `dlsym`/`GetProcAddress` result
//! carries; what such a provider adds is an import library for a *linked*
//! build, which is not this route's problem.
//!
//! Allocator: upstream's own. `inchi_malloc` / `inchi_calloc` / `inchi_free`
//! are internal to the library and every allocation a caller receives is
//! released by a matching `Free*` entry point in the same provider. Nothing
//! here allocates, nothing here frees, and no Zig allocator is ever in the
//! path -- which is also why a Zig leak oracle cannot see one.
//!
//! Variadics: none. No declaration in `inchi_api.h` or `ixa.h` is variadic, so
//! the generated dispatch has no variadic wrapper to build.
//!
//! Exported data: none. Neither header declares an `extern` object, so every
//! entry in the table is a function and no `NAMEAddr()` accessor exists.
//!
//! ## The ABI boundary, stated honestly
//!
//! Resolving the symbols and translating the header is the boundary. They are
//! not proof that a provider is compatible, and this file does not pretend to
//! add one. The only thing checked at load time is that `CheckINCHIKey` -- a
//! pure, allocation-free function over one C string (`ikey_dll.c:513-597`) --
//! classifies a published InChIKey as a valid standard key and a string that is
//! plainly not one as invalid. That is a check that two routed entry points
//! behave, not a compatibility verdict: a provider compiled from a different
//! `MAXVAL` would answer it correctly and still misread a molecule.

const rt = @import("rt");

/// The synchronization this loader calls, bound by exact name.
///
/// The names below are `runtime/sync.h` compiled with
/// `RT_SYNC_PREFIX=inchi_rt`, which is what `runtime/graph.zig` passes. Two
/// spellings of that prefix have to agree: this file names the symbols, and
/// graph.zig defines the macro. A build where they disagree does not link, and
/// that is the whole error report: there is no runtime path that could hide it.
///
/// The core in `runtime/loader.zig` never names a symbol of its own, which is
/// what lets two SDKs, or two configurations of one SDK, hold their own loader
/// state in one process without sharing any of it.
pub const Sync = struct {
    extern fn inchi_rt_lock() void;
    extern fn inchi_rt_unlock() void;
    extern fn inchi_rt_wait() void;
    extern fn inchi_rt_broadcast() void;
    // `unsigned long long`. Declared as u64, which is the same type in every
    // ABI this SDK targets: 64-bit on x86_64, aarch64, riscv64 and wasm32.
    extern fn inchi_rt_thread_self() u64;

    pub fn lock() void {
        inchi_rt_lock();
    }
    pub fn unlock() void {
        inchi_rt_unlock();
    }
    pub fn wait() void {
        inchi_rt_wait();
    }
    pub fn broadcast() void {
        inchi_rt_broadcast();
    }
    pub fn threadSelf() u64 {
        return inchi_rt_thread_self();
    }
};

/// The loader's configuration for this SDK, given the dispatch that owns the
/// table.
///
/// `dispatch` is the generated module, passed as a type by the dispatch itself
/// so that this file never has to import it. The direction is one-way on
/// purpose: the descriptor knows what the loader needs, the dispatch knows what
/// the header said, and neither imports the other.
pub fn Config(comptime dispatch: type) type {
    return struct {
        /// Named in the pre-load panic, so the message says which library was
        /// reached for before it was loaded.
        pub const library_name = "inchi";

        /// The table the generated dispatch declares, and the symbols it needs
        /// to fill it. Both come from the translated header, not from this file.
        pub const table = dispatch.Table;
        pub const symbols = dispatch.symbols;
        pub const optional_symbols = dispatch.optional_symbols;

        /// The project's namespaced synchronization binding.
        pub const sync = Sync;

        pub fn tablePtr() *table {
            return dispatch.tablePtr();
        }

        pub fn ready() *rt.Ready {
            return &dispatch.ready;
        }

        pub fn assign(comptime index: usize, dst: *table, address: *const anyopaque) void {
            dispatch.assign(index, dst, address);
        }

        /// One resolved address into one optional table field, and the empty
        /// case beside it. Both index `optional_symbols`, not `symbols`.
        pub inline fn assignOptional(comptime index: usize, dst: *table, address: *const anyopaque) void {
            dispatch.assignOptional(index, dst, address);
        }

        pub inline fn assignMissing(comptime index: usize, dst: *table) void {
            dispatch.assignMissing(index, dst);
        }

        /// The one library-specific check, run after every symbol resolved and
        /// before anything is published.
        ///
        /// PubChem's published InChIKey for water, and a string that is not a
        /// key at all. `CheckINCHIKey` allocates nothing, keeps no state and
        /// touches no global (`ikey_dll.c:513-597`): it measures a length, two
        /// dash positions and the base-26 alphabet, and answers
        /// `INCHIKEY_VALID_STANDARD` (0) or `INCHIKEY_INVALID_LENGTH` (1). Both
        /// answers are the ones the header documents
        /// (`inchi_api.h:1050-1067`).
        pub fn validate(dst: *const table) ?[]const u8 {
            const water_key = "XLYOFNOQVPJJNP-UHFFFAOYSA-N";
            if (dst.CheckINCHIKey(water_key) != 0) {
                return "CheckINCHIKey() did not accept a published InChIKey, so this " ++
                    "provider is not behaving like the library this header describes";
            }
            if (dst.CheckINCHIKey("not-an-inchikey") == 0) {
                return "CheckINCHIKey() accepted a string that is not an InChIKey, so " ++
                    "this provider is not behaving like the library this header describes";
            }
            return null;
        }
    };
}