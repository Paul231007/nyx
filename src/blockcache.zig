//! Simple write-through block cache over the ATA PIO driver.
//!
//! 16 direct-mapped slots keyed by (lba % 16). Each slot holds one 512-byte
//! sector. Write-through means every write goes immediately to disk so the
//! cache and disk are always consistent; flush() is a no-op.

const std = @import("std");
const ata = @import("ata.zig");

const NUM_SLOTS: usize = 16;

const Slot = struct {
    lba:   u32,
    valid: bool,
    data:  *[ata.SECTOR]u8,
};

var slots: [NUM_SLOTS]Slot = undefined;
var bc_alloc: std.mem.Allocator = undefined;

/// Allocate backing buffers from `alloc`. Must be called after heap.init().
pub fn init(alloc: std.mem.Allocator) void {
    bc_alloc = alloc;
    for (&slots) |*sl| {
        const raw = alloc.alloc(u8, ata.SECTOR) catch unreachable;
        sl.data  = raw[0..ata.SECTOR];
        sl.valid = false;
        sl.lba   = 0;
    }
}

/// Return a pointer to the cached sector for `lba`, loading from disk on miss.
pub fn read(lba: u32) *[ata.SECTOR]u8 {
    const idx = lba % NUM_SLOTS;
    const sl = &slots[idx];
    if (sl.valid and sl.lba == lba) return sl.data;
    // cache miss — load from disk
    _ = ata.readSectors(lba, 1, sl.data);
    sl.lba   = lba;
    sl.valid = true;
    return sl.data;
}

/// Write `data` to disk immediately (write-through) and update the cache slot.
pub fn write(lba: u32, data: *const [ata.SECTOR]u8) void {
    _ = ata.writeSectors(lba, 1, data);
    const idx = lba % NUM_SLOTS;
    const sl = &slots[idx];
    @memcpy(sl.data, data);
    sl.lba   = lba;
    sl.valid = true;
}

