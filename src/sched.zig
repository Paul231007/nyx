//! sched — a tiny cooperative round-robin scheduler with kernel threads.
//!
//! Each task owns a heap-allocated stack and a saved `esp`. Switching between
//! tasks is a callee-saved register swap (`switchContext`) that parks the old
//! task's stack pointer and resumes the new one. A freshly spawned task has its
//! stack hand-crafted so the very first `switchContext` "returns" into a
//! trampoline, which calls the task's entry fn, marks the task done, then yields
//! forever (so a finished task is skipped, never falling off its stack).
//!
//! The bootstrap task represents kmain's context: it is a real node in the ready
//! ring so the scheduler can round-robin back into kmain when every spawned task
//! has finished.

const std = @import("std");
const heap = @import("heap.zig");


