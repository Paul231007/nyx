//! 8259 PIC remap + mask helpers.
//! After remap, master IRQs 0..7 land on vectors 0x20..0x27 and slave IRQs
//! 8..15 on 0x28..0x2F, so they no longer collide with CPU exceptions.

const io = @import("io.zig");

const MASTER_CMD: u16 = 0x20;
const MASTER_DATA: u16 = 0x21;
const SLAVE_CMD: u16 = 0xA0;
const SLAVE_DATA: u16 = 0xA1;

const EOI: u8 = 0x20;

/// Remap the PIC vector bases to 0x20 (master) / 0x28 (slave) and mask all
/// lines except the timer (IRQ0).
pub fn init() void {
    // ICW1: start init sequence, expect ICW4.
    io.outb(MASTER_CMD, 0x11);
    io.ioWait();
    io.outb(SLAVE_CMD, 0x11);
    io.ioWait();

