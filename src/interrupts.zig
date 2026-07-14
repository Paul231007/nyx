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

    // Hardware IRQ gates: vectors 32..47 (PIC remapped to 0x20..0x2F).
    setGate(32, &irq0);
    setGate(33, &irq1);
    setGate(34, &irq2);
    setGate(35, &irq3);
    setGate(36, &irq4);
    setGate(37, &irq5);
    setGate(38, &irq6);
    setGate(39, &irq7);
    setGate(40, &irq8);
    setGate(41, &irq9);
    setGate(42, &irq10);
    setGate(43, &irq11);
    setGate(44, &irq12);
    setGate(45, &irq13);
    setGate(46, &irq14);
    setGate(47, &irq15);

    // int 0x80 syscall gate (DPL 0 — everything runs in ring 0).
    setGate(0x80, &isr128);

    idt.load();
}

inline fn setGate(n: u8, handler: *const anyopaque) void {
    idt.setGate(n, @intCast(@intFromPtr(handler)), 0x8E);
}

// The external stub symbols defined in the assembly block below.
extern fn isr0() void;
extern fn isr1() void;
extern fn isr2() void;
extern fn isr3() void;
extern fn isr4() void;
extern fn isr5() void;
extern fn isr6() void;
extern fn isr7() void;
extern fn isr8() void;
extern fn isr9() void;
extern fn isr10() void;
extern fn isr11() void;
extern fn isr12() void;
extern fn isr13() void;
extern fn isr14() void;
extern fn isr15() void;
extern fn isr16() void;
extern fn isr17() void;
extern fn isr18() void;
extern fn isr19() void;
extern fn isr20() void;
extern fn isr21() void;
extern fn isr22() void;
extern fn isr23() void;
extern fn isr24() void;
extern fn isr25() void;
extern fn isr26() void;
extern fn isr27() void;
extern fn isr28() void;
extern fn isr29() void;
extern fn isr30() void;
extern fn isr31() void;

extern fn isr128() void;

extern fn irq0() void;
extern fn irq1() void;
extern fn irq2() void;
extern fn irq3() void;
extern fn irq4() void;
extern fn irq5() void;
extern fn irq6() void;
extern fn irq7() void;
extern fn irq8() void;
extern fn irq9() void;
extern fn irq10() void;
extern fn irq11() void;
extern fn irq12() void;
extern fn irq13() void;
extern fn irq14() void;
extern fn irq15() void;

// 32 exception stubs + the shared bottom half, in one AT&T assembly block.
// No-error-code vectors push a dummy 0 so every Frame has identical layout.
comptime {
    asm (
        \\.text
        \\
        \\.macro ISR_NOERR n
        \\.global isr\n
        \\isr\n:
        \\    cli
        \\    pushl $0
        \\    pushl $\n
        \\    jmp isr_common
        \\.endm
        \\
        \\.macro ISR_ERR n
        \\.global isr\n
        \\isr\n:
        \\    cli
        \\    pushl $\n
        \\    jmp isr_common
        \\.endm
        \\
        \\ISR_NOERR 0
        \\ISR_NOERR 1
        \\ISR_NOERR 2
        \\ISR_NOERR 3
        \\ISR_NOERR 4
        \\ISR_NOERR 5
        \\ISR_NOERR 6
        \\ISR_NOERR 7
        \\ISR_ERR   8
        \\ISR_NOERR 9
        \\ISR_ERR   10
        \\ISR_ERR   11
        \\ISR_ERR   12
        \\ISR_ERR   13
        \\ISR_ERR   14
        \\ISR_NOERR 15
        \\ISR_NOERR 16
        \\ISR_ERR   17
        \\ISR_NOERR 18
        \\ISR_NOERR 19
        \\ISR_NOERR 20
        \\ISR_NOERR 21
        \\ISR_NOERR 22
        \\ISR_NOERR 23
        \\ISR_NOERR 24
        \\ISR_NOERR 25
        \\ISR_NOERR 26
        \\ISR_NOERR 27
        \\ISR_NOERR 28
        \\ISR_NOERR 29
        \\ISR_NOERR 30
        \\ISR_NOERR 31
        \\
        \\.macro IRQ n
        \\.global irq\n
        \\irq\n:
        \\    cli
        \\    pushl $0
        \\    pushl $(32 + \n)
        \\    jmp irq_common
        \\.endm
        \\
        \\IRQ 0
        \\IRQ 1
        \\IRQ 2
        \\IRQ 3
        \\IRQ 4
        \\IRQ 5
        \\IRQ 6
        \\IRQ 7
        \\IRQ 8
        \\IRQ 9
        \\IRQ 10
        \\IRQ 11
        \\IRQ 12
        \\IRQ 13
        \\IRQ 14
        \\IRQ 15
        \\
        \\irq_common:
        \\    pusha
        \\    push %ds
        \\    mov $0x10, %ax
        \\    mov %ax, %ds
        \\    mov %ax, %es
        \\    mov %ax, %fs
        \\    mov %ax, %gs
        \\    push %esp
        \\    call irqHandler
        \\    add $4, %esp
        \\    pop %eax
        \\    mov %ax, %ds
        \\    mov %ax, %es
        \\    mov %ax, %fs
        \\    mov %ax, %gs
        \\    popa
        \\    add $8, %esp
        \\    iret
        \\
        \\isr_common:
        \\    pusha
        \\    push %ds
        \\    mov $0x10, %ax
        \\    mov %ax, %ds
        \\    mov %ax, %es
        \\    mov %ax, %fs
        \\    mov %ax, %gs
        \\    push %esp
        \\    call isrHandler
        \\    add $4, %esp
        \\    pop %eax
        \\    mov %ax, %ds
        \\    mov %ax, %es
        \\    mov %ax, %fs
        \\    mov %ax, %gs
        \\    popa
        \\    add $8, %esp
        \\    iret
        \\
        \\.global isr128
        \\isr128:
        \\    cli
        \\    pushl $0
        \\    pushl $128
        \\    jmp syscall_common
        \\
        \\syscall_common:
        \\    pusha
        \\    push %ds
        \\    mov $0x10, %ax
        \\    mov %ax, %ds
        \\    mov %ax, %es
        \\    mov %ax, %fs
        \\    mov %ax, %gs
        \\    push %esp
        \\    call syscallHandler
        \\    add $4, %esp
        \\    pop %eax
        \\    mov %ax, %ds
        \\    mov %ax, %es
        \\    mov %ax, %fs
        \\    mov %ax, %gs
        \\    popa
        \\    add $8, %esp
        \\    iret
    );
}

