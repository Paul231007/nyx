//! Shared input ring buffer + blocking line reader.
//!
//! Both the keyboard IRQ (`keyboard.handleIrq`) and the serial poller (in
//! `getchar`) feed bytes in via `push`; the shell drains them via `pop`.
//! Single core: the IRQ writes the slot before advancing `head`, so a reader
//! that only touches `tail` sees a consistent buffer without locking.


