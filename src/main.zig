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

    // M7: kernel heap allocator (free-list, std.mem.Allocator).
    heap.init();
    console.write("[M7] heap initialized (4 MiB @ 0xD0000000)\n");
    const alloc = heap.allocator();
    // (a) raw alloc/free with pattern check.
    const p = alloc.alloc(u8, 100) catch unreachable;
    for (p, 0..) |*x, i| x.* = @truncate(i);
    var ok = true;
    for (p, 0..) |x, i| {
        if (x != @as(u8, @truncate(i))) ok = false;
    }
    alloc.free(p);
    // (b) std.ArrayList round-trip through the kernel allocator.
    var list = std.ArrayList(u32){};
    defer list.deinit(alloc);
    var i: u32 = 0;
    while (i < 500) : (i += 1) {
        list.append(alloc, i * 3) catch unreachable;
    }
    var sum: u64 = 0;
    for (list.items) |v| sum += v;
    var hb: [96]u8 = undefined;
    console.write(std.fmt.bufPrint(&hb, "[M7] arraylist: len={d} sum={d} (pattern_ok={})\n", .{ list.items.len, sum, ok }) catch "");
    if (ok and list.items.len == 500 and sum == 374250) console.write("nyx: M7 OK\n") else console.write("nyx: M7 FAIL\n");

    // Init block cache now that the heap is ready; later tasks (M12, shell) use it.
    {
        const blockcache = @import("blockcache.zig");
        blockcache.init(heap.allocator());
    }

    // M8: cooperative round-robin scheduler with kernel threads.
    sched.init();
    _ = sched.spawn(taskA);
    _ = sched.spawn(taskB);
    _ = sched.spawn(taskC);
    console.write("[M8] spawned 3 tasks; running scheduler\n");
    sched.runUntilIdle();
    console.write("\n[M8] all tasks finished, back in bootstrap\n");

    // Preemptive demo: tasks that NEVER call yield(). The timer IRQ forces the
    // context switches, proving real preemption. Tasks spin between prints so a
    // tick lands mid-task.
    sched.enablePreemption();
    _ = sched.spawn(ptaskX);
    _ = sched.spawn(ptaskY);
    _ = sched.spawn(ptaskZ);
    console.write("[M8] spawned 3 PREEMPTIVE tasks (no yields); timer drives switches\n");
    sched.runUntilIdle();
    sched.disablePreemption();
    console.write("\n[M8] preemptive tasks finished\n");
    console.write("nyx: M8 OK\n");

    // M10: libk — string + numeric helpers used across the kernel and shell.
    {
        const libk = @import("libk.zig");
        var m10ok = true;
        if (!libk.streq("abc", "abc") or libk.streq("abc", "abd")) m10ok = false;
        if (libk.parseUint("255", 10) != 255) m10ok = false;
        if (libk.parseHex("CAFE") != 0xCAFE) m10ok = false;
        var dst: [4]u8 = undefined;
        libk.memset(&dst, 0xAA);
        if (dst[0] != 0xAA or dst[3] != 0xAA) m10ok = false;
        libk.memcpy(&dst, "WXYZ");
        if (dst[2] != 'Y') m10ok = false;
        if (m10ok) console.write("nyx: M10 OK\n") else console.write("nyx: M10 FAIL\n");
    }

    // M11: CMOS RTC + PCI bus enumeration.
    {
        const rtc = @import("rtc.zig");
        const pci = @import("pci.zig");
        const t = rtc.read();
        var rb: [96]u8 = undefined;
        console.write(std.fmt.bufPrint(&rb, "[M11] rtc {d:0>2}:{d:0>2}:{d:0>2}\n", .{ t.hour, t.min, t.sec }) catch "");
        var devs: [32]pci.Device = undefined;
        const npci = pci.enumerate(&devs);
        console.write(std.fmt.bufPrint(&rb, "[M11] pci devices found: {d}\n", .{npci}) catch "");
        if (npci >= 1 and t.sec < 60) console.write("nyx: M11 OK\n") else console.write("nyx: M11 FAIL\n");
    }

    // M12: ATA PIO disk — identify, write a sentinel sector, read it back.
    {
        const ata = @import("ata.zig");
        if (ata.identify()) |dinfo| {
            var wb: [ata.SECTOR]u8 = undefined;
            for (&wb, 0..) |*bb, ii| bb.* = @truncate(ii * 7 + 1);
            const wrote = ata.writeSectors(2, 1, &wb);
            var rb2: [ata.SECTOR]u8 = undefined;
            const rd = ata.readSectors(2, 1, &rb2);
            var same = wrote and rd;
            for (wb, rb2) |aa, cc| { if (aa != cc) same = false; }
            var mb: [64]u8 = undefined;
            console.write(std.fmt.bufPrint(&mb, "[M12] disk sectors={d}\n", .{dinfo.sectors}) catch "");
            if (same) console.write("nyx: M12 OK\n") else console.write("nyx: M12 FAIL\n");
        } else console.write("nyx: M12 FAIL (no disk)\n");
    }

    // M13: VFS layer — mount a stub fs, write+read through fds.
    {
        vfs.mount(&stub_fs);
        const fd = vfs.open("/x").?;
        _ = vfs.write(fd, "hello vfs");
        vfs.seek(fd, 0);
        var rb3: [16]u8 = undefined;
        const nread = vfs.read(fd, &rb3);
        vfs.close(fd);
        const ok13 = nread == 9 and std.mem.eql(u8, rb3[0..9], "hello vfs");
        if (ok13) console.write("nyx: M13 OK\n") else console.write("nyx: M13 FAIL\n");
    }

    // M14: RamFS + tar initrd
    {
        const ramfs = @import("ramfs.zig");
        const tar = @import("tar.zig");
        ramfs.init(heap.allocator());
        vfs.mount(ramfs.fs());
        const ncreated = tar.unpackInto(@embedFile("initrd.tar"), ramfs.fs());
        var mb14: [80]u8 = undefined;
        console.write(std.fmt.bufPrint(&mb14, "[M14] initrd entries: {d}\n", .{ncreated}) catch "");
        const fd14 = vfs.open("/hello.txt");
        var ok14 = false;
        if (fd14) |f| {
            var rb14: [32]u8 = undefined;
            const got14 = vfs.read(f, &rb14);
            vfs.close(f);
            ok14 = (ncreated >= 2) and std.mem.eql(u8, rb14[0..got14], "hello nyx\n");
        }
        if (ok14) console.write("nyx: M14 OK\n") else console.write("nyx: M14 FAIL\n");
    }

