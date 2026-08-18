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

/// 6. syscall_uptime — int 0x80 uptime call must return a positive tick count.
fn syscall_uptime() bool {
    return syscall.invoke(.uptime, 0, 0, 0) > 0;
}

/// 7. slab_roundtrip — allocate a batch of objects, verify the live count,
/// free them all, and verify the count drops back to zero.
fn slab_roundtrip() bool {
    var sl = slab.Slab.init(heap.allocator(), 16, 8, 8);
    defer sl.deinit();
    var ptrs: [24][*]u8 = undefined;
    for (&ptrs) |*pp| {
        pp.* = sl.alloc() orelse return false;
    }
    if (sl.stats().live != 24) return false;
    for (ptrs) |pp| sl.free(pp);
    return sl.stats().live == 0;
}

/// 8. ring_fifo — push four bytes, verify full/count, pop them in FIFO order,
/// verify empty, and confirm overflow is rejected.
fn ring_fifo() bool {
    var rb = ring.Ring(4){};
    if (!rb.push('w')) return false;
    if (!rb.push('x')) return false;
    if (!rb.push('y')) return false;
    if (!rb.push('z')) return false;
    if (!rb.isFull()) return false;
    if (rb.len() != 4) return false;
    if (rb.push('!')) return false; // must reject (full)
    if (rb.pop() != 'w') return false;
    if (rb.pop() != 'x') return false;
    if (rb.pop() != 'y') return false;
    if (rb.pop() != 'z') return false;
    if (rb.pop() != null) return false; // must be empty
    return rb.isEmpty();
}

/// 9. libk_format — exercise formatDec, formatHex, strncmp, indexOf, and the
/// case-conversion helpers added in M17.
fn libk_format() bool {
    var buf: [24]u8 = undefined;
    // formatDec
    if (!std.mem.eql(u8, libk.formatDec(&buf, 0), "0")) return false;
    if (!std.mem.eql(u8, libk.formatDec(&buf, 12345), "12345")) return false;
    if (!std.mem.eql(u8, libk.formatDec(&buf, 999999999), "999999999")) return false;
    // formatHex
    if (!std.mem.eql(u8, libk.formatHex(&buf, 0), "0")) return false;
    if (!std.mem.eql(u8, libk.formatHex(&buf, 0xdeadbeef), "deadbeef")) return false;
    if (!std.mem.eql(u8, libk.formatHex(&buf, 0xff), "ff")) return false;
    // strncmp
    if (libk.strncmp("abc", "abd", 2) != 0) return false; // first 2 chars match
    if (libk.strncmp("abc", "abd", 3) >= 0) return false; // 'c' < 'd'
    if (libk.strncmp("xyz", "xyz", 3) != 0) return false;
    // indexOf
    if (libk.indexOf("hello", 'l') != 2) return false;
    if (libk.indexOf("hello", 'z') != null) return false;
    // case helpers
    if (libk.toUpper('a') != 'A') return false;
    if (libk.toUpper('Z') != 'Z') return false;
    if (libk.toLower('Z') != 'z') return false;
    if (libk.toLower('a') != 'a') return false;
    // startsWith
    if (!libk.startsWith("hello", "hel")) return false;
    if (libk.startsWith("hello", "world")) return false;
    return true;
}

/// 10. elf_parse — embed the sample ELF32 fixture and verify key header fields.
fn elf_parse() bool {
    const image = @embedFile("sample.elf");
    const hdr = elf.parse(image) catch return false;
    if (hdr.class != 1) return false;       // ELF32
    if (hdr.machine != 3) return false;     // EM_386
    if (hdr.entry != 0x401000) return false;
    if (hdr.phnum != 1) return false;
    return true;
}

/// 11. cpuid_vendor — vendor string from CPUID leaf 0 must be non-empty.
fn cpuid_vendor() bool {
    const v = cpu.vendor();
    for (v) |ch| {
        if (ch != 0) return true;
    }
    return false; // all-zero is suspicious
}

/// 12. acpi_rsdp — call find(); if RSDP is present verify rsdt_addr is non-zero;
/// if not present (e.g. minimal QEMU config) the test still passes — we just
/// verify the scan completed without a crash.
fn acpi_rsdp() bool {
    const r = acpi.find();
    if (r.found) {
        return r.rsdt_addr != 0;
    }
    return true; // scan completed; RSDP absence is OK in QEMU
}

/// 13. timefmt_format — exercises isLeapYear, weekday, daysInMonth, fmtIso, and
/// the epoch helpers on known fixed dates.
fn timefmt_format() bool {
    // Leap year checks.
    if (!timefmt.isLeapYear(2000)) return false; // divisible by 400
    if (timefmt.isLeapYear(1900)) return false;  // divisible by 100, not 400
    if (!timefmt.isLeapYear(2024)) return false; // divisible by 4, not 100
    if (timefmt.isLeapYear(2023)) return false;  // ordinary year

    // daysInMonth: February in leap vs non-leap year.
    if (timefmt.daysInMonth(2024, 2) != 29) return false;
    if (timefmt.daysInMonth(2023, 2) != 28) return false;
    if (timefmt.daysInMonth(2026, 1) != 31) return false;

    // weekday: 2026-06-09 is known to be a Tuesday (= 2).
    if (timefmt.weekday(2026, 6, 9) != 2) return false;
    // 2026-01-01 is a Thursday (= 4).
    if (timefmt.weekday(2026, 1, 1) != 4) return false;

    // fmtIso: verify the formatted string for a fixed time.
    const t = rtc.Time{ .year = 2026, .month = 6, .day = 9,
                        .hour = 12, .min = 0, .sec = 0 };
    var ibuf: [24]u8 = undefined;
    const iso = timefmt.fmtIso(&ibuf, t);
    if (!std.mem.eql(u8, iso, "2026-06-09T12:00:00")) return false;

    // dayOfYear: Jan 1 = 1, Feb 1 = 32, Dec 31 non-leap = 365.
    if (timefmt.dayOfYear(2026, 1, 1) != 1) return false;
    if (timefmt.dayOfYear(2026, 2, 1) != 32) return false;
    if (timefmt.dayOfYear(2023, 12, 31) != 365) return false;

    return true;
}

/// 14. pci_classname — verify classNameOf and vendorNameOf return expected strings
/// for a handful of well-known codes.
fn pci_classname() bool {
    // Class 0x01, sub 0x01 = IDE storage controller.
    if (!std.mem.eql(u8, pci.classNameOf(0x01, 0x01), "Storage / IDE")) return false;
    // Class 0x02, sub 0x00 = Ethernet.
    if (!std.mem.eql(u8, pci.classNameOf(0x02, 0x00), "Network / Ethernet")) return false;
    // Class 0x03, sub 0x00 = VGA.
    if (!std.mem.eql(u8, pci.classNameOf(0x03, 0x00), "Display / VGA Compatible")) return false;
    // Class 0x06, sub 0x00 = Host bridge.
    if (!std.mem.eql(u8, pci.classNameOf(0x06, 0x00), "Bridge / Host")) return false;
    // Unknown class code.
    if (!std.mem.eql(u8, pci.classNameOf(0xFE, 0x00), "Unknown Class")) return false;

