# Shell, syscalls, and self-tests

## shell.zig — Interactive command shell (M9)

`shell.run()` is the final call in `kmain` and never returns. It is the interactive
endpoint of the kernel: a classic read-eval-print loop over the unified input ring.

### Command loop

```
shell.run()
  while true:
    console.write("nyx> ")
    n = input.readLine(&line)
    text = trim(line[0..n])
    if text is empty: continue
    split text into cmd (first token) and args (remainder)
    dispatch to handler or print "unknown command"
```

`trim()` strips leading/trailing ASCII whitespace using `std.mem.trim`. The split
finds the first space with `std.mem.indexOfScalar`. This means commands like
`write /foo bar baz` pass `"/foo bar baz"` as `args`, and individual handlers do
their own secondary splits as needed (`cmdWrite` splits at the first space to
separate path from content).

### Built-in commands

| Command | Handler | Description |
|---------|---------|-------------|
| `help` | `cmdHelp()` | Prints the command list |
| `echo <args>` | inline | `console.write(args)` + newline |
| `mem` | `cmdMem()` | `pmm.stats()` + `heap.HEAP_BASE/HEAP_SIZE` |
| `uptime` | `cmdUptime()` | `timer.ticks()` and ticks / `timer.hz()` |
| `ps` | `cmdPs()` | `sched.taskCount()` and `sched.liveCount()` |
| `clear` | inline | `vga.clear()` + ANSI `\x1b[2J\x1b[H` on serial |
| `reboot` | inline | `io.outb(0x64, 0xFE)` — pulse 8042 CPU reset line |
| `date` | `cmdDate()` | `rtc.read()` formatted as ISO 8601 datetime |
| `lspci` | `cmdLspci()` | `pci.enumerate()` + formatted print per device |
| `diskinfo` | `cmdDiskinfo()` | `ata.identify()` — sectors and model string |
| `ls [path]` | `cmdLs()` | `vfs.open(path)` then `vfs.readdir()` loop |
| `cat <path>` | `cmdCat()` | `vfs.open()` + `vfs.read()` loop |
| `write <path> <s>` | `cmdWrite()` | `ramfs.create()` + `vfs.open()` + `vfs.write()` |
| `mkdir <path>` | `cmdMkdir()` | `ramfs.create(path, .dir)` |
| `rm <path>` | `cmdRm()` | `ramfs.remove(path)` |
| `test` | inline | `ktest.runAll()` |

### Filesystem commands

`cmdLs(args)` calls `vfs.open(path)` (defaulting to `"/"`) and iterates
`vfs.readdir(fd, idx)` from `idx = 0` until it returns `null`. Each node is printed
with a leading `'d'` or `'-'` flag.

`cmdCat(path)` opens the file and loops calling `vfs.read(fd, &buf)` until it
returns 0, writing each chunk to the console.

`cmdWrite(args)` splits `args` at the first space to get `path` and `content`. It
calls `ramfs.create(path, .file)` to ensure the entry exists (idempotent), then
opens it via the VFS and writes the content string. The RamFS `write` vtable
function overwrites from offset 0 (seek behaviour: the newly opened fd has offset 0).

`cmdMkdir` and `cmdRm` delegate directly to `ramfs.create` and `ramfs.remove`
without going through the VFS (no fd is needed for these metadata operations).

### Reboot

`reboot` writes `0xFE` to the PS/2 controller command port (`0x64`). This pulses the
CPU reset line, which causes QEMU and real x86 hardware to perform a warm reset.

## syscall.zig — int 0x80 interface (M15)

### Kernel side: `syscall.dispatch`

The IDT gate at vector 0x80 is wired to the int-0x80 ISR in `interrupts.zig`.
The ISR saves the full register set, extracts `eax/ebx/ecx/edx`, and calls
`syscall.dispatch(nr, a, b, c)`, which is a tagged switch on the `Nr` enum:

```zig
pub const Nr = enum(u32) {
    write  = 1,   // a=ptr, b=len → write to console
    read   = 2,   // a=fd,  b=bufptr, c=len → vfs.read
    open   = 3,   // a=path_ptr, b=path_len → vfs.open → fd
    close  = 4,   // a=fd → vfs.close
    getpid = 5,   // always returns 1 (single-process kernel)
    uptime = 6,   // returns timer.ticks()
};
```

`write` takes a virtual address and length and calls `console.write`. `read` and
`open`/`close` delegate to the VFS layer. `getpid` is a stub returning 1. `uptime`
returns `timer.ticks()` cast to `usize`.

### Caller side: `syscall.invoke`

```zig
pub fn invoke(nr: Nr, a: usize, b: usize, c: usize) usize
```

Implemented entirely in inline assembly:

```
mov @intFromEnum(nr), %eax
mov a, %ebx
mov b, %ecx
mov c, %edx
int $0x80
→ return value in %eax
```

`invoke` is callable from ring-0 kernel code (the M15 self-test uses it) and would
work equally from ring-3 user code once privilege-level switching is added.

## ktest.zig — Kernel self-test harness (M16)

`ktest.zig` provides a lightweight test runner. Each test is a named `Case`:

```zig
pub const Case = struct {
    name: []const u8,
    run:  *const fn () bool,
};
```

`runAll()` iterates the static `cases` array, calls each `run()` function, prints
`[PASS]` or `[FAIL]` per case, and returns a `Result{ passed, failed }`.

### Registered test cases

1. **`libk_parse`** — Exercises `libk.parseUint("255", 10)`, `libk.parseHex("0xCAFE")`,
   and `libk.streq("ab", "ab")`. All must return expected values.

2. **`pmm_roundtrip`** — Calls `pmm.allocFrame()`, checks the returned address is
   4 KiB-aligned (`frame & 0xFFF == 0`), frees the frame, and verifies that
   `pmm.stats().free` returns to its pre-allocation value.

3. **`heap_alloc`** — Allocates 64 bytes via `heap.allocator().alloc(u8, 64)`,
   writes a pattern (`idx ^ 0xA5`), verifies each byte, and frees the buffer.

