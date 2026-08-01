//! PS/2 keyboard driver, scancode set 1 (QEMU default).
//!
//! On IRQ1 we read one scancode from port 0x60. Break codes (bit 7 set) are
//! ignored except for shift release. Make codes are mapped to ASCII via a
//! US-QWERTY table (shifted variant when shift is held) and pushed into the
//! shared input ring. Extended (0xE0) sequences are skipped.

const io = @import("io.zig");
const input = @import("input.zig");


