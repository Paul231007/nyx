# nyx — Architecture

nyx is a monolithic, single-address-space x86 kernel. There is no user/kernel
privilege split, no paging protection between subsystems, and no SMP. Every piece
of code runs in ring-0 protected mode. The design is intentionally layered: each
milestone depends only on the ones below it, so the bring-up sequence also doubles
as an integration test.

## Layers at a glance

```
┌──────────────────────────────────────────────────────────────┐
│  Shell (shell.zig)                                           │
│  Syscall interface (syscall.zig, int 0x80)                   │
├──────────────────────────────────────────────────────────────┤
│  VFS (vfs.zig) ──► RamFS (ramfs.zig) ◄── tar initrd         │
├──────────────────────────────────────────────────────────────┤
│  Scheduler (sched.zig) — cooperative + timer preemption      │
├──────────────────────────────────────────────────────────────┤
│  Heap (heap.zig)                                             │
│  Paging (paging.zig)           Block cache (blockcache.zig)  │
│  PMM (pmm.zig)                                               │
├──────────────────────────────────────────────────────────────┤
│  Drivers: serial · vga · keyboard · PIT · RTC · PCI · ATA   │
├──────────────────────────────────────────────────────────────┤
│  Interrupt infrastructure: GDT · IDT · PIC (8259)           │
├──────────────────────────────────────────────────────────────┤
│  Boot (boot.s) — multiboot1 header, stack, jump to kmain    │
└──────────────────────────────────────────────────────────────┘
```

## Boot sequence

### boot.s → kmain

`boot.s` defines the multiboot1 header and the `_start` entry point. It sets the
stack pointer to the top of a 16 KiB `.bss` array and calls `kmain(magic, info)`
in C calling convention. No IDT or GDT is loaded at this point; the CPU is still
running with whatever the bootloader left behind.

### M0 — console

`kmain` calls `console.init()`, which calls `vga.clear()` and `serial.init()`. From
this point every `console.write()` call fans out to both the VGA text buffer at
`0xB8000` and COM1 at 38400 baud. The serial port is the headless test interface.

### M2 — GDT and IDT

`gdt.init()` installs a flat three-descriptor GDT (null, 32-bit code, 32-bit data)
and reloads `cs`/`ds`/`ss`/`es`/`fs`/`gs` via a far jump. `interrupts.init()` fills
all 256 IDT gates: the first 32 as exception stubs, gates 32–47 as hardware IRQ
stubs, and gate 0x80 as the syscall gate. The exception stubs print a register dump
and either `iret` (for recoverable faults like the int 3 self-test) or halt.

### M3 — PIC and PIT

`pic.init()` remaps the 8259 master/slave PIC so IRQs 0–15 map to IDT vectors 32–47
(above the CPU exception range). `timer.init(100)` programs PIT channel 0 for
100 Hz in mode 3 (square wave). After `sti`, the IRQ0 handler fires every 10 ms,
calls `timer.tick()` to increment the tick counter, and (when preemption is enabled)
calls `sched.onTick()` to force a context switch.

### M4 — Input

IRQ1 is unmasked with `pic.clearMask(1)`. Each keyboard interrupt calls
`keyboard.handleIrq()`, which reads a scancode from port `0x60`, translates it
via the US-QWERTY tables in `keyboard.zig`, and pushes the ASCII byte into the
shared ring buffer in `input.zig`. The serial driver's `getcNonblock()` is polled
from the same `input.readLine()` function, so the shell works identically whether
driven by a physical keyboard or by piping bytes into QEMU's `-serial stdio`.

### M5 — Physical Memory Manager

`pmm.init(mb_info)` walks the multiboot1 memory map (flag bit 6 in the info struct).
It starts by marking every bit in its 128 KiB bitmap as used, then walks the mmap
entries: for each `type=1` (available RAM) region it clears the corresponding frame
bits and counts usable frames. It then re-reserves the first 1 MiB, the kernel image
(bounded by the linker symbols `kernel_start`/`kernel_end`), and the multiboot info
struct itself. `allocFrame()` returns the physical address of a free 4 KiB frame by
scanning the bitmap; `freeFrame()` clears the bit with a double-free guard.

### M6 — Paging

`paging.init()` allocates a page directory and 16 page tables (one per 4 MiB) from
the PMM, identity-maps the first 64 MiB with present+RW entries, loads the page
directory physical address into CR3, and sets bit 31 of CR0. After this call every
virtual address in [0, 64 MiB) is a 1:1 map to physical memory. The `map(virt,
phys, flags)` function handles arbitrary single-page mappings (used by the heap to
map its 4 MiB window at `0xD0000000`). `translate(virt)` walks the tables and is
used by the M6 self-test.

### M7 — Heap

`heap.init()` maps 1024 frames from the PMM into `[0xD0000000, 0xD0400000)` (4 MiB)
via `paging.map()`. The window is seeded with a single free `Block` header covering
the whole range. `heapAlloc` is a first-fit allocator that honours arbitrary
alignment by padding between the header and the user pointer and storing a
back-pointer in the `usize` slot immediately before the user pointer. `heapFree`
marks the block free and coalesces with its physically-adjacent neighbours. The
`allocator()` function wraps the allocator in a `std.mem.Allocator` vtable so Zig
standard-library types like `std.ArrayList` work without modification.

The block cache (`blockcache.init`) is initialised immediately after the heap since
it allocates its 16 × 512-byte sector buffers from the heap allocator.

### M8 — Scheduler

`sched.init()` allocates a bootstrap `Task` node representing `kmain`'s own stack.
`spawn(f)` allocates a heap `Task` struct and a 16 KiB stack, hand-crafts the
initial stack so `switchContext`'s first `ret` lands in `taskTrampoline`, and links
the node into a singly-linked circular ring just before the bootstrap node.

