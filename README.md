# nyx

A small **freestanding x86 (i386) operating-system kernel**, written from scratch in
**Zig 0.15.2** with no libc and no external dependencies. It boots on bare QEMU and
brings the machine up through the classic kernel-bring-up sequence all the way to an
**interactive shell** with a real filesystem, disk driver, syscall layer, and self-test
harness.

```
$ zig build run
================================
  nyx -- a small x86 kernel
================================
nyx: M0 OK
nyx: M2 OK
nyx: M3 OK
...
nyx: M16 OK
================================
  nyx shell -- type 'help'
================================
nyx> help
nyx> mem
frames: total=15933 used=1044 free=14889
usable: 62 MiB total, 58 MiB free
heap:   base=0xD0000000 size=4096 KiB
nyx> echo hello
hello
nyx> date
2026-06-26 14:22:05
nyx> ls
- hello.txt
- motd
nyx> cat /hello.txt
hello nyx
```

## Build & run

Requires `zig` (0.15.2) and `qemu-system-i386`.

```sh
zig build            # builds zig-out/bin/kernel.elf (a multiboot1 ELF)
zig build run        # boots it in QEMU with the serial console on stdio
```

QEMU boots the kernel directly via `-kernel` (multiboot1) — no GRUB or ISO needed.

### Disk image

The ATA driver (M12) and block cache require an IDE disk. The `build.zig` passes:

```
-drive file=nyx.img,if=ide,format=raw
```

Create a blank image before the first run if it does not exist:

```sh
dd if=/dev/zero of=nyx.img bs=512 count=65536  # 32 MiB
```

### Headless testing

`tools/qrun.sh` boots the kernel with no display, captures the serial output, and
times out so a hang or triple-fault can never wedge the harness. The shell reads
from both the PS/2 keyboard and COM1, so it is fully driveable headlessly:

```sh
bash tools/qrun.sh zig-out/bin/kernel.elf "help\nuptime\necho hi\n" 12
```

## Bring-up milestones (M0–M16)

Each milestone is validated inline in `kmain` before the next one begins:

| Stage | Subsystem |
|-------|-----------|
| **M0** | Multiboot1 boot, 16 KiB stack, VGA text console (`0xB8000`) + COM1 serial, unified console |
| **M2** | Flat **GDT**, 256-entry **IDT**, all 32 CPU exception handlers (register dump + recover/halt) |
| **M3** | **8259 PIC** remap, hardware IRQ dispatch, **PIT** timer at 100 Hz, tick counter |
| **M4** | **PS/2 keyboard** (IRQ1, scancode set 1 → ASCII) + serial input, shared ring buffer + line reader |
| **M5** | **Physical memory manager** — parses the multiboot memory map, 4 KiB frame bitmap allocator |
| **M6** | **Paging** — page directory + tables, identity-maps 64 MiB RAM, enables `CR0.PG`, page-fault handler |
| **M7** | **Kernel heap** — first-fit free-list allocator exposed as a `std.mem.Allocator` |
| **M8** | **Scheduler** — kernel threads with 16 KiB stacks, cooperative round-robin + timer preemption |
| **M9** | **Interactive shell** — 16 built-in commands, reads from keyboard + serial |
| **M10** | **libk** — freestanding string/numeric helpers (`streq`, `parseUint`, `parseHex`, `memcpy`, `HexDump`) |
| **M11** | **CMOS RTC** (date/time) + **PCI** bus enumeration (config mechanism #1) |
| **M12** | **ATA PIO** disk driver — IDENTIFY, 28-bit LBA read/write, write-through **block cache** |
| **M13** | **VFS** layer — fd table (16 slots), vtable-dispatched `open`/`read`/`write`/`seek`/`readdir`/`close` |
| **M14** | **RamFS** + **tar initrd** — in-memory filesystem (64 entries), ustar unpacker, `@embedFile` initrd |
| **M15** | **int 0x80 syscalls** — `write`, `read`, `open`, `close`, `getpid`, `uptime` |
| **M16** | **Kernel self-test harness** — 6 named cases covering libk, PMM, heap, VFS, ATA, and syscalls |

