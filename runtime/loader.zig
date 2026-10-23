// SPDX-License-Identifier: LicenseRef-InChI-MIT-Conditional
//! Process-wide dynamic loader for a generated C API table.

const std = @import("std");
const builtin = @import("builtin");

/// Select a library by absolute path or platform name; there is no fallback.
pub const LoadSource = union(enum) {
    /// Absolute path; relative paths return `InvalidSource`.
    path: []const u8,
    /// Loader search name; separators and NUL bytes return `InvalidSource`.
    system: []const u8,
};

/// Reasons a library load can fail.
pub const LoadError = error{
    /// The path or name is empty.
    EmptySource,
    /// The request exceeds `max_source_len` and is not truncated.
    SourceTooLong,
    /// The path is not absolute or the name contains a separator or NUL.
    InvalidSource,
    /// The target has no dynamic loader.
    UnsupportedTarget,
    /// The platform loader could not open the provider or a dependency.
    OpenFailed,
    /// The provider lacks a symbol required by the translated header.
    MissingSymbol,
    /// Provider-specific validation declined the opened library.
    ValidationFailed,
    /// Another provider is loaded or currently loading.
    ProviderMismatch,
    /// The loading thread called `load` again.
    ReentrantLoad,
};

/// Maximum request length, in bytes.
pub const max_source_len = 32768;

const SourceRecord = struct {
    tag: enum(u8) { none = 0, path, system } = .none,
    len: u32 = 0,
    bytes: [max_source_len]u8 = undefined,

    fn set(self: *SourceRecord, request: LoadSource) void {
        const text = switch (request) {
            .path => |p| p,
            .system => |s| s,
        };
        @memcpy(self.bytes[0..text.len], text);
        self.len = @intCast(text.len);
        self.tag = switch (request) {
            .path => .path,
            .system => .system,
        };
    }

    pub fn source(self: *const SourceRecord) ?LoadSource {
        const text = self.bytes[0..self.len];
        return switch (self.tag) {
            .none => null,
            .path => .{ .path = text },
            .system => .{ .system = text },
        };
    }
};

/// Compare request kind and bytes without normalization.
pub fn eqlSource(a: LoadSource, b: LoadSource) bool {
    return switch (a) {
        .path => |pa| switch (b) {
            .path => |pb| std.mem.eql(u8, pa, pb),
            .system => false,
        },
        .system => |sa| switch (b) {
            .system => |sb| std.mem.eql(u8, sa, sb),
            .path => false,
        },
    };
}

fn validateSource(source: LoadSource) LoadError!void {
    const text = switch (source) {
        .path => |p| p,
        .system => |s| s,
    };
    if (text.len == 0) return error.EmptySource;
    if (text.len > max_source_len) return error.SourceTooLong;
    if (std.mem.indexOfScalar(u8, text, 0) != null) return error.InvalidSource;
    switch (source) {
        .path => {
            const absolute = if (builtin.os.tag == .windows)
                switch (std.fs.path.getWin32PathType(u8, text)) {
                    .drive_absolute, .unc_absolute, .local_device, .root_local_device => true,
                    .relative, .rooted, .drive_relative => false,
                }
            else
                std.fs.path.isAbsolutePosix(text);
            if (!absolute) return error.InvalidSource;
        },
        .system => {
            for (text) |byte| {
                if (std.fs.path.isSep(byte)) return error.InvalidSource;
                if (builtin.os.tag == .windows and byte == ':') return error.InvalidSource;
            }
        },
    }
}

/// The loader's table-publication phase.
pub const Phase = enum(u8) {
    /// No provider is loaded; a failed attempt returns to this state.
    not_loaded = 0,
    /// One thread is filling the table.
    loading = 1,
    /// The table is published and routed calls are available.
    ready = 2,
};

/// Atomic table readiness state.
/// The loader publishes with release ordering; routed calls read with acquire ordering.
pub const Ready = struct {
    phase: std.atomic.Value(u8) = .init(@backingInt(Phase.not_loaded)),

    /// Check readiness with acquire ordering.
    pub fn isReady(self: *const Ready) bool {
        return self.phase.load(.acquire) == @backingInt(Phase.ready);
    }

    /// Return the current phase with acquire ordering.
    pub fn state(self: *const Ready) Phase {
        return @fromBackingInt(@intCast(self.phase.load(.acquire)));
    }

    /// Publish a phase with release ordering.
    pub fn set(self: *Ready, value: Phase) void {
        self.phase.store(@backingInt(value), .release);
    }
};

/// Kind of exported symbol stored in a table slot.
pub const SymbolKind = enum {
    /// Function address with the translated C function-pointer type.
    function,
    /// Provider-owned object address; the table stores no copy.
    data,
};

