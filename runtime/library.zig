//! SPDX-License-Identifier: LicenseRef-InChI-MIT-Conditional
//! See FORK-LICENSE.md for the full grant and the owner authorization behind it.
//! InChI runtime-loader descriptor and provider ABI requirements.
//! Buffers returned by InChI stay provider-owned and require matching `Free*` calls.

const rt = @import("rt");

/// Namespaced synchronization hooks used by one loader instance.
pub const Sync = struct {
    extern fn inchi_rt_lock() void;
    extern fn inchi_rt_unlock() void;
    extern fn inchi_rt_wait() void;
    extern fn inchi_rt_broadcast() void;
    // Matches C `unsigned long long` on supported targets.
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

/// Bind the loader to this SDK's generated dispatch.
pub fn Config(comptime dispatch: type) type {
    return struct {
        /// Name used in loader diagnostics.
        pub const library_name = "inchi";

        /// Generated symbol table and inventories.
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

        /// Store an optional address or mark its slot missing.
        pub inline fn assignOptional(comptime index: usize, dst: *table, address: *const anyopaque) void {
            dispatch.assignOptional(index, dst, address);
        }

        pub inline fn assignMissing(comptime index: usize, dst: *table) void {
            dispatch.assignMissing(index, dst);
        }

        /// Check valid and invalid InChIKeys; return a diagnostic on mismatch.
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
