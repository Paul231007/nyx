//! PIT (8253/8254) channel 0 driving IRQ0 at a configurable frequency.

const io = @import("io.zig");

const PIT_FREQ: u32 = 1193182;
const CHANNEL0: u16 = 0x40;
const COMMAND: u16 = 0x43;

var ticks_count: u64 = 0;
var configured_hz: u32 = 0;

