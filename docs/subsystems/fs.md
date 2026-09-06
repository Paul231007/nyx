# Filesystem subsystem

nyx has a three-layer filesystem stack: a generic VFS abstraction, a concrete
in-memory RamFS implementation, and a ustar tar parser that populates RamFS from
an embedded initrd image.

## vfs.zig — Virtual file system

The VFS provides a stable, filesystem-agnostic API to callers (the shell, syscalls,
and the M13/M14 self-tests). Concrete filesystems register by calling `vfs.mount()`
with a pointer to a `FileSystem` vtable. Only one filesystem can be mounted at a
time; re-mounting replaces the previous one.

