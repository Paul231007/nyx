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


