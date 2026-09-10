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

### fd table

The fd table is a fixed array of 16 `FdEntry` records:

```zig
const FdEntry = struct {
    in_use: bool,
    node: ?*Node,
    offset: u32,
};
```

`vfs.open(path)` calls `fs.open(path)` to get a `*Node`, then allocates the first
free `FdEntry` and returns its index as an `Fd`. If all 16 slots are occupied,
`open` returns `null`. `vfs.close(fd)` clears the slot.

### I/O operations

All I/O is offset-tracked through the fd table entry:

- `vfs.read(fd, buf)` — calls `fs.read(node, entry.offset, buf)`, advances the
  offset by the bytes returned.
- `vfs.write(fd, data)` — calls `fs.write(node, entry.offset, data)`, advances
  the offset, and updates `node.size` if the write extends the file.
- `vfs.seek(fd, off)` — sets `entry.offset = off` directly (no delegation to the
  backing fs).
- `vfs.readdir(fd, idx)` — calls `fs.readdir(node, idx)` to enumerate directory
  children by index. Returns `null` when `idx` is past the last child.

### Stub filesystem (M13 self-test)

`main.zig` defines a minimal in-memory stub (a single 128-byte `stub_buf` and a
single `stub_node`) wired to four static functions (`stubOpen`, `stubRead`,
`stubWrite`, `stubReaddir`). It is mounted via `vfs.mount(&stub_fs)` for the M13
round-trip test, then replaced by the RamFS in M14.

## ramfs.zig — In-memory filesystem

RamFS backs the VFS with a static array of 64 `Entry` records:

```zig
const Entry = struct {
    used: bool,
    kind: vfs.Kind,
    path: [128]u8,    // full absolute path, e.g. "/etc/motd"
    path_len: usize,
    data: [4096]u8,   // inline file data (4 KiB per file max)
    data_len: usize,
    node: vfs.Node,
};
```

Paths are stored with a leading `/`. The root directory is pre-seeded at `entries[0]`
by `ramfs.init()` with path `"/"` and `kind = .dir`.

### Creating and removing entries

`ramfs.create(path, kind)` first scans for an existing entry with the same path
(idempotent). If not found, it finds a free slot, fills in the path, derives the
basename for `node.name`, sets `node.impl = e` (the entry's own address), and
returns `&e.node`. Returns `null` when the 64-entry table is full.

`ramfs.remove(path)` scans for a matching entry and marks `e.used = false`. The
slot is immediately available for reuse. No directory emptiness check is performed.

### vtable implementations

`ramfsOpen(path)` scans `entries` for a matching path and returns `&e.node`.

`ramfsRead(node, off, buf)` recovers the `Entry` from `node.impl` and copies bytes
from `e.data[off..]` into `buf`. Returns 0 if `off >= e.data_len`.

`ramfsWrite(node, off, data)` copies `data` into `e.data[off..]`. Truncates to 4096
bytes if the write would overflow. Updates `e.data_len` and `node.size`.

`ramfsReaddir(dir, idx)` implements index-based enumeration: it scans all entries,
counts those that are direct children of `dir`'s path (via `isDirectChild`), and
returns the `idx`-th one. `isDirectChild` checks that the candidate path starts with
the directory path and has no additional `/` separator after the prefix.

The `fs()` function returns a pointer to the module-level `fs_instance` vtable, which
is what callers pass to `vfs.mount()`.

## tar.zig — ustar initrd

`tar.unpackInto(image, into)` parses a raw ustar archive (as embedded by
`@embedFile("initrd.tar")`) and creates entries in the target filesystem.

### Header format

Each archive member starts with a 512-byte header:

| Offset | Size | Field |
|--------|------|-------|
| 0 | 100 | name (NUL-terminated) |
| 124 | 12 | file size (octal ASCII, NUL/space terminated) |
| 156 | 1 | typeflag: `'0'`/`0` = file, `'5'` = directory |

Data blocks follow the header, padded to a multiple of 512. The archive ends with
two consecutive all-zero 512-byte blocks.

### Parsing logic

`parseOctal(s)` converts the size field's octal ASCII string to a `usize`.

`normalizePath(name, buf)` strips a `./` prefix and trailing `/` from the tar name
and prepends `/`, producing a canonical VFS path.

