//! Unified console: everything written here goes to BOTH the VGA text buffer
//! and the COM1 serial line, so the same output is visible on a real screen and
//! capturable headlessly during tests.

const serial = @import("serial.zig");
const vga = @import("vga.zig");

pub fn init() void {
    serial.init();
    vga.clear();
}

