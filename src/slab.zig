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

const std = @import("std");

/// Header embedded at the start of every backing chunk so we can walk them on
/// deinit.  The chunk is allocated with extra headroom so the objects that
/// follow the header can be aligned to `obj_align`.
const ChunkHdr = struct {
    next_chunk: ?[*]u8, // intrusive linked list of all live chunks
    total_bytes: usize, // full allocation size (for freeing)
};

pub const Slab = struct {
    backing: std.mem.Allocator,
    /// Requested object size (may be rounded up internally).
    obj_size: usize,
    /// Required alignment for every returned object pointer (bytes).
    obj_align: usize,
    /// Number of object slots per backing chunk.
    slab_objs: usize,
    /// Head of the free-slot list (null ⟹ no free slot yet).
    free_list: ?[*]u8,
    /// Head of the backing-chunk chain (for deinit).
    chunk_list: ?[*]u8,
    /// Number of slots currently handed to callers.
    live: usize,
    /// Total slots ever made available (grows with each `grow` call).
    capacity: usize,

