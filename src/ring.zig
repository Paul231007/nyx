//! ring — a generic fixed-capacity byte FIFO ring buffer.
//!
//! `Ring(N)` returns a struct type whose instances occupy exactly `N + @sizeOf(usize)*2`
//! bytes on the stack (no heap allocation).  All operations are O(1).
//! `push` fails (returns false) when the buffer is full; `pop` returns null
//! when it is empty.


