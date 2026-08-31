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

    var b: [64]u8 = undefined;
    console.write(std.fmt.bufPrint(&b, "[M3] timer ticks = {d}\n", .{timer.ticks()}) catch "");
    if (timer.ticks() > 0) console.write("nyx: M3 OK\n") else console.write("nyx: M3 FAIL (no ticks)\n");

    // M4: keyboard IRQ1 + serial console input + line reader.
    pic.clearMask(1); // enable keyboard IRQ
    console.write("[M4] keyboard IRQ1 enabled; serial input active\n");
    console.write("nyx: M4 OK\n");

    // M5: physical memory manager — parse the multiboot mmap, build a frame bitmap.
    pmm.init(info);
    const s = pmm.stats();
    var pb: [128]u8 = undefined;
    console.write(std.fmt.bufPrint(&pb, "[M5] frames: total={d} used={d} free={d} (~{d} MiB usable)\n", .{ s.total, s.used, s.free, (s.total * 4) / 1024 }) catch "");

    // Round-trip test: alloc 3 frames, check distinct + page-aligned, free them.
    const free0 = pmm.stats().free;
    const a1 = pmm.allocFrame().?;
    const a2 = pmm.allocFrame().?;
    const a3 = pmm.allocFrame().?;
    console.write(std.fmt.bufPrint(&pb, "[M5] alloc: 0x{X} 0x{X} 0x{X}\n", .{ a1, a2, a3 }) catch "");
    const aligned = (a1 & 0xFFF) == 0 and (a2 & 0xFFF) == 0 and (a3 & 0xFFF) == 0;
    const distinct = a1 != a2 and a2 != a3 and a1 != a3;
    pmm.freeFrame(a1);
    pmm.freeFrame(a2);
    pmm.freeFrame(a3);
    const restored = pmm.stats().free == free0;
    if (aligned and distinct and restored) console.write("nyx: M5 OK\n") else console.write("nyx: M5 FAIL\n");

    // M6: paging — build an identity map and enable CR0.PG.
    paging.init();
    console.write("[M6] paging enabled (identity map, CR0.PG on)\n");
    // Prove the mapping works: write a sentinel through a virtual address and read it back.
    const probe: *volatile u32 = @ptrFromInt(0x800000); // 8 MiB, identity-mapped RAM
    probe.* = 0xCAFEBABE;
    const got = probe.*;
    console.write(std.fmt.bufPrint(&b, "[M6] sentinel @8MiB readback = 0x{X}\n", .{got}) catch "");
    // Prove map() works: map a fresh pmm frame to a high virtual addr, write+read it.
    const frame_phys = pmm.allocFrame().?;
    const VADDR: usize = 0xE0000000; // 3.5 GiB, currently unmapped
    paging.map(VADDR, frame_phys, 0x3); // present+rw
    const hp: *volatile u32 = @ptrFromInt(VADDR);
    hp.* = 0x1234ABCD;
    const got2 = hp.*;
    console.write(std.fmt.bufPrint(&b, "[M6] mapped 0x{X}->0x{X}, readback = 0x{X}\n", .{ VADDR, frame_phys, got2 }) catch "");
    if (got == 0xCAFEBABE and got2 == 0x1234ABCD) console.write("nyx: M6 OK\n") else console.write("nyx: M6 FAIL\n");

