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

const std = @import("std");
const pmm = @import("pmm.zig");
const paging = @import("paging.zig");

pub const HEAP_BASE: usize = 0xD0000000;
pub const HEAP_SIZE: usize = 4 * 1024 * 1024; // 4 MiB = 1024 frames
const PAGE_SIZE: usize = 4096;

const Block = struct {
    size: usize, // payload bytes following this header
    free: bool,
    next: ?*Block,
    prev: ?*Block,
};

const MIN_PAYLOAD: usize = 16;

var head: ?*Block = null;
var initialized: bool = false;

/// Map the whole heap window and seed it with one big free block.
pub fn init() void {
    var virt: usize = HEAP_BASE;
    while (virt < HEAP_BASE + HEAP_SIZE) : (virt += PAGE_SIZE) {
        const f = pmm.allocFrame().?;
        paging.map(virt, f, 0x3); // present + rw
    }

    const b: *Block = @ptrFromInt(HEAP_BASE);
    b.* = .{
        .size = HEAP_SIZE - @sizeOf(Block),
        .free = true,
        .next = null,
        .prev = null,
    };
    head = b;
    initialized = true;
}

inline fn payloadStart(b: *Block) usize {
    return @intFromPtr(b) + @sizeOf(Block);
}

/// First-fit allocation honoring `alignment` (in bytes). Returns the user
/// pointer or null. Splits the tail of the chosen block into a new free block
/// when the leftover is large enough.
fn heapAlloc(len: usize, alignment: usize) ?[*]u8 {
    if (!initialized) return null;
    const a = if (alignment == 0) 1 else alignment;

    var it = head;
    while (it) |b| : (it = b.next) {
        if (!b.free) continue;
        const ps = payloadStart(b);
        const payload_end = ps + b.size;
        // Reserve a usize back-pointer slot before the (aligned) user pointer.
        const user = std.mem.alignForward(usize, ps + @sizeOf(usize), a);
        const used_end = user + len;
        if (used_end > payload_end) continue; // doesn't fit

        // Try to carve the tail into a fresh free block.
        const split = std.mem.alignForward(usize, used_end, @alignOf(Block));
        if (split + @sizeOf(Block) + MIN_PAYLOAD <= payload_end) {
            const nb: *Block = @ptrFromInt(split);
            nb.* = .{
                .size = payload_end - split - @sizeOf(Block),
                .free = true,
                .next = b.next,
                .prev = b,
            };
            if (b.next) |n| n.prev = nb;
            b.next = nb;
            b.size = split - ps;
        }

        b.free = false;
        // Stash the owning header just before the user pointer.
        const backptr: *usize = @ptrFromInt(user - @sizeOf(usize));
        backptr.* = @intFromPtr(b);
        return @ptrFromInt(user);
    }
    return null;
}

fn heapFree(ptr: [*]u8) void {
    const user = @intFromPtr(ptr);
    const backptr: *usize = @ptrFromInt(user - @sizeOf(usize));
    const b: *Block = @ptrFromInt(backptr.*);
    b.free = true;

