# Filesystem subsystem

nyx has a three-layer filesystem stack: a generic VFS abstraction, a concrete
in-memory RamFS implementation, and a ustar tar parser that populates RamFS from
an embedded initrd image.

## vfs.zig — Virtual file system

The VFS provides a stable, filesystem-agnostic API to callers (the shell, syscalls,
and the M13/M14 self-tests). Concrete filesystems register by calling `vfs.mount()`
with a pointer to a `FileSystem` vtable. Only one filesystem can be mounted at a
time; re-mounting replaces the previous one.

### Types

```zig
pub const Kind = enum { file, dir };

pub const Node = struct {
    name: [64]u8,
    name_len: u8,
    kind: Kind,
    size: u32,
    impl: ?*anyopaque,   // opaque pointer owned by the backing fs
};

pub const FileSystem = struct {
    open:    *const fn (path: []const u8) ?*Node,
    read:    *const fn (node: *Node, off: u32, buf: []u8) u32,
    write:   *const fn (node: *Node, off: u32, data: []const u8) u32,
    readdir: *const fn (dir: *Node, idx: usize) ?*Node,
};

pub const Fd = u8;   // index into the fd table
```

The `impl` pointer is set by the backing filesystem (e.g. `ramfs.zig` sets it to
the address of its internal `Entry` struct) and is cast back inside the vtable
implementation. Generic VFS code never dereferences `impl`.

