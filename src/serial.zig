//! COM1 serial driver. Doubles as the headless console for testing: we can
//! drive the kernel by piping bytes into QEMU's `-serial stdio` and read its
//! output back the same way.

const io = @import("io.zig");

const COM1: u16 = 0x3F8;

pub fn init() void {
    io.outb(COM1 + 1, 0x00); // disable interrupts
    io.outb(COM1 + 3, 0x80); // enable DLAB (set baud divisor)
    io.outb(COM1 + 0, 0x03); // divisor lo: 0x0003 => 38400 baud
    io.outb(COM1 + 1, 0x00); // divisor hi
    io.outb(COM1 + 3, 0x03); // 8 bits, no parity, one stop bit
    // Leave the RX FIFO DISABLED. With the 16550 FIFO off, QEMU flow-controls
    // the receiver (it holds the next byte in the chardev until we drain the
    // 1-byte RBR), so no piped input byte is ever dropped — whereas turning the
    // FIFO on discards whatever byte already sits in the pre-FIFO RBR.
    io.outb(COM1 + 2, 0x00); // FIFO off
    io.outb(COM1 + 4, 0x0B); // IRQs enabled, RTS/DSR set
}

fn txEmpty() bool {
    return (io.inb(COM1 + 5) & 0x20) != 0;
}

