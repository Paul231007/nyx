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

    if (!pollDRQ()) return null;

    var words: [256]u16 = undefined;
    for (&words) |*wrd| {
        wrd.* = io.inw(BASE + REG_DATA);
    }

    var info: Info = undefined;
    // 28-bit LBA sector count: word 60 (lo) and word 61 (hi)
    info.sectors = @as(u32, words[60]) | (@as(u32, words[61]) << 16);

    // Model string occupies words 27..46 (20 words = 40 bytes), byte-swapped
    var moff: usize = 0;
    for (words[27..47]) |mw| {
        info.model[moff]     = @truncate(mw >> 8);
        info.model[moff + 1] = @truncate(mw & 0xFF);
        moff += 2;
    }

    return info;
}

/// READ SECTORS (0x20): polling PIO, reads `count` sectors at `lba` into `buf`.
pub fn readSectors(lba: u32, count: u8, buf: []u8) bool {
    if (buf.len < @as(usize, count) * SECTOR) return false;

    io.outb(BASE + REG_DRIVE, 0xE0 | @as(u8, @truncate((lba >> 24) & 0xF)));
    io.outb(BASE + REG_COUNT, count);
    io.outb(BASE + REG_LBA_LO,  @truncate(lba & 0xFF));
    io.outb(BASE + REG_LBA_MID, @truncate((lba >> 8) & 0xFF));
    io.outb(BASE + REG_LBA_HI,  @truncate((lba >> 16) & 0xFF));
    io.outb(BASE + REG_CMD, 0x20); // READ SECTORS

    var sec: usize = 0;
    while (sec < count) : (sec += 1) {
        if (!pollDRQ()) return false;
        const boff = sec * SECTOR;
        var wi: usize = 0;
        while (wi < 256) : (wi += 1) {
            const wval = io.inw(BASE + REG_DATA);
            buf[boff + wi * 2]     = @truncate(wval & 0xFF);
            buf[boff + wi * 2 + 1] = @truncate(wval >> 8);
        }
    }
    return true;
}

/// WRITE SECTORS (0x30): polling PIO, writes `count` sectors at `lba` from `buf`.
/// Follows with CACHE FLUSH (0xE7).
pub fn writeSectors(lba: u32, count: u8, buf: []const u8) bool {
    if (buf.len < @as(usize, count) * SECTOR) return false;

    io.outb(BASE + REG_DRIVE, 0xE0 | @as(u8, @truncate((lba >> 24) & 0xF)));
    io.outb(BASE + REG_COUNT, count);
    io.outb(BASE + REG_LBA_LO,  @truncate(lba & 0xFF));
    io.outb(BASE + REG_LBA_MID, @truncate((lba >> 8) & 0xFF));
    io.outb(BASE + REG_LBA_HI,  @truncate((lba >> 16) & 0xFF));
    io.outb(BASE + REG_CMD, 0x30); // WRITE SECTORS

    var sec: usize = 0;
    while (sec < count) : (sec += 1) {
        if (!pollDRQ()) return false;
        const boff = sec * SECTOR;
        var wi: usize = 0;
        while (wi < 256) : (wi += 1) {
            const lo: u16 = buf[boff + wi * 2];
            const hi: u16 = buf[boff + wi * 2 + 1];
            io.outw(BASE + REG_DATA, lo | (hi << 8));
        }
    }
    // Wait for BSY to clear after the last transfer before flushing
    _ = pollReady();
    // CACHE FLUSH — force the drive to commit write buffers to media
    io.outb(BASE + REG_CMD, 0xE7);
    _ = pollReady();
    return true;
}
