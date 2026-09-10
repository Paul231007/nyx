# Memory subsystem

nyx has four cooperating memory components: the physical frame allocator (PMM),
the paging layer, the kernel heap, and the block cache. They are initialised in
this order during boot and each depends on the ones before it.

## pmm.zig — Physical frame allocator

The PMM tracks every 4 KiB physical frame in a statically-allocated 128 KiB bitmap
(`var bitmap: [BITMAP_BYTES]u8`). One bit per frame; bit set means used/reserved,
bit clear means free. The bitmap covers the full 32-bit address space (1,048,576
frames × 1 bit = 128 KiB).

