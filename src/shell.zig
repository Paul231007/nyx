//! shell — nyx's interactive command shell (M9).
//!
//! Reads lines from the unified console (PS/2 keyboard IRQ + serial), parses the
//! first whitespace-delimited token as a command and the remainder as args, then
//! dispatches to a built-in. Runs forever: the kernel hands control here as its
//! final, interactive endpoint, so `run()` never returns.

const std = @import("std");
const console = @import("console.zig");
const vga = @import("vga.zig");
const io = @import("io.zig");
const input = @import("input.zig");
const pmm = @import("pmm.zig");
const timer = @import("timer.zig");
const heap = @import("heap.zig");
const sched = @import("sched.zig");
const rtc = @import("rtc.zig");
const pci = @import("pci.zig");
const ata = @import("ata.zig");
const vfs = @import("vfs.zig");
const ramfs = @import("ramfs.zig");
const ktest = @import("ktest.zig");
const slab = @import("slab.zig");
const elf = @import("elf.zig");
const cpu = @import("cpu.zig");
const acpi = @import("acpi.zig");
const libk = @import("libk.zig");
const timefmt = @import("timefmt.zig");

var line: [256]u8 = undefined;
var scratch: [160]u8 = undefined;

// ---- command history ring buffer -----------------------------------------------

const HISTORY_DEPTH = 16;
const HISTORY_LINE  = 128;

var hist_buf: [HISTORY_DEPTH][HISTORY_LINE]u8 = undefined;
var hist_len: [HISTORY_DEPTH]usize = [_]usize{0} ** HISTORY_DEPTH;
var hist_head: usize = 0;  // index of the NEXT slot to write (ring)
var hist_count: usize = 0; // total lines ever recorded (saturates at HISTORY_DEPTH)

