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

