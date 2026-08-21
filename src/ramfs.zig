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

