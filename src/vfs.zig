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

/// An integer file descriptor; indices into the fd table.
pub const Fd = u8;

// ---- internal state -------------------------------------------------------

const MAX_FDS: usize = 16;

const FdEntry = struct {
    in_use: bool = false,
    node: ?*Node = null,
    offset: u32 = 0,
};

var mounted_fs: ?*FileSystem = null;
var fd_table: [MAX_FDS]FdEntry = [_]FdEntry{.{}} ** MAX_FDS;

// ---- public API -----------------------------------------------------------

/// Register a filesystem as the single (flat) mount point.
pub fn mount(fs: *FileSystem) void {
    mounted_fs = fs;
}

/// Open a path through the mounted filesystem and return a new file descriptor,
/// or null if no filesystem is mounted, the path doesn't exist, or all fd
/// slots are occupied.
pub fn open(path: []const u8) ?Fd {
    const fs = mounted_fs orelse return null;
    const node = fs.open(path) orelse return null;
    for (&fd_table, 0..) |*entry, idx| {
        if (!entry.in_use) {
            entry.in_use = true;
            entry.node = node;
            entry.offset = 0;
            return @intCast(idx);
        }
    }
    return null; // no free slot
}

/// Read up to `buf.len` bytes from `fd` starting at the current offset.
/// Returns the number of bytes actually read and advances the offset by that amount.
pub fn read(fd: Fd, buf: []u8) u32 {
    const fs = mounted_fs orelse return 0;
    if (fd >= MAX_FDS) return 0;
    const entry = &fd_table[fd];
    if (!entry.in_use) return 0;
    const node = entry.node orelse return 0;
    const n = fs.read(node, entry.offset, buf);
    entry.offset += n;
    return n;
}

/// Write `data` to `fd` at the current offset.
/// Returns the number of bytes written, advances the offset, and updates
/// `node.size` if the write extends past the previous end of file.
pub fn write(fd: Fd, data: []const u8) u32 {
    const fs = mounted_fs orelse return 0;
    if (fd >= MAX_FDS) return 0;
    const entry = &fd_table[fd];
    if (!entry.in_use) return 0;
    const node = entry.node orelse return 0;
    const n = fs.write(node, entry.offset, data);
    entry.offset += n;
    if (entry.offset > node.size) node.size = entry.offset;
    return n;
}

/// Seek `fd` to an absolute byte offset.
pub fn seek(fd: Fd, off: u32) void {
    if (fd >= MAX_FDS) return;
    const entry = &fd_table[fd];
    if (!entry.in_use) return;
    entry.offset = off;
}

/// Return the idx-th child node of the directory opened as `fd`, or null when
/// the index is past the last entry. Used by the shell `ls` command.
pub fn readdir(fd: Fd, idx: usize) ?*Node {
    const fs = mounted_fs orelse return null;
    if (fd >= MAX_FDS) return null;
    const entry = &fd_table[fd];
    if (!entry.in_use) return null;
    const node = entry.node orelse return null;
    return fs.readdir(node, idx);
}

/// Release the fd slot so it can be reused.
pub fn close(fd: Fd) void {
    if (fd >= MAX_FDS) return;
    fd_table[fd].in_use = false;
    fd_table[fd].node = null;
    fd_table[fd].offset = 0;
}
