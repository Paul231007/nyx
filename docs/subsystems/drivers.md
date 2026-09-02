# Drivers

All nyx drivers use port-mapped I/O via the helpers in `io.zig` (`inb`, `outb`,
`inw`, `outw`, `inl`, `outl`). There are no memory-mapped MMIO drivers (VGA is the
sole exception — its framebuffer is at the fixed physical address `0xB8000`). None
of the drivers uses DMA or interrupts for data transfer except the keyboard and
timer, which are purely interrupt-driven.

