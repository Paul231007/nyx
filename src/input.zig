//! Shared input ring buffer + blocking line reader.
//!
//! Both the keyboard IRQ (`keyboard.handleIrq`) and the serial poller (in
//! `getchar`) feed bytes in via `push`; the shell drains them via `pop`.
//! Single core: the IRQ writes the slot before advancing `head`, so a reader
//! that only touches `tail` sees a consistent buffer without locking.

const console = @import("console.zig");
const serial = @import("serial.zig");

var buf: [256]u8 = undefined;
var head: usize = 0; // producer index (IRQ side)
var tail: usize = 0; // consumer index (reader side)


