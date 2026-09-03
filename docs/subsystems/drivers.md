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

On each interrupt, one scancode byte is read from data port `0x60`. The handler:
1. Skips the extended `0xE0` byte and the byte that follows it.
2. Detects break codes (bit 7 set): only shift-key releases are acted on.
3. Translates make codes via a 89-entry `map[]` (unshifted) or `map_shift[]`
   (shifted) US-QWERTY table. Zero entries in the table are non-printable and
   are silently dropped.
4. Pushes the resulting ASCII byte into the shared input ring via `input.push(ch)`.

The shift state is a single `var shift: bool` tracking left or right shift. Caps
Lock, Num Lock, and function keys are not handled.

## input.zig — Shared ring buffer

`input.zig` provides a single-producer / single-consumer ring buffer that merges
keyboard and serial input. `input.push(ch)` (called from the keyboard IRQ handler)
writes one byte; it is safe to call from an interrupt context because the ring
write is a single indexed store with a modular increment.

`input.readLine(buf)` is the blocking line reader used by the shell. It polls:
1. `serial.getcNonblock()` for bytes from COM1.
2. The ring buffer (keyboard) for pending bytes.

Backspace is echoed and removes the last character from the accumulator. `'\n'` or
`'\r'` ends the line. The function blocks (busy-polling with `hlt` between
iterations) until a newline arrives.

## timer.zig — PIT channel 0

`timer.init(hz)` programmes the 8253/8254 PIT channel 0 for the requested frequency
using mode 3 (square wave), lo/hi byte access (command byte `0x36`). The divisor is
`PIT_FREQ / hz` where `PIT_FREQ = 1193182`. At 100 Hz the divisor is 11931.

`timer.tick()` is called by the IRQ0 handler and increments a `u64` counter with
wrapping arithmetic. `timer.ticks()` returns the current count; `timer.hz()` returns
the configured frequency (used by `cmdUptime` to convert ticks to seconds).

The IRQ0 handler also calls `sched.onTick()`, which calls `sched.yield()` if timer
preemption is enabled.

## rtc.zig — CMOS real-time clock

The CMOS RTC is accessed via index/data ports `0x70`/`0x71`. `cmosRead(reg)` writes
the register index to port `0x70` and reads the value from `0x71`.

`rtc.read()` returns a `Time` struct with year, month, day, hour, min, sec. It first
waits for the Update-In-Progress flag (status register A, bit 7) to clear, then
reads the six time registers. It checks status register B bit 2 to decide whether
the values are BCD (common QEMU default) or binary; `fromBcd()` converts BCD to
binary. The year is always adjusted by +2000.

The shell `date` command calls `rtc.read()` on each invocation; there is no caching.

