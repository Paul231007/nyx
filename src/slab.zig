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

    /// Initialise a Slab.  No heap allocation is made here; the first `alloc`
    /// triggers the initial `grow`.
    pub fn init(backing_alloc: std.mem.Allocator, obj_size: usize, obj_align: usize, slab_objs: usize) Slab {
        // Each slot must be large enough to hold the free-list link word.
        const eff_align = @max(obj_align, @alignOf(usize));
        const eff_size = std.mem.alignForward(usize, @max(obj_size, @sizeOf(usize)), eff_align);
        return .{
            .backing = backing_alloc,
            .obj_size = eff_size,
            .obj_align = eff_align,
            .slab_objs = slab_objs,
            .free_list = null,
            .chunk_list = null,
            .live = 0,
            .capacity = 0,
        };
    }

    /// Allocate a fresh backing chunk and thread all its slots into the free
    /// list.  Returns `false` if the backing allocator is exhausted.
    fn grow(self: *Slab) bool {
        // Header lives at the front of the raw allocation.  Pad it up to
        // `obj_align` so the first object that follows is properly aligned.
        const hdr_bytes = std.mem.alignForward(usize, @sizeOf(ChunkHdr), self.obj_align);
        // Over-allocate by `obj_align` so we can round up the base address of
        // the object region even if the backing allocator returns an address
        // that is only @alignOf(usize)-aligned (4 bytes on i386).
        const payload_bytes = self.obj_size * self.slab_objs;
        const total = hdr_bytes + payload_bytes + self.obj_align;

        const raw_slice = self.backing.alloc(u8, total) catch return false;
        const raw = raw_slice.ptr;

        // Write the chunk header.
        const hdr: *ChunkHdr = @ptrCast(@alignCast(raw));
        hdr.next_chunk = self.chunk_list;
        hdr.total_bytes = total;
        self.chunk_list = raw;

        // Align the start of the object region to `obj_align`.
        const objs_base = std.mem.alignForward(usize, @intFromPtr(raw) + hdr_bytes, self.obj_align);

        // Thread objects into the free list in forward order (LIFO push).
        var ii: usize = 0;
        while (ii < self.slab_objs) : (ii += 1) {
            const obj: [*]u8 = @ptrFromInt(objs_base + ii * self.obj_size);
            const link: *?[*]u8 = @ptrCast(@alignCast(obj));
            link.* = self.free_list;
            self.free_list = obj;
        }
        self.capacity += self.slab_objs;
        return true;
    }

    /// Return a pointer to an uninitialised object slot, or null if the backing
    /// allocator cannot satisfy a `grow` request.  O(1) when a free slot exists.
    pub fn alloc(self: *Slab) ?[*]u8 {
        if (self.free_list == null) {
            if (!self.grow()) return null;
        }
        const ptr = self.free_list.?;
        // Pop the head of the free list.
        const link: *?[*]u8 = @ptrCast(@alignCast(ptr));
        self.free_list = link.*;
        self.live += 1;
        return ptr;
    }

