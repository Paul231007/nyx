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

`allocFrame()` scans the bitmap from index 0 up to `highest_frame` for the first
clear bit, sets it, and returns the physical address (`idx * 4096`). On failure it
returns `null`. `freeFrame(addr)` clears the bit for `addr / 4096`. A double-free
guard (`if (!bitGet(idx)) return`) prevents double-counting.

`stats()` returns `{ total, used, free }` where `free` is computed by counting
clear bits up to `highest_frame`. This is an O(frames) walk and is only called for
the `mem` shell command and diagnostic prints, never in hot paths.

### Utility

```zig
pub fn allocFrame() ?usize        // returns physical address or null
pub fn freeFrame(addr: usize) void
pub const Stats = struct { total: usize, used: usize, free: usize };
pub fn stats() Stats
```

## paging.zig — 32-bit x86 paging

`paging.zig` implements non-PAE 32-bit paging: a 1024-entry page directory, each
entry pointing to a 1024-entry page table covering 4 MiB. Each page table entry
covers a 4 KiB physical frame.

### Identity map (`paging.init`)

`init()` allocates one PMM frame for the page directory and 16 frames for page
tables (one per 4 MiB, covering the first 64 MiB). Every page table entry is set
to `phys_addr | PRESENT | RW`, making virtual == physical for all addresses below
64 MiB. The directory is loaded into CR3 and CR0 bit 31 (`PG`) is set via inline
assembly. After `init()` returns, paging is active and all existing kernel pointers
remain valid because of the identity map.

### Arbitrary mappings (`paging.map`)

```zig
pub fn map(virt: usize, phys: usize, flags: u32) void
```

`map()` installs a single 4 KiB mapping. It looks up the page directory entry
for `virt >> 22`; if no page table exists it allocates one from the PMM and
zeroes it. It then writes the PTE at `(virt >> 12) & 0x3FF` and issues `invlpg`
to flush the TLB entry.

The heap uses `map()` to wire 1024 PMM frames into the virtual window
`[0xD0000000, 0xD0400000)`. The M6 self-test uses it to map a single frame at
`0xE0000000` and verify a sentinel read-back.

### Page-walk (`paging.translate`)

```zig
pub fn translate(virt: usize) ?usize
```

Walks the directory and table to return the physical frame base for a virtual
address, or `null` if not mapped. Used by the M6 diagnostic and available to
future subsystems.

## heap.zig — Kernel heap

The heap lives in `[HEAP_BASE, HEAP_BASE + HEAP_SIZE)` = `[0xD0000000, 0xD0400000)`
(4 MiB). It is a first-fit, address-ordered, doubly-linked free list.

### Block layout

Every allocation region is described by a `Block` header immediately preceding the
payload:

```zig
const Block = struct {
    size: usize,   // payload bytes available after this header
    free: bool,
    next: ?*Block,
    prev: ?*Block,
};
```

Blocks tile the heap window with no gaps. On free, a block is coalesced with its
physically-adjacent neighbours by merging the `size` fields and relinking the list.

### Alignment

`heapAlloc(len, alignment)` computes the aligned user pointer by stepping forward
from `payloadStart(b)` to satisfy the alignment constraint. It stores the owning
header address in the `usize` slot immediately before the user pointer (the
"back-pointer trick"). `heapFree(ptr)` recovers the header by reading
`ptr[-sizeof(usize)]`.

Split happens when the tail of the chosen block is large enough to hold a new
`Block` header plus `MIN_PAYLOAD` (16) bytes. This keeps small allocations from
permanently fragmenting large regions.

### std.mem.Allocator

`heap.allocator()` returns a `std.mem.Allocator` backed by the vtable
`{ alloc, resize, remap, free }`. `resize` allows shrink-in-place; `remap` returns
`null` for growth (signalling the caller to alloc + copy + free). This is the
allocator used by `std.ArrayList` in the M7 self-test and by the scheduler and
block cache.

```zig
pub const HEAP_BASE: usize = 0xD0000000;
pub const HEAP_SIZE: usize = 4 * 1024 * 1024;
pub fn init() void
pub fn allocator() std.mem.Allocator
pub fn kmalloc(n: usize) ?[*]u8    // convenience wrapper
pub fn kfree(ptr: [*]u8) void
```

## blockcache.zig — Write-through block cache