/// Required export name and kind.
pub const Symbol = struct {
    /// NUL-terminated exported name from the C header.
    name: [:0]const u8,
    /// Kind of export stored in the table.
    kind: SymbolKind,
};

/// Panic with library and symbol names when a routed call precedes load.
pub fn panicNotReady(library: []const u8, comptime symbol: []const u8) noreturn {
    std.debug.panic(
        "{s}: {s} was called before this module was loaded; call " ++
            "load({{ .path = \"...\" }}) or load({{ .system = \"...\" }}) first",
        .{ library, symbol },
    );
}

/// Whether the target supports dynamic-library loading.
pub const supported_target: bool = switch (builtin.os.tag) {
    .wasi, .emscripten, .freestanding => false,
    else => true,
};

/// Loader for one generated dispatch; Config supplies its table, symbols, sync and assignment hooks.
/// Loads are single-flight and retryable; same requests share a result, while provider changes fail.
pub fn Loader(comptime Config: type) type {
    return struct {
        const LoaderType = @This();

        /// The configured dispatch table type.
        pub const table_type = Config.table;

        attempt: ?Attempt = null,

        request: SourceRecord = .{},

        /// Load a provider; same requests are idempotent and concurrent calls share an attempt.
        /// Returns `LoadError` for invalid input, load failure, provider mismatch or reentrancy.
        pub fn load(self: *LoaderType, source: LoadSource) LoadError!void {
            try validateSource(source);
            // An already-published table handles the common case without taking the lock.
            if (Config.ready().isReady()) return self.accept(source);

            Config.sync.lock();
            while (true) {
                switch (Config.ready().state()) {
                    .ready => {
                        Config.sync.unlock();
                        return self.accept(source);
                    },
                    .loading => {
                        const attempt = &self.attempt.?;
                        if (attempt.owner == Config.sync.threadSelf()) {
                            Config.sync.unlock();
                            return error.ReentrantLoad;
                        }
                        if (!eqlSource(self.request.source().?, source)) {
                            Config.sync.unlock();
                            return error.ProviderMismatch;
                        }
                        // Wait for this attempt instead of starting a competing one.
                        attempt.waiters += 1;
                        while (Config.ready().state() == .loading) Config.sync.wait();
                        const result = attempt.result;
                        attempt.waiters -= 1;
                        // Keep the attempt record until all waiters have read its result.
                        Config.sync.broadcast();
                        Config.sync.unlock();
                        return result;
                    },
                    .not_loaded => {
                        // A retry waits until the previous attempt's waiters drain.
                        if (self.attempt != null) {
                            Config.sync.wait();
                            continue;
                        }
                        break;
                    },
                }
            }

            self.request.set(source);
            self.attempt = .{ .owner = Config.sync.threadSelf() };
            Config.ready().set(.loading);
            Config.sync.unlock();

            // Run provider constructors without holding the synchronization lock.
            const outcome = runAttempt(self.request.source().?);
            const succeeded = if (outcome) |_| true else |_| false;

            Config.sync.lock();
            self.attempt.?.result = outcome;
            Config.ready().set(if (succeeded) .ready else .not_loaded);
            // Wake every waiter; all must leave before the attempt record can be cleared.
            Config.sync.broadcast();
            // Waiters release the lock while draining the record.
            while (self.attempt.?.waiters > 0) Config.sync.wait();
            self.attempt = null;
            // Wake threads waiting to start a retry.
            Config.sync.broadcast();
            Config.sync.unlock();

            return outcome;
        }

        /// Return the retained request, valid for process lifetime, or null.
        pub fn loadedSource(self: *const LoaderType) ?LoadSource {
            if (!Config.ready().isReady()) return null;
            return self.request.source();
        }

        fn accept(self: *const LoaderType, source: LoadSource) LoadError!void {
            // Called only after an acquire-read of readiness.
            const published = self.request.source() orelse unreachable;
            if (eqlSource(published, source)) return;
            return error.ProviderMismatch;
        }

        /// Resolve and validate a candidate without publishing it; close failures.
        fn runAttempt(source: LoadSource) LoadError!void {
            const handle = platform.open(source) catch |err| return err;

            var retain = false;
            defer if (!retain) platform.close(handle);

            if (@hasDecl(Config, "optional_symbols")) {
                inline for (Config.optional_symbols, 0..) |_, index| {
                    Config.assignMissing(index, Config.tablePtr());
                }
            }

            inline for (Config.symbols, 0..) |symbol, index| {
                const address = platform.lookup(handle, symbol.name) orelse
                    return error.MissingSymbol;
                Config.assign(index, Config.tablePtr(), address);
            }

            if (@hasDecl(Config, "optional_symbols")) {
                inline for (Config.optional_symbols, 0..) |symbol, index| {
                    if (platform.lookup(handle, symbol.name)) |address| {
                        Config.assignOptional(index, Config.tablePtr(), address);
                    }
                }
            }

            if (@hasDecl(Config, "validate")) {
                if (Config.validate(Config.tablePtr())) |refusal| {
                    std.debug.print("{s}: refusing this provider: {s}\n", .{
                        Config.library_name,
                        refusal,
                    });
                    return error.ValidationFailed;
                }
            }

            // Retain the handle because published table entries point into it.
            retain = true;
        }
    };
}

