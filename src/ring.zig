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

        /// Push `b` onto the tail.  Returns `false` if the buffer is full.
        pub fn push(self: *@This(), b: u8) bool {
            if (self.count == N) return false;
            self.buf[self.tail] = b;
            self.tail = (self.tail + 1) % N;
            self.count += 1;
            return true;
        }

        /// Pop a byte from the head, or return null if the buffer is empty.
        pub fn pop(self: *@This()) ?u8 {
            if (self.count == 0) return null;
            const b = self.buf[self.head];
            self.head = (self.head + 1) % N;
            self.count -= 1;
            return b;
        }

        /// Number of bytes currently stored.
        pub fn len(self: *const @This()) usize {
            return self.count;
        }

        /// True when no bytes are stored.
        pub fn isEmpty(self: *const @This()) bool {
            return self.count == 0;
        }

