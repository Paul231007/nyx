//! ktest — kernel self-test harness (M16).
//!
//! Each test case is a standalone function that returns `true` on pass.
//! `runAll` iterates the registered table, prints per-case results, and
//! returns aggregate counts.  Cases are kept independent; any side effects
//! (a ramfs file, a rewritten ATA sector) are documented but benign.

const std = @import("std");
const console = @import("console.zig");
const libk = @import("libk.zig");
const pmm = @import("pmm.zig");
const heap = @import("heap.zig");
const vfs = @import("vfs.zig");
const ramfs = @import("ramfs.zig");
const ata = @import("ata.zig");
const syscall = @import("syscall.zig");
const slab = @import("slab.zig");
const ring = @import("ring.zig");
const elf = @import("elf.zig");
const cpu = @import("cpu.zig");
const acpi = @import("acpi.zig");
const timefmt = @import("timefmt.zig");
const rtc = @import("rtc.zig");
const pci = @import("pci.zig");
const keyboard = @import("keyboard.zig");

/// A single named test case.
pub const Case = struct { name: []const u8, run: *const fn () bool };

/// Aggregate result returned by `runAll`.
pub const Result = struct { passed: u32, failed: u32 };

// ---- test cases ---------------------------------------------------------------

/// 1. libk_parse — exercises parseUint, parseHex, and streq.
fn libk_parse() bool {
    const dec = libk.parseUint("255", 10) orelse return false;
    if (dec != 255) return false;
    const hex = libk.parseHex("0xCAFE") orelse return false;
    if (hex != 0xCAFE) return false;
    return libk.streq("ab", "ab");
}

/// 2. pmm_roundtrip — alloc one frame and verify alignment; free restores count.
fn pmm_roundtrip() bool {
    const before = pmm.stats().free;
    const frame = pmm.allocFrame() orelse return false;
    // Page-aligned sanity check.
    if (frame & 0xFFF != 0) {
        pmm.freeFrame(frame);
        return false;
    }
    pmm.freeFrame(frame);
    return pmm.stats().free == before;
}

/// 3. heap_alloc — write and verify a pattern through the kernel heap allocator.
fn heap_alloc() bool {
    const alloc = heap.allocator();
    const buf = alloc.alloc(u8, 64) catch return false;
    defer alloc.free(buf);
    for (buf, 0..) |*byte, idx| byte.* = @truncate(idx ^ 0xA5);
    for (buf, 0..) |byte, idx| {
        if (byte != @as(u8, @truncate(idx ^ 0xA5))) return false;
    }
    return true;
}

/// 4. vfs_roundtrip — create a ramfs file, write "ktest", seek 0, read back.
fn vfs_roundtrip() bool {
    _ = ramfs.create("/ktest.tmp", .file) orelse return false;
    const fd = vfs.open("/ktest.tmp") orelse return false;
    defer vfs.close(fd);
    const written = vfs.write(fd, "ktest");
    if (written != 5) return false;
    vfs.seek(fd, 0);
    var rbuf: [8]u8 = undefined;
    const nread = vfs.read(fd, &rbuf);
    if (nread != 5) return false;
    return std.mem.eql(u8, rbuf[0..5], "ktest");
}

/// 5. ata_sector — write a known pattern to sector 5, read it back, compare.
fn ata_sector() bool {
    var wbuf: [ata.SECTOR]u8 = undefined;
    for (&wbuf, 0..) |*byte, idx| byte.* = @truncate(idx +% 0x42);
    if (!ata.writeSectors(5, 1, &wbuf)) return false;
    var rbuf: [ata.SECTOR]u8 = undefined;
    if (!ata.readSectors(5, 1, &rbuf)) return false;
    for (wbuf, rbuf) |wb, rb| {
        if (wb != rb) return false;
    }
    return true;
}

