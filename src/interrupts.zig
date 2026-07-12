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

/// Syscall handler: reads nr/args from the saved frame, dispatches, writes
/// the return value back into frame.eax so `popa` restores it into eax on iret.
export fn syscallHandler(frame: *Frame) callconv(.c) void {
    const ret = syscall.dispatch(frame.eax, frame.ebx, frame.ecx, frame.edx);
    frame.eax = @truncate(ret);
}

export fn isrHandler(frame: *Frame) callconv(.c) void {
    var buf: [96]u8 = undefined;
    console.write(std.fmt.bufPrint(&buf, "EXCEPTION {d} ({s}) eip=0x{X} err=0x{X}\n", .{
        frame.int_no, nameOf(frame.int_no), frame.eip, frame.err_code,
    }) catch "");

    if (frame.int_no == 3) return; // breakpoint: recoverable, return via iret

    if (frame.int_no == 14) {
        const cr2 = asm volatile ("mov %%cr2, %[v]"
            : [v] "=r" (-> usize),
        );
        const ec = frame.err_code;
        console.write(std.fmt.bufPrint(&buf, "PAGE FAULT at 0x{X} eip=0x{X} err=0x{X} [{s}{s}{s}]\n", .{
            cr2,
            frame.eip,
            ec,
            if ((ec & 0x1) != 0) "P" else "-", // present vs non-present
            if ((ec & 0x2) != 0) "W" else "R", // write vs read
            if ((ec & 0x4) != 0) "U" else "K", // user vs kernel
        }) catch "");
        console.write("nyx: FATAL page fault, halting\n");
        exitQemu(.failure);
        hang();
    }

    // Anything else is fatal for now.
    console.write("nyx: FATAL exception, halting\n");
    exitQemu(.failure);
    hang();
}

export fn irqHandler(frame: *Frame) callconv(.c) void {
    const irq: u8 = @intCast(frame.int_no - 32);
    if (irq == 0) timer.tick() else if (irq == 1) keyboard.handleIrq();
    // Always acknowledge, or the PIC stops delivering further IRQs.
    pic.sendEOI(irq);
    // Preemptive scheduling: after EOI, let the scheduler round-robin on the
    // timer tick (no-op unless preemption has been explicitly enabled).
    if (irq == 0) sched.onTick();
}

pub fn init() void {
    setGate(0, &isr0);
    setGate(1, &isr1);
    setGate(2, &isr2);
    setGate(3, &isr3);
    setGate(4, &isr4);
    setGate(5, &isr5);
    setGate(6, &isr6);
    setGate(7, &isr7);
    setGate(8, &isr8);
    setGate(9, &isr9);
    setGate(10, &isr10);
    setGate(11, &isr11);
    setGate(12, &isr12);
    setGate(13, &isr13);
    setGate(14, &isr14);
    setGate(15, &isr15);
    setGate(16, &isr16);
    setGate(17, &isr17);
    setGate(18, &isr18);
    setGate(19, &isr19);
    setGate(20, &isr20);
    setGate(21, &isr21);
    setGate(22, &isr22);
    setGate(23, &isr23);
    setGate(24, &isr24);
    setGate(25, &isr25);
    setGate(26, &isr26);
    setGate(27, &isr27);
    setGate(28, &isr28);
    setGate(29, &isr29);
    setGate(30, &isr30);
    setGate(31, &isr31);

