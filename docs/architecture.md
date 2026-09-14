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

