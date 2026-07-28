//! pmm — physical memory manager. Parses the multiboot1 memory map and hands
//! out 4 KiB physical frames via a static bitmap (1 = used, 0 = free).

const std = @import("std");

pub const FRAME_SIZE: usize = 4096;

// Cover a full 4 GiB physical address space: 4 GiB / 4 KiB = 1,048,576 frames,
// one bit each => 131072 bytes. Lives in .bss (zero-initialised) — but init()
// sets everything USED first, so the initial zeroing is irrelevant.
const MAX_FRAMES: usize = 1 << 20; // 1,048,576
const BITMAP_BYTES: usize = MAX_FRAMES / 8; // 131072

var bitmap: [BITMAP_BYTES]u8 = undefined;

var total_frames: usize = 0; // usable frames discovered from the mmap
var used_frames: usize = 0; // currently used (incl. reserved kernel/etc.)
var highest_frame: usize = 0; // highest frame index touched (for bounds)

// Multiboot mmap entry. `size` does NOT count itself: stride is size + 4.
const Entry = extern struct {
    size: u32,
    base_addr: u64,
    length: u64,
    type: u32,
};

inline fn bitSet(idx: usize) void {
    bitmap[idx >> 3] |= (@as(u8, 1) << @intCast(idx & 7));
}
inline fn bitClear(idx: usize) void {
    bitmap[idx >> 3] &= ~(@as(u8, 1) << @intCast(idx & 7));
}
inline fn bitGet(idx: usize) bool {
    return (bitmap[idx >> 3] & (@as(u8, 1) << @intCast(idx & 7))) != 0;
}

fn markUsed(idx: usize) void {
    if (idx >= MAX_FRAMES) return;
    if (!bitGet(idx)) {
        bitSet(idx);
        used_frames += 1;
    }
}

