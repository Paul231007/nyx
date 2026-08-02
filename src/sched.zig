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

pub const Task = struct {
    esp: u32,
    stack: []u8,
    id: u32,
    done: bool,
    next: ?*Task,
    fn_ptr: *const fn () void,
};

const STACK_SIZE: usize = 16 * 1024;

var bootstrap: *Task = undefined;
var current: ?*Task = null;
var next_id: u32 = 0;
var preempt: bool = false;

/// x86 cdecl callee-saved context switch. After `push ebp/ebx/esi/edi` (16 bytes)
/// plus the return address (4 bytes), arg1 sits at 20(%esp), arg2 at 24(%esp).
extern fn switchContext(old_esp_ptr: *u32, new_esp: u32) void;


