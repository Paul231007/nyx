//! CPU exception (ISR) layer: 32 assembly stubs for vectors 0..31 funnel into
//! one common stub that saves a uniform register frame and calls `isrHandler`.
//!
//! Stack frame, from low address (where the Frame pointer points) upward:
//!   ds, edi, esi, ebp, esp_dummy, ebx, edx, ecx, eax  (from `push %ds` + pusha)
//!   int_no, err_code                                   (pushed by the stubs)
//!   eip, cs, eflags[, useresp, ss]                     (pushed by the CPU)

const std = @import("std");
const console = @import("console.zig");
const io = @import("io.zig");
const idt = @import("idt.zig");
const pic = @import("pic.zig");
const timer = @import("timer.zig");
const keyboard = @import("keyboard.zig");
const sched = @import("sched.zig");
const syscall = @import("syscall.zig");

/// Register/trap frame handed to `isrHandler`. Field order matches the push
/// order documented above (and in the M2 spec) exactly.
pub const Frame = extern struct {
    ds: u32,
    edi: u32,
    esi: u32,
    ebp: u32,
    esp_dummy: u32,
    ebx: u32,
    edx: u32,
    ecx: u32,
    eax: u32,
    int_no: u32,
    err_code: u32,
    eip: u32,
    cs: u32,
    eflags: u32,
    useresp: u32,
    ss: u32,
};

const exception_names = [_][]const u8{
    "Divide Error", // 0
    "Debug", // 1
    "Non-Maskable Interrupt", // 2
    "Breakpoint", // 3
    "Overflow", // 4
    "Bound Range Exceeded", // 5
    "Invalid Opcode", // 6
    "Device Not Available", // 7
    "Double Fault", // 8
    "Coprocessor Segment Overrun", // 9
    "Invalid TSS", // 10
    "Segment Not Present", // 11
    "Stack-Segment Fault", // 12
    "General Protection", // 13
    "Page Fault", // 14
    "Reserved", // 15
    "x87 FPU Error", // 16
    "Alignment Check", // 17
    "Machine Check", // 18
    "SIMD FP Exception", // 19
};

fn nameOf(n: u32) []const u8 {
    return if (n < exception_names.len) exception_names[n] else "Reserved";
}

/// Local copies so we don't need to reach back into main.zig.
const ExitCode = enum(u8) { success = 0x10, failure = 0x11 };
fn exitQemu(code: ExitCode) void {
    io.outb(0xf4, @intFromEnum(code));
}
fn hang() noreturn {
    while (true) asm volatile ("hlt");
}

