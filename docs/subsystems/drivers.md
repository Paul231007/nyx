# Drivers

All nyx drivers use port-mapped I/O via the helpers in `io.zig` (`inb`, `outb`,
`inw`, `outw`, `inl`, `outl`). There are no memory-mapped MMIO drivers (VGA is the
sole exception — its framebuffer is at the fixed physical address `0xB8000`). None
of the drivers uses DMA or interrupts for data transfer except the keyboard and
timer, which are purely interrupt-driven.

## serial.zig — COM1 UART

COM1 is used as the headless console: QEMU's `-serial stdio` maps it to the host's
stdin/stdout, so the kernel is fully driveable by piping bytes from the shell.

`serial.init()` programmes the 16550 UART at I/O base `0x3F8`:
- DLAB set, divisor = 3 → 38400 baud.
- 8 data bits, no parity, 1 stop bit.
- The FIFO is deliberately left **disabled** (FCR = 0x00). With the FIFO off, QEMU
  flow-controls the receiver by holding the next byte in the chardev until the
  kernel reads the single-byte RBR, so no piped input is ever dropped.

`serial.putc(c)` spin-waits on the transmit-empty bit (LSR bit 5) before writing.
A `'\n'` is expanded to `'\r\n'` for VT100 terminals.