// Platform-specific dynamic-loading backends.

/// State shared by callers waiting on one load attempt.
const Attempt = struct {
    /// Thread id used for reentrancy detection.
    owner: u64,
    /// Result published before readiness leaves `loading`.
    result: LoadError!void = error.OpenFailed,
    /// Keep the attempt until all attached callers have read its result.
    waiters: usize = 0,
};

/// Windows path buffer capacity, including the terminator.
const windows_path_units = 32768;

const platform = if (builtin.os.tag == .windows)
    Windows
else if (supported_target)
    Unix
else
    NoLoader;

/// Backend for targets without a dynamic loader.
const NoLoader = struct {
    const OpenError = error{ OpenFailed, UnsupportedTarget };

    fn open(source: LoadSource) OpenError!*anyopaque {
        _ = source;
        return error.UnsupportedTarget;
    }
    fn lookup(handle: *anyopaque, name: [:0]const u8) ?*const anyopaque {
        _ = handle;
        _ = name;
        return null;
    }
    fn close(handle: *anyopaque) void {
        _ = handle;
    }
};

/// Unix dynamic-loader backend.
const Unix = struct {
    const OpenError = error{ OpenFailed, UnsupportedTarget };

    fn open(source: LoadSource) OpenError!*anyopaque {
        const text = switch (source) {
            .path => |p| p,
            .system => |s| s,
        };
        var buffer: [max_source_len + 1]u8 = undefined;
        @memcpy(buffer[0..text.len], text);
        buffer[text.len] = 0;
        // NOW reports dependency failures at open; LOCAL avoids cross-library symbol lookup.
        return std.c.dlopen(
            // dlopen requires a NUL-terminated name.
            buffer[0..text.len :0].ptr,
            .{ .NOW = true, .GLOBAL = false },
        ) orelse error.OpenFailed;
    }

    fn lookup(handle: *anyopaque, name: [:0]const u8) ?*const anyopaque {
        return std.c.dlsym(handle, name.ptr);
    }

    fn close(handle: *anyopaque) void {
        _ = std.c.dlclose(handle);
    }
};

/// Windows dynamic-loader declarations.
const kernel32 = struct {
    extern "kernel32" fn LoadLibraryExW(
        file_name: [*:0]const u16,
        file: ?*anyopaque,
        flags: u32,
    ) callconv(.winapi) ?*anyopaque;
    extern "kernel32" fn GetProcAddress(module: *anyopaque, name: [*:0]const u8) callconv(.winapi) ?*anyopaque;
    extern "kernel32" fn FreeLibrary(module: *anyopaque) callconv(.winapi) i32;
};

/// Windows dynamic-loader backend.
const Windows = struct {
    const OpenError = error{ OpenFailed, UnsupportedTarget, SourceTooLong };

    /// Search standard directories without adding the current directory.
    const load_library_search_default_dirs: u32 = 0x0000_1000;
    const load_library_search_dll_load_dir: u32 = 0x0000_0100;

    fn open(source: LoadSource) OpenError!*anyopaque {
        const text = switch (source) {
            .path => |p| p,
            .system => |s| s,
        };
        if (text.len > windows_path_units) return error.SourceTooLong;
        var buffer: [windows_path_units + 1]u16 = undefined;
        const units = std.unicode.utf8ToUtf16Le(buffer[0..text.len], text) catch
            return error.OpenFailed;
        buffer[units] = 0;
        return kernel32.LoadLibraryExW(
            buffer[0..units :0],
            null,
            load_library_search_default_dirs | switch (source) {
                .path => load_library_search_dll_load_dir,
                .system => @as(u32, 0),
            },
        ) orelse error.OpenFailed;
    }

    fn lookup(handle: *anyopaque, name: [:0]const u8) ?*const anyopaque {
        return kernel32.GetProcAddress(handle, name.ptr);
    }

    fn close(handle: *anyopaque) void {
        _ = kernel32.FreeLibrary(handle);
    }
};
