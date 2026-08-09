//! ATA PIO disk driver — primary bus (0x1F0), master drive, 28-bit LBA, polling.

const io = @import("io.zig");

pub const SECTOR: usize = 512;

const BASE: u16 = 0x1F0;

// Register offsets from BASE
const REG_DATA: u16    = 0;
const REG_FEAT: u16    = 1; // features (write) / error (read)
const REG_COUNT: u16   = 2;
const REG_LBA_LO: u16  = 3;
const REG_LBA_MID: u16 = 4;
const REG_LBA_HI: u16  = 5;
const REG_DRIVE: u16   = 6; // drive/head select
const REG_CMD: u16     = 7; // command (write) / status (read)

const STATUS_BSY: u8 = 0x80;
const STATUS_DRQ: u8 = 0x08;
const STATUS_ERR: u8 = 0x01;

pub const Info = struct {
    sectors: u32,
    model: [40]u8,
};

/// Poll: wait while BSY set, then until DRQ set. Returns false if missing or error.
fn pollDRQ() bool {
    var tries: u32 = 0;
    while (tries < 200_000) : (tries += 1) {
        const st = io.inb(BASE + REG_CMD);
        if (st == 0x00 or st == 0xFF) return false;
        if (st & STATUS_ERR != 0) return false;
        if (st & STATUS_BSY != 0) continue;
        if (st & STATUS_DRQ != 0) return true;
    }
    return false;
}

/// Poll: wait while BSY set. Returns false on timeout or drive error.
fn pollReady() bool {
    var tries: u32 = 0;
    while (tries < 200_000) : (tries += 1) {
        const st = io.inb(BASE + REG_CMD);
        if (st == 0x00 or st == 0xFF) return false;
        if (st & STATUS_ERR != 0) return false;
        if (st & STATUS_BSY == 0) return true;
    }
    return false;
}

/// Send IDENTIFY (0xEC) to master; poll BSY/DRQ; read 256 words.
/// Sectors from words 60-61; model from words 27-46 (byte-swapped).
/// Returns null if no drive (status 0 or 0xFF).
pub fn identify() ?Info {
    // Select master drive, LBA mode, no drive bit in address
    io.outb(BASE + REG_DRIVE, 0xA0);
    // Zero out LBA/count registers
    io.outb(BASE + REG_COUNT, 0);
    io.outb(BASE + REG_LBA_LO, 0);
    io.outb(BASE + REG_LBA_MID, 0);
    io.outb(BASE + REG_LBA_HI, 0);
    // Send IDENTIFY command
    io.outb(BASE + REG_CMD, 0xEC);

    // Check immediately if a drive exists
    const st0 = io.inb(BASE + REG_CMD);
    if (st0 == 0x00 or st0 == 0xFF) return null;

