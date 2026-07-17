//! 80x25 VGA text-mode console at 0xB8000.

const WIDTH: usize = 80;
const HEIGHT: usize = 25;
const COLOR: u8 = 0x0F; // bright white on black

const buffer: [*]volatile u16 = @ptrFromInt(0xB8000);

var row: usize = 0;
var col: usize = 0;

fn cell(c: u8) u16 {
    return (@as(u16, COLOR) << 8) | c;
}

