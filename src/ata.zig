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


