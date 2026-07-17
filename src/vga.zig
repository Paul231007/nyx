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

pub fn clear() void {
    var i: usize = 0;
    while (i < WIDTH * HEIGHT) : (i += 1) buffer[i] = cell(' ');
    row = 0;
    col = 0;
}

fn scroll() void {
    var y: usize = 1;
    while (y < HEIGHT) : (y += 1) {
        var x: usize = 0;
        while (x < WIDTH) : (x += 1) {
            buffer[(y - 1) * WIDTH + x] = buffer[y * WIDTH + x];
        }
    }
    var x: usize = 0;
    while (x < WIDTH) : (x += 1) buffer[(HEIGHT - 1) * WIDTH + x] = cell(' ');
}

