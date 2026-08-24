//! ramfs — an in-memory filesystem backed by a fixed array of 64 entries.
//!
//! Paths are stored with a leading '/' (e.g. "/hello.txt", "/etc", "/etc/motd").
//! The root directory entry always lives at index 0 with path "/".

const std = @import("std");
const vfs = @import("vfs.zig");

const MAX_ENTRIES: usize = 64;
const MAX_DATA: usize = 4096;

const Entry = struct {
    used: bool = false,
    kind: vfs.Kind = .file,
    path: [128]u8 = undefined,
    path_len: usize = 0,
    data: [MAX_DATA]u8 = undefined,
    data_len: usize = 0,
    node: vfs.Node = .{},
};

var entries: [MAX_ENTRIES]Entry = [_]Entry{.{}} ** MAX_ENTRIES;

var fs_instance: vfs.FileSystem = .{
    .open = ramfsOpen,
    .read = ramfsRead,
    .write = ramfsWrite,
    .readdir = ramfsReaddir,
};

// ---- public API -----------------------------------------------------------

pub fn init(alloc: std.mem.Allocator) void {
    _ = alloc;
    // Reset all entries.
    for (&entries) |*e| {
        e.used = false;
        e.kind = .file;
        e.path_len = 0;
        e.data_len = 0;
        e.node = .{};
    }
    // Seed root directory at slot 0.
    const root = &entries[0];
    root.used = true;
    root.kind = .dir;
    root.path[0] = '/';
    root.path_len = 1;
    root.node.kind = .dir;
    root.node.name[0] = '/';
    root.node.name_len = 1;
    root.node.size = 0;
    root.node.impl = root;
}

pub fn fs() *vfs.FileSystem {
    return &fs_instance;
}

/// Create (or return existing) entry for `path` with the given `kind`.
/// Returns a pointer to the node on success, null if the table is full.
pub fn create(path: []const u8, kind: vfs.Kind) ?*vfs.Node {
    // Return existing entry if path is already present.
    for (&entries) |*e| {
        if (!e.used) continue;
        if (e.path_len != path.len) continue;
        if (std.mem.eql(u8, e.path[0..e.path_len], path)) return &e.node;
    }
    // Find a free slot.
    for (&entries) |*e| {
        if (e.used) continue;
        e.used = true;
        e.kind = kind;
        e.data_len = 0;
        e.node = .{};
        // Store the path.
        const plen = @min(path.len, 127);
        std.mem.copyForwards(u8, &e.path, path[0..plen]);
        e.path_len = plen;
        // Derive the basename for node.name.
        const stored_path = path[0..plen];
        const slash_pos = std.mem.lastIndexOfScalar(u8, stored_path, '/');
        const base: []const u8 = if (slash_pos) |s| stored_path[s + 1 ..] else stored_path;
        const nlen: u8 = @intCast(@min(base.len, 63));
        std.mem.copyForwards(u8, &e.node.name, base[0..nlen]);
        e.node.name_len = nlen;
        e.node.kind = kind;
        e.node.size = 0;
        e.node.impl = e;
        return &e.node;
    }
    return null; // table full
}

/// Remove the entry at `path`. Returns true if found and removed.
pub fn remove(path: []const u8) bool {
    for (&entries) |*e| {
        if (!e.used) continue;
        if (e.path_len != path.len) continue;
        if (std.mem.eql(u8, e.path[0..e.path_len], path)) {
            e.used = false;
            return true;
        }
    }
    return false;
}

// ---- vtable implementations -----------------------------------------------

fn entryFromNode(node: *vfs.Node) ?*Entry {
    const impl = node.impl orelse return null;
    return @ptrCast(@alignCast(impl));
}

fn ramfsOpen(path: []const u8) ?*vfs.Node {
    for (&entries) |*e| {
        if (!e.used) continue;
        if (e.path_len != path.len) continue;
        if (std.mem.eql(u8, e.path[0..e.path_len], path)) return &e.node;
    }
    return null;
}

fn ramfsRead(node: *vfs.Node, off: u32, buf: []u8) u32 {
    const e = entryFromNode(node) orelse return 0;
    if (off >= e.data_len) return 0;
    const avail = e.data_len - @as(usize, off);
    const n = @min(avail, buf.len);
    std.mem.copyForwards(u8, buf[0..n], e.data[off .. @as(usize, off) + n]);
    return @intCast(n);
}

