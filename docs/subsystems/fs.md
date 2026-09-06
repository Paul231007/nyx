# Filesystem subsystem

nyx has a three-layer filesystem stack: a generic VFS abstraction, a concrete
in-memory RamFS implementation, and a ustar tar parser that populates RamFS from
an embedded initrd image.

