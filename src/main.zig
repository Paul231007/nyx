//! nyx — a small freestanding x86 kernel.
//! Entry point `kmain` is called from boot.s with the multiboot magic + info.

const std = @import("std");
const console = @import("console.zig");
const io = @import("io.zig");
const gdt = @import("gdt.zig");
const interrupts = @import("interrupts.zig");
const pic = @import("pic.zig");
const timer = @import("timer.zig");
const input = @import("input.zig");
const pmm = @import("pmm.zig");
const paging = @import("paging.zig");
const heap = @import("heap.zig");
const sched = @import("sched.zig");
const shell = @import("shell.zig");

// --- M13 VFS stub filesystem (a single in-memory file) ---
const vfs = @import("vfs.zig");
var stub_node: vfs.Node = .{ .kind = .file, .size = 0 };
var stub_buf: [128]u8 = undefined;
fn stubOpen(path: []const u8) ?*vfs.Node {
    _ = path;
    return &stub_node;
}
fn stubRead(node: *vfs.Node, off: u32, buf: []u8) u32 {
    _ = node;
    var n: u32 = 0;
    while (off + n < stub_node.size and n < buf.len) : (n += 1) buf[n] = stub_buf[off + n];
    return n;
}
fn stubWrite(node: *vfs.Node, off: u32, data: []const u8) u32 {
    _ = node;
    var n: u32 = 0;
    while (off + n < stub_buf.len and n < data.len) : (n += 1) stub_buf[off + n] = data[n];
    if (off + n > stub_node.size) stub_node.size = off + n;
    return n;
}
fn stubReaddir(dir: *vfs.Node, idx: usize) ?*vfs.Node {
    _ = dir;
    _ = idx;
    return null;
}
var stub_fs: vfs.FileSystem = .{ .open = stubOpen, .read = stubRead, .write = stubWrite, .readdir = stubReaddir };

/// QEMU `isa-debug-exit` device: writing V to port 0xf4 exits QEMU with status
/// (V<<1)|1. Used so headless self-tests stop the VM promptly.
const ExitCode = enum(u8) { success = 0x10, failure = 0x11 };
fn exitQemu(code: ExitCode) void {
    io.outb(0xf4, @intFromEnum(code));
}

pub fn hang() noreturn {
    while (true) asm volatile ("hlt");
}

// Freestanding panic handler.
pub const panic = std.debug.FullPanic(panicFn);
fn panicFn(msg: []const u8, _: ?usize) noreturn {
    console.write("\n*** KERNEL PANIC: ");
    console.write(msg);
    console.write(" ***\n");
    exitQemu(.failure);
    hang();
}

export fn kmain(magic: u32, info: u32) callconv(.c) void {
    console.init();
    console.write("\n================================\n");
    console.write("  nyx -- a small x86 kernel\n");
    console.write("================================\n");

    var buf: [80]u8 = undefined;
    console.write(std.fmt.bufPrint(&buf, "multiboot magic : 0x{X} ({s})\n", .{
        magic, if (magic == 0x2BADB002) "OK" else "BAD",
    }) catch "");
    console.write(std.fmt.bufPrint(&buf, "multiboot info  : 0x{X}\n", .{info}) catch "");

    console.write("[M0] boot foundation: VGA + serial online\n");
    console.write("nyx: M0 OK\n");

    gdt.init();
    console.write("[M2] GDT loaded\n");
    interrupts.init();
    console.write("[M2] IDT loaded\n");
    asm volatile ("int $3"); // breakpoint self-test (recoverable)
    console.write("[M2] returned from int3 (iret works)\n");
    console.write("nyx: M2 OK\n");

    // M3: hardware interrupts. Remap the PIC before enabling interrupts so a
    // stray IRQ can't vector into an exception slot. IDT gates 32..47 were
    // already wired by interrupts.init() above.
    pic.init();
    console.write("[M3] PIC remapped\n");
    timer.init(100); // 100 Hz
    console.write("[M3] PIT @ 100 Hz\n");
    asm volatile ("sti"); // enable interrupts

    // Idle with hlt so each timer IRQ wakes us; bounded by a guard counter.
    var guard: u64 = 0;
    while (timer.ticks() < 5 and guard < 100_000_000) : (guard += 1) {
        asm volatile ("hlt");
    }


