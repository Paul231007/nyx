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

/// Record a non-empty command line in the history ring.
fn histPush(text: []const u8) void {
    const n = @min(text.len, HISTORY_LINE);
    @memcpy(hist_buf[hist_head][0..n], text[0..n]);
    hist_len[hist_head] = n;
    hist_head = (hist_head + 1) % HISTORY_DEPTH;
    if (hist_count < HISTORY_DEPTH) hist_count += 1;
}

fn print(comptime fmt: []const u8, args: anytype) void {
    console.write(std.fmt.bufPrint(&scratch, fmt, args) catch return);
}

/// Trim leading/trailing ASCII whitespace.
fn trim(s: []const u8) []const u8 {
    return std.mem.trim(u8, s, " \t\r\n");
}

pub fn run() noreturn {
    console.write("\n");
    console.write("================================\n");
    console.write("  nyx shell -- type 'help'\n");
    console.write("================================\n");
    console.write("nyx: M9 OK (shell ready)\n");

    while (true) {
        console.write("nyx> ");
        const n = input.readLine(&line);
        const text = trim(line[0..n]);
        if (text.len == 0) continue;

        // Record non-empty lines in the history ring.
        histPush(text);

        // Split off the first token as the command; the rest is args.
        var cmd = text;
        var args: []const u8 = "";
        if (std.mem.indexOfScalar(u8, text, ' ')) |sp| {
            cmd = text[0..sp];
            args = trim(text[sp + 1 ..]);
        }

        if (std.mem.eql(u8, cmd, "help")) {
            cmdHelp();
        } else if (std.mem.eql(u8, cmd, "echo")) {
            console.write(args);
            console.write("\n");
        } else if (std.mem.eql(u8, cmd, "mem")) {
            cmdMem();
        } else if (std.mem.eql(u8, cmd, "uptime")) {
            cmdUptime();
        } else if (std.mem.eql(u8, cmd, "ps")) {
            cmdPs();
        } else if (std.mem.eql(u8, cmd, "clear")) {
            vga.clear();
            console.write("\x1b[2J\x1b[H"); // ANSI clear for serial terminals
        } else if (std.mem.eql(u8, cmd, "reboot")) {
            console.write("rebooting...\n");
            io.outb(0x64, 0xFE); // pulse the 8042 CPU reset line
            while (true) asm volatile ("hlt");
        } else if (std.mem.eql(u8, cmd, "date")) {
            cmdDate();
        } else if (std.mem.eql(u8, cmd, "lspci")) {
            cmdLspci();
        } else if (std.mem.eql(u8, cmd, "diskinfo")) {
            cmdDiskinfo();
        } else if (std.mem.eql(u8, cmd, "ls")) {
            cmdLs(args);
        } else if (std.mem.eql(u8, cmd, "cat")) {
            cmdCat(args);
        } else if (std.mem.eql(u8, cmd, "write")) {
            cmdWrite(args);
        } else if (std.mem.eql(u8, cmd, "mkdir")) {
            cmdMkdir(args);
        } else if (std.mem.eql(u8, cmd, "rm")) {
            cmdRm(args);
        } else if (std.mem.eql(u8, cmd, "test")) {
            const res = ktest.runAll();
            print("tests: {d} passed, {d} failed\n", .{ res.passed, res.failed });
        } else if (std.mem.eql(u8, cmd, "slabstat")) {
            cmdSlabstat();
        } else if (std.mem.eql(u8, cmd, "env")) {
            cmdEnv();
        } else if (std.mem.eql(u8, cmd, "readelf")) {
            cmdReadelf(args);
        } else if (std.mem.eql(u8, cmd, "cpuid")) {
            cmdCpuid();
        } else if (std.mem.eql(u8, cmd, "acpi")) {
            cmdAcpi();
        } else if (std.mem.eql(u8, cmd, "hexdump")) {
            cmdHexdump(args);
        } else if (std.mem.eql(u8, cmd, "peek")) {
            cmdPeek(args);
        } else if (std.mem.eql(u8, cmd, "poke")) {
            cmdPoke(args);
        } else if (std.mem.eql(u8, cmd, "touch")) {
            cmdTouch(args);
        } else if (std.mem.eql(u8, cmd, "uname")) {
            cmdUname();
        } else if (std.mem.eql(u8, cmd, "history")) {
            cmdHistory();
        } else if (std.mem.eql(u8, cmd, "meminfo")) {
            cmdMeminfo();
        } else if (std.mem.eql(u8, cmd, "phdrs")) {
            cmdPhdrs(args);
        } else if (std.mem.eql(u8, cmd, "sysinfo")) {
            cmdSysinfo();
        } else {
            print("unknown command: {s} (try 'help')\n", .{cmd});
        }
    }
}

