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

