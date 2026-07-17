//! PIT (8253/8254) channel 0 driving IRQ0 at a configurable frequency.

const io = @import("io.zig");

const PIT_FREQ: u32 = 1193182;
const CHANNEL0: u16 = 0x40;
const COMMAND: u16 = 0x43;

var ticks_count: u64 = 0;
var configured_hz: u32 = 0;

/// Program channel 0 for `hz` Hz, square-wave (mode 3), lo/hi byte access.
pub fn init(frequency: u32) void {
    configured_hz = frequency;
    const divisor: u32 = PIT_FREQ / frequency;
    io.outb(COMMAND, 0x36);
    io.outb(CHANNEL0, @intCast(divisor & 0xFF));
    io.outb(CHANNEL0, @intCast((divisor >> 8) & 0xFF));
}

/// Called from the IRQ0 handler on every timer tick.
pub fn tick() void {
    ticks_count +%= 1;
}

pub fn ticks() u64 {
    return ticks_count;
}

