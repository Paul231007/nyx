//! heap — a kernel heap exposed as a `std.mem.Allocator`.
//!
//! Design: a first-fit, address-ordered, boundary-tag-ish free list over a
//! single contiguous virtual window. The window [HEAP_BASE, HEAP_BASE+SIZE) is
//! mapped up-front (one pmm frame per 4 KiB page) into high virtual space so it
//! never collides with the 0..64 MiB identity map. Every block is a header
//! immediately followed by its payload; blocks tile the window with no gaps, so
//! coalescing on free is just "merge with the physically-next/prev node".
//!
//! Alignment: `std.mem.Allocator` hands us a log2 alignment. We place the user
//! pointer at an aligned offset inside the chosen block's payload and stash a
//! back-pointer to the owning block in the `usize` slot immediately before it,
//! so `free(ptr)` can recover the header regardless of the alignment padding.

