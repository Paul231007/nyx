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

    // ICW2: vector base offsets.
    io.outb(MASTER_DATA, 0x20);
    io.ioWait();
    io.outb(SLAVE_DATA, 0x28);
    io.ioWait();

    // ICW3: master has a slave on IRQ2; slave cascade identity = 2.
    io.outb(MASTER_DATA, 0x04);
    io.ioWait();
    io.outb(SLAVE_DATA, 0x02);
    io.ioWait();

    // ICW4: 8086/88 mode.
    io.outb(MASTER_DATA, 0x01);
    io.ioWait();
    io.outb(SLAVE_DATA, 0x01);
    io.ioWait();

    // Mask everything, then enable only the timer (IRQ0).
    io.outb(MASTER_DATA, 0xFF);
    io.outb(SLAVE_DATA, 0xFF);
    clearMask(0);
}

pub fn setMask(irq: u8) void {
    const port: u16 = if (irq < 8) MASTER_DATA else SLAVE_DATA;
    const bit: u3 = @intCast(if (irq < 8) irq else irq - 8);
    const value = io.inb(port) | (@as(u8, 1) << bit);
    io.outb(port, value);
}

