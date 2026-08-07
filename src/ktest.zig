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
