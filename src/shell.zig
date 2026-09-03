//! shell — nyx's interactive command shell (M9).
//!
//! Reads lines from the unified console (PS/2 keyboard IRQ + serial), parses the
//! first whitespace-delimited token as a command and the remainder as args, then
//! dispatches to a built-in. Runs forever: the kernel hands control here as its
//! final, interactive endpoint, so `run()` never returns.

