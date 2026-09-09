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

fn cmdPs() void {
    print("tasks created: {d} (incl. bootstrap)\n", .{sched.taskCount()});
    print("live in ring : {d}\n", .{sched.liveCount()});
    console.write("running in bootstrap context (shell)\n");
}

fn cmdDate() void {
    const t = rtc.read();
    var fbuf: [32]u8 = undefined;
    console.write(timefmt.fmtFull(&fbuf, t));
    console.write("\n");
    var ibuf: [24]u8 = undefined;
    console.write(timefmt.fmtIso(&ibuf, t));
    console.write("\n");
    var wbuf: [12]u8 = undefined;
    console.write(timefmt.fmtWeekday(&wbuf, t));
    console.write("\n");
}

fn cmdLspci() void {
    var pci_devs: [32]pci.Device = undefined;
    const npci = pci.enumerate(&pci_devs);
    var idx: usize = 0;
    while (idx < npci) : (idx += 1) {
        const d = pci_devs[idx];
        const vname = pci.vendorNameOf(d.vendor);
        const cname = pci.classNameOf(d.class, d.subclass);
        print("{d:0>2}:{d:0>2}.{d}  {X:0>4}:{X:0>4}  [{s}]\n", .{
            d.bus, d.slot, d.func, d.vendor, d.device, vname,
        });
        print("         {s}\n", .{cname});
    }
    if (npci == 0) console.write("no PCI devices found\n");
}

fn cmdDiskinfo() void {
    if (ata.identify()) |info| {
        print("sectors : {d}\n", .{info.sectors});
        // Trim trailing spaces from the model string before printing
        var mlen: usize = info.model.len;
        while (mlen > 0 and info.model[mlen - 1] == ' ') : (mlen -= 1) {}
        console.write("model   : ");
        console.write(info.model[0..mlen]);
        console.write("\n");
    } else {
        console.write("no ATA disk detected\n");
    }
}

fn cmdLs(args: []const u8) void {
    const path = if (trim(args).len > 0) trim(args) else "/";
    const fd = vfs.open(path) orelse {
        print("ls: not found: {s}\n", .{path});
        return;
    };
    var idx: usize = 0;
    while (vfs.readdir(fd, idx)) |node| : (idx += 1) {
        const name = node.name[0..node.name_len];
        const kind_ch: u8 = if (node.kind == .dir) 'd' else '-';
        print("{c} {s}\n", .{ kind_ch, name });
    }
    if (idx == 0) console.write("(empty)\n");
    vfs.close(fd);
}

fn cmdCat(args: []const u8) void {
    const path = trim(args);
    if (path.len == 0) {
        console.write("cat: need a path\n");
        return;
    }
    const fd = vfs.open(path) orelse {
        print("cat: not found: {s}\n", .{path});
        return;
    };
    var buf: [256]u8 = undefined;
    var n = vfs.read(fd, &buf);
    while (n > 0) {
        console.write(buf[0..n]);
        n = vfs.read(fd, &buf);
    }
    vfs.close(fd);
}

fn cmdWrite(args: []const u8) void {
    const sp = std.mem.indexOfScalar(u8, args, ' ') orelse {
        console.write("write: usage: write <path> <content>\n");
        return;
    };
    const path = trim(args[0..sp]);
    const content = trim(args[sp + 1 ..]);
    if (path.len == 0) {
        console.write("write: need a path\n");
        return;
    }
    // Create if not already present.
    _ = ramfs.create(path, .file);
    const fd = vfs.open(path) orelse {
        print("write: open failed: {s}\n", .{path});
        return;
    };
    _ = vfs.write(fd, content);
    vfs.close(fd);
    print("wrote {d} bytes to {s}\n", .{ content.len, path });
}

fn cmdMkdir(args: []const u8) void {
    const path = trim(args);
    if (path.len == 0) {
        console.write("mkdir: need a path\n");
        return;
    }
    if (ramfs.create(path, .dir) != null) {
        print("mkdir: created {s}\n", .{path});
    } else {
        print("mkdir: failed (table full?): {s}\n", .{path});
    }
}

fn cmdRm(args: []const u8) void {
    const path = trim(args);
    if (path.len == 0) {
        console.write("rm: need a path\n");
        return;
    }
    if (ramfs.remove(path)) {
        print("rm: removed {s}\n", .{path});
    } else {
        print("rm: not found: {s}\n", .{path});
    }
}

/// Demo the slab allocator: initialise a small slab, allocate a handful of
/// objects, print live/capacity stats, then free them all.
fn cmdSlabstat() void {
    var sl = slab.Slab.init(heap.allocator(), 32, 8, 4);
    defer sl.deinit();
    console.write("slab: obj_size=32 obj_align=8 per_chunk=4\n");
    var ptrs: [6][*]u8 = undefined;
    for (&ptrs) |*pp| {
        pp.* = sl.alloc() orelse {
            console.write("slabstat: alloc failed\n");
            return;
        };
    }
    const st1 = sl.stats();
    print("slab: live={d}  capacity={d}  (2 chunks grown)\n", .{ st1.live, st1.capacity });
    for (ptrs) |pp| sl.free(pp);
    const st2 = sl.stats();
    print("slab: after free: live={d}  capacity={d}\n", .{ st2.live, st2.capacity });
}

/// Print static kernel build and runtime information.
fn cmdEnv() void {
    console.write("nyx kernel info:\n");
    console.write("  arch     : i386 (x86 protected mode, Multiboot 1)\n");
    console.write("  compiler : Zig 0.15.2 (freestanding-i386)\n");
    console.write("  heap     : 4 MiB first-fit free-list @ 0xD0000000\n");
    console.write("  console  : VGA text mode + serial COM1\n");
    console.write("  fs       : RamFS + tar initrd (M14)\n");
    console.write("  sched    : co-op + preemptive round-robin (M8)\n");
    console.write("  syscall  : int 0x80 dispatch (M15)\n");
    console.write("  slab     : M17 fixed-size slab allocator\n");
}

/// Inspect an ELF32 file from the VFS and print key header fields.
fn cmdReadelf(args: []const u8) void {
    const path = trim(args);
    if (path.len == 0) {
        console.write("readelf: usage: readelf <path>\n");
        return;
    }
    const fd = vfs.open(path) orelse {
        print("readelf: not found: {s}\n", .{path});
        return;
    };
    var buf: [512]u8 = undefined;
    const n = vfs.read(fd, &buf);
    vfs.close(fd);
    if (n == 0) {
        console.write("readelf: file is empty\n");
        return;
    }
    const hdr = elf.parse(buf[0..n]) catch |err| {
        switch (err) {
            error.BadMagic  => console.write("readelf: not an ELF file\n"),
            error.NotElf32  => console.write("readelf: not ELF32\n"),
        }
        return;
    };
    print("  class   : ELF{d}\n", .{if (hdr.class == 1) @as(u32, 32) else @as(u32, 64)});
    print("  machine : {s}\n", .{elf.machineName(hdr.machine)});
    print("  entry   : 0x{X}\n", .{hdr.entry});
    print("  phoff   : 0x{X}\n", .{hdr.phoff});
    print("  phnum   : {d}\n", .{hdr.phnum});
    print("  shnum   : {d}\n", .{hdr.shnum});
}


