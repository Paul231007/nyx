//! ring — a generic fixed-capacity byte FIFO ring buffer.
//!
//! `Ring(N)` returns a struct type whose instances occupy exactly `N + @sizeOf(usize)*2`
//! bytes on the stack (no heap allocation).  All operations are O(1).
//! `push` fails (returns false) when the buffer is full; `pop` returns null
//! when it is empty.

/// Return a ring-buffer type whose capacity is exactly `N` bytes.
/// Example usage:
///   var rb = Ring(64){};
///   _ = rb.push('x');
///   const b = rb.pop();
pub fn Ring(comptime N: usize) type {
    comptime {
        if (N == 0) @compileError("Ring capacity must be > 0");
    }
    return struct {
        buf: [N]u8 = undefined,
        /// Index of the next byte to read.
        head: usize = 0,
        /// Index of the next empty slot to write into.
        tail: usize = 0,
        /// Number of bytes currently in the buffer.
        count: usize = 0,


