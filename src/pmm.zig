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

