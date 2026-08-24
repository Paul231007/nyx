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

comptime {
    asm (
        \\.global switchContext
        \\switchContext:
        \\    push %ebp
        \\    push %ebx
        \\    push %esi
        \\    push %edi
        \\    mov 20(%esp), %eax
        \\    mov %esp, (%eax)
        \\    mov 24(%esp), %esp
        \\    pop %edi
        \\    pop %esi
        \\    pop %ebx
        \\    pop %ebp
        \\    ret
    );
}

/// First thing a freshly spawned task runs (entered via switchContext's `ret`).
/// `current` already points at this task. Run the entry fn, then mark done and
/// yield forever so we never return off the end of the stack.
fn taskTrampoline() callconv(.c) void {
    // New tasks must run with interrupts enabled so timer preemption (if on)
    // can fire; cooperative-only tasks are unaffected by an extra sti.
    asm volatile ("sti");
    const t = current.?;
    t.fn_ptr();
    t.done = true;
    while (true) yield();
}

pub fn init() void {
    const alloc = heap.allocator();
    const b = alloc.create(Task) catch @panic("sched: bootstrap alloc failed");
    b.* = .{
        .esp = 0, // filled in on the first switch away
        .stack = &[_]u8{},
        .id = next_id,
        .done = false,
        .next = undefined,
        .fn_ptr = undefined,
    };
    next_id += 1;
    b.next = b; // ring of one
    bootstrap = b;
    current = b;
}

pub fn spawn(f: *const fn () void) *Task {
    const alloc = heap.allocator();
    const t = alloc.create(Task) catch @panic("sched: task alloc failed");
    const stack = alloc.alloc(u8, STACK_SIZE) catch @panic("sched: stack alloc failed");
    t.* = .{
        .esp = 0,
        .stack = stack,
        .id = next_id,
        .done = false,
        .next = undefined,
        .fn_ptr = f,
    };
    next_id += 1;

    // Build the initial stack top-down: [entry][ebp=0][ebx=0][esi=0][edi=0].
    // esp points at the saved-edi slot so switchContext's pops land cleanly and
    // its `ret` jumps to the trampoline.
    var sp: usize = (@intFromPtr(stack.ptr) + stack.len) & ~@as(usize, 0xF);
    sp -= 4;
    @as(*u32, @ptrFromInt(sp)).* = @intCast(@intFromPtr(&taskTrampoline)); // entry
    sp -= 4;
    @as(*u32, @ptrFromInt(sp)).* = 0; // ebp
    sp -= 4;
    @as(*u32, @ptrFromInt(sp)).* = 0; // ebx
    sp -= 4;
    @as(*u32, @ptrFromInt(sp)).* = 0; // esi
    sp -= 4;
    @as(*u32, @ptrFromInt(sp)).* = 0; // edi
    t.esp = @intCast(sp);

    // Link in just before the bootstrap node, preserving spawn order in the ring.
    var p = bootstrap;
    while (p.next.? != bootstrap) : (p = p.next.?) {}
    p.next = t;
    t.next = bootstrap;
    return t;
}


