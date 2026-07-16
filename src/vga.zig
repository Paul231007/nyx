//! 80x25 VGA text-mode console at 0xB8000.

const WIDTH: usize = 80;
const HEIGHT: usize = 25;
const COLOR: u8 = 0x0F; // bright white on black

const buffer: [*]volatile u16 = @ptrFromInt(0xB8000);

