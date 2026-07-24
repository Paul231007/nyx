//! slab — fixed-size-object slab allocator built on top of the kernel heap.
//!
//! Design: backing memory is carved from a `std.mem.Allocator` in chunks that
//! each hold `slab_objs` equally-sized object slots.  Free slots are threaded
//! into a singly-linked free list (the link word is written into the first
//! `@sizeOf(usize)` bytes of every free slot).  `alloc` pops from the list in
//! O(1); `free` pushes in O(1).  When the list is empty, `grow` allocates a
//! fresh chunk from the backing allocator and adds all its slots to the list.
//!
//! A `ChunkHdr` is stored at the very start of each backing allocation so that
//! `deinit` can walk the chain and release every chunk.


