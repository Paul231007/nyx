# Memory subsystem

nyx has four cooperating memory components: the physical frame allocator (PMM),
the paging layer, the kernel heap, and the block cache. They are initialised in
this order during boot and each depends on the ones before it.

## pmm.zig — Physical frame allocator

The PMM tracks every 4 KiB physical frame in a statically-allocated 128 KiB bitmap
(`var bitmap: [BITMAP_BYTES]u8`). One bit per frame; bit set means used/reserved,
bit clear means free. The bitmap covers the full 32-bit address space (1,048,576
frames × 1 bit = 128 KiB).

### Initialisation (`pmm.init`)

1. All bits are set to 1 (every frame marked used).
2. The multiboot1 memory map is walked. Each entry with `type == 1` (available RAM)
   has its frames cleared (marked free) and counted into `total_frames`.
3. Three ranges are re-reserved so they are never handed out:
   - The first 1 MiB (BIOS, IVT, VGA buffer at `0xB8000`).
   - The kernel ELF image, bounded by the linker-exported `kernel_start` and
     `kernel_end` symbols.
   - The multiboot info struct and its mmap buffer.

The `reserveAndCount` helper both sets the bits and decrements `total_frames` so
the `stats().free` count is always accurate relative to truly usable frames.

### Allocation and deallocation