`switchContext` (inlined assembly) saves `ebp/ebx/esi/edi` on the old stack, writes
the stack pointer into `old_esp_ptr`, loads `new_esp` into `esp`, and restores the
saved registers from the new stack. `yield()` picks the next non-done node in the
ring and calls `switchContext`. `runUntilIdle()` drives `yield()` until all
non-bootstrap tasks are done. Timer preemption is enabled by setting the `preempt`
flag; `sched.onTick()` (called from the IRQ0 handler) then calls `yield()` directly.

### M10 — libk

A freestanding utility library: `streq`, `strlen`, `memcpy`, `memset`,
`parseUint` (base 10 or 16), `parseHex` (accepts `0x` prefix), and `HexDump` (16-
byte rows with hex + ASCII columns). No dynamic allocation.

### M11 — RTC and PCI

`rtc.read()` reads the six CMOS time registers (0x00/0x02/0x04/0x07/0x08/0x09) via
ports 0x70/0x71, waiting for the Update-In-Progress flag to clear. It converts BCD
to binary when status register B bit 2 is clear (the common QEMU default).

`pci.enumerate(out)` brute-forces all 256 buses × 32 slots × 8 functions using PCI
configuration mechanism #1 (ports 0xCF8/0xCFC). For each present function it reads
the vendor/device word and the class/subclass byte and stores a `Device` record.
`pci.find(class, subclass)` is a targeted variant used elsewhere.

### M12 — ATA and Block Cache

`ata.zig` drives the primary ATA bus (base 0x1F0) in polling PIO mode (no
interrupts). `identify()` issues command 0xEC, polls BSY/DRQ, reads 256 words, and
extracts the 28-bit LBA sector count (words 60–61) and the byte-swapped model string
(words 27–46). `readSectors` (command 0x20) and `writeSectors` (command 0x30) handle
multi-sector transfers one sector at a time; writes are followed by CACHE FLUSH
(0xE7). QEMU requires a `-drive if=ide` argument; without it `identify()` returns
null and M12 reports FAIL.

`blockcache.zig` sits between the VFS and the ATA driver. It provides 16 direct-
mapped slots keyed by `lba % 16`. A read hit avoids the disk entirely; a miss loads
the sector. Writes go to disk immediately (write-through), then update the slot.

### M13 — VFS

`vfs.zig` defines two types: `Node` (an abstract file-system object with a name,
kind, size, and an opaque `impl` pointer) and `FileSystem` (a vtable of four
function pointers: `open`, `read`, `write`, `readdir`). A single filesystem is
mounted at a time via `mount()`. The fd table has 16 slots; each slot tracks the
open `Node` and the current byte offset. `read`/`write` advance the offset and
`seek` resets it. `readdir` delegates index-based enumeration to the backing fs.

### M14 — RamFS and initrd

`ramfs.zig` backs the VFS with a fixed 64-entry array. Each entry holds a 128-byte
path, a 4 KiB inline data buffer, and a `vfs.Node`. The root (`/`) is pre-seeded
at slot 0 by `ramfs.init()`. `ramfsReaddir` implements directory listing by scanning
all entries for paths that are direct children of the requested directory path.
`ramfs.create()` either returns an existing entry or allocates a new one; `remove()`
marks the slot unused.

`tar.zig` parses a POSIX ustar archive embedded via `@embedFile("initrd.tar")`.
`unpackInto()` walks 512-byte headers, parses the octal size field, normalises the
path (strips `./` prefix, prepends `/`), calls `ramfs.create()` for each entry, and
writes file data through the vtable. Two consecutive zero blocks signal end-of-
archive.

### M15 — Syscalls

The IDT gate at index 0x80 is wired to the int-0x80 ISR in `interrupts.zig`, which
saves the caller's state and calls `syscall.dispatch(nr, a, b, c)`. Six syscall
numbers are defined in the `Nr` enum: `write` (1), `read` (2), `open` (3), `close`
(4), `getpid` (5), `uptime` (6). The `invoke()` function issues `int $0x80` via
inline assembly (eax=nr, ebx/ecx/edx=args), making it callable from ring-0 kernel
code as a self-test.

### M16 — Self-test harness

`ktest.runAll()` runs six named cases in order:
- `libk_parse` — parseUint, parseHex, streq
- `pmm_roundtrip` — alloc + alignment check + free restores count
- `heap_alloc` — pattern write/verify through the Allocator interface
- `vfs_roundtrip` — create /ktest.tmp, write "ktest", seek 0, read back
- `ata_sector` — write known pattern to sector 5, read back, compare
- `syscall_uptime` — int 0x80 uptime call returns a positive tick count

`ktest.runAll()` runs automatically during boot (M16 check) and is also exposed as
the `test` shell command for interactive re-runs.

### M9 — Shell

`shell.run()` is the final call in `kmain` and never returns. It prints the welcome
banner, then loops: prints `nyx> `, calls `input.readLine()` (which blocks on the
ring buffer), splits the first token as the command name, and dispatches to the
appropriate handler function. Unknown commands print a hint.

## Memory map

```
0x00000000 – 0x000FFFFF   First 1 MiB (BIOS, IVT, VGA buffer at 0xB8000)
0x00100000 – 0x???       Kernel ELF image (loaded at 1 MiB by linker.ld)
                         PMM bitmap (~128 KiB, in .bss)
                         Boot stack (16 KiB, in .bss)
0x00400000 – 0x03FFFFFF  Available RAM, managed by PMM
0xD0000000 – 0xD03FFFFF  Kernel heap (4 MiB, mapped by paging.init via PMM)
0xE0000000              Test mapping used by M6 paging probe
```

## Interrupt routing

