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

## Boot flow

```
boot.s (_start)
  └─ sets up the 16 KiB stack, passes multiboot magic+info to kmain
kmain (main.zig)
  ├─ M0  console.init() — VGA + serial
  ├─ M2  gdt.init(), interrupts.init()
  ├─ M3  pic.init(), timer.init(100), sti
  ├─ M4  pic.clearMask(1)  — keyboard IRQ1 enabled
  ├─ M5  pmm.init(mb_info)
  ├─ M6  paging.init()
  ├─ M7  heap.init(), blockcache.init()
  ├─ M8  sched: cooperative then preemptive demo tasks
  ├─ M10 libk self-test
  ├─ M11 rtc.read(), pci.enumerate()
  ├─ M12 ata.identify(), read/write round-trip
  ├─ M13 vfs.mount(stub_fs), fd open/write/read/close
  ├─ M14 ramfs.init(), tar.unpackInto(initrd)
  ├─ M15 syscall.invoke(.write / .uptime)
  ├─ M16 ktest.runAll()
  └─ M9  shell.run()  ← never returns
```

## Shell commands

```
help              list all commands
echo <args>       print arguments to the console
mem               physical frame + heap statistics
uptime            timer ticks and seconds since boot
ps                scheduler task counts
clear             clear the VGA screen (and send ANSI ESC[2J on serial)
reboot            reset the machine via the 8042 CPU reset line
date              current date and time from the CMOS RTC
lspci             list PCI devices (bus:slot.func vendor:device class)
diskinfo          ATA drive sector count and model string
ls [path]         list directory contents (default /)
cat <path>        print file contents via the VFS
write <path> <s>  write a string into a RamFS file (creates if absent)
mkdir <path>      create a directory entry in RamFS
rm <path>         remove a file or directory from RamFS
test              run the M16 kernel self-test harness
```

## Source layout

