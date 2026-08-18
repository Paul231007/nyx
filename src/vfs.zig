//! VFS — a filesystem-agnostic virtual file system layer.
//!
//! Any concrete filesystem registers itself via `mount`. Callers interact with
//! files through integer file descriptors (Fd). The implementation keeps a
//! fixed-size fd table (16 slots); each slot tracks the open Node and the
//! current read/write offset.

/// Whether a node represents a regular file or a directory.
pub const Kind = enum { file, dir };

/// An abstract file-system node. The `impl` pointer is private to the backing
/// filesystem and must not be accessed by generic VFS code.
pub const Node = struct {
    name: [64]u8 = undefined,
    name_len: u8 = 0,
    kind: Kind = .file,
    size: u32 = 0,
    impl: ?*anyopaque = null, // backing-fs private pointer
};

/// Vtable that every concrete filesystem must fill in.
pub const FileSystem = struct {
    open: *const fn (path: []const u8) ?*Node,
    read: *const fn (node: *Node, off: u32, buf: []u8) u32,
    write: *const fn (node: *Node, off: u32, data: []const u8) u32,
    readdir: *const fn (dir: *Node, idx: usize) ?*Node,
};

// / An integer ...
pub const Fd = u8;

