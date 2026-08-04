//! ktest — kernel self-test harness (M16).
//!
//! Each test case is a standalone function that returns `true` on pass.
//! `runAll` iterates the registered table, prints per-case results, and
//! returns aggregate counts.  Cases are kept independent; any side effects
//! (a ramfs file, a rewritten ATA sector) are documented but benign.