fn cmdHelp() void {
    console.write("commands:\n");
    console.write("  help    -- list commands\n");
    console.write("  echo    -- print the given arguments\n");
    console.write("  mem     -- physical frame + heap stats\n");
    console.write("  uptime  -- timer ticks and seconds since boot\n");
    console.write("  ps      -- scheduler / task info\n");
    console.write("  clear   -- clear the screen\n");
    console.write("  reboot  -- reset the machine\n");
    console.write("  date    -- show CMOS RTC date and time\n");
    console.write("  lspci    -- list PCI devices\n");
    console.write("  diskinfo -- ATA disk identity (sectors + model)\n");
    console.write("  ls [path]         -- list directory (default /)\n");
    console.write("  cat <path>        -- print file contents\n");
    console.write("  write <path> <s>  -- write string to file\n");
    console.write("  mkdir <path>      -- create directory\n");
    console.write("  rm <path>         -- remove file or directory\n");
    console.write("  test              -- run kernel self-test harness\n");
    console.write("  slabstat          -- demo slab allocator and print stats\n");
    console.write("  env               -- show kernel build / runtime info\n");
    console.write("  readelf <path>    -- inspect ELF32 header of a VFS file\n");
    console.write("  cpuid             -- show CPUID vendor string and max leaf\n");
    console.write("  acpi              -- search for ACPI RSDP and print address\n");
    console.write("  hexdump <addr> <len> -- hex+ASCII dump of memory (hex args)\n");
    console.write("  peek <addr>       -- read and print u32 at hex address\n");
    console.write("  poke <addr> <val> -- write u32 hex value to hex address\n");
    console.write("  touch <path>      -- create an empty file in the VFS\n");
    console.write("  uname             -- kernel name, version, CPU vendor\n");
    console.write("  history           -- print last entered commands\n");
    console.write("  meminfo           -- detailed memory: frames, heap, slab demo\n");
    console.write("  phdrs <path>      -- walk ELF32 program headers of a VFS file\n");
    console.write("  sysinfo           -- quick summary: CPU, memory, PCI count\n");
}

fn cmdMem() void {
    const s = pmm.stats();
    const free_mib = (s.free * 4) / 1024;
    const total_mib = (s.total * 4) / 1024;
    print("frames: total={d} used={d} free={d}\n", .{ s.total, s.used, s.free });
    print("usable: {d} MiB total, {d} MiB free\n", .{ total_mib, free_mib });
    print("heap:   base=0x{X} size={d} KiB\n", .{ heap.HEAP_BASE, heap.HEAP_SIZE / 1024 });
}

fn cmdUptime() void {
    const t = timer.ticks();
    const h = timer.hz();
    const secs = if (h != 0) t / h else 0;
    print("up {d} ticks ({d} s)\n", .{ t, secs });
}

fn cmdPs() void { print("tasks created: {d} (incl. bootstrap)\n", .{sched.taskCount()}); print("live in ring : {d}\n", .{sched.liveCount()}); console.write("running in boootstrap context (shell)\n"); }