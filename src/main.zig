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

