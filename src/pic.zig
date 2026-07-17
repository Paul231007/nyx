//! 8259 PIC remap + mask helpers.
//! After remap, master IRQs 0..7 land on vectors 0x20..0x27 and slave IRQs
//! 8..15 on 0x28..0x2F, so they no longer collide with CPU exceptions.

const io = @import("io.zig");

