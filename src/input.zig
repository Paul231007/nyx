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

/// Push a byte into the ring. Drops the byte if the buffer is full.
pub fn push(c: u8) void {
    const next = (head + 1) % buf.len;
    if (next == tail) return; // full: drop
    buf[head] = c; // write slot first
    head = next; // then publish
}

/// Pop a byte, or null if empty.
pub fn pop() ?u8 {
    if (tail == head) return null;
    const c = buf[tail];
    tail = (tail + 1) % buf.len;
    return c;
}


