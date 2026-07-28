//! pmm — physical memory manager. Parses the multiboot1 memory map and hands
//! out 4 KiB physical frames via a static bitmap (1 = used, 0 = free).

const std = @import("std");

pub const FRAME_SIZE: usize = 4096;


