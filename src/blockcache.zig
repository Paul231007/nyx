//! Simple write-through block cache over the ATA PIO driver.
//!
//! 16 direct-mapped slots keyed by (lba % 16). Each slot holds one 512-byte
//! sector. Write-through means every write goes immediately to disk so the
//! cache and disk are always consistent; flush() is a no-op.

const std = @import("std");
const ata = @import("ata.zig");

const NUM_SLOTS: usize = 16;

