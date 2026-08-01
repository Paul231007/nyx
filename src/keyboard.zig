//! PS/2 keyboard driver, scancode set 1 (QEMU default).
//!
//! On IRQ1 we read one scancode from port 0x60. Break codes (bit 7 set) are
//! ignored except for shift release. Make codes are mapped to ASCII via a
//! US-QWERTY table (shifted variant when shift is held) and pushed into the
//! shared input ring. Extended (0xE0) sequences are skipped.

const io = @import("io.zig");
const input = @import("input.zig");

const DATA_PORT: u16 = 0x60;

// Make codes
const SC_LSHIFT: u8 = 0x2A;
const SC_RSHIFT: u8 = 0x36;
const SC_CAPSLOCK: u8 = 0x3A;
const SC_LCTRL: u8 = 0x1D;
const SC_LALT: u8 = 0x38;
const SC_EXTENDED: u8 = 0xE0;
const SC_F1: u8 = 0x3B;
const SC_F2: u8 = 0x3C;
const SC_F3: u8 = 0x3D;
const SC_F4: u8 = 0x3E;
const SC_F5: u8 = 0x3F;
const SC_F6: u8 = 0x40;
const SC_F7: u8 = 0x41;
const SC_F8: u8 = 0x42;
const SC_F9: u8 = 0x43;
const SC_F10: u8 = 0x44;
const SC_F11: u8 = 0x57;
const SC_F12: u8 = 0x58;
const SC_HOME: u8 = 0x47;
const SC_UP: u8 = 0x48;
const SC_PGUP: u8 = 0x49;
const SC_LEFT: u8 = 0x4B;
const SC_RIGHT: u8 = 0x4D;
const SC_END: u8 = 0x4F;
const SC_DOWN: u8 = 0x50;
const SC_PGDN: u8 = 0x51;
const SC_INS: u8 = 0x52;
const SC_DEL: u8 = 0x53;

