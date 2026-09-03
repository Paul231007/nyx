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

`serial.getcNonblock()` returns `?u8`: it reads LSR bit 0 (data ready) and, if set,
reads the RBR. Returns `null` if no byte is waiting. The input subsystem polls this
in `readLine`.

## vga.zig — VGA text console

The VGA text buffer is a `[*]volatile u16` at `0xB8000`. Each cell is a 16-bit word:
the high byte is the attribute (colour) byte and the low byte is the ASCII character.
nyx uses colour `0x0F` (bright white on black) for all output.

`vga.putc(c)` handles:
- `'\n'` — advance row, reset column.
- `'\r'` — reset column only.
- Backspace (0x08) — decrement column, write a space cell.
- All other bytes — write the cell and advance the column.

When `row >= HEIGHT` (25), `scroll()` copies rows 1..24 up by one and blanks the
last row. `vga.clear()` blanks the entire buffer and resets both cursors to (0, 0).

There is no hardware cursor update (no CRTC port writes); the visible cursor is
managed solely by the software row/col counters.

## keyboard.zig — PS/2 keyboard

The PS/2 controller is connected to IRQ1 (vector 33). `keyboard.handleIrq()` is
called from the IRQ1 stub in `interrupts.zig`.

