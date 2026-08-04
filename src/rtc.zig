//! CMOS RTC driver — reads the real-time clock via I/O ports 0x70/0x71.

const io = @import("io.zig");

/// Calendar date and time as read from the CMOS RTC.
pub const Time = struct {
    year: u16,
    month: u8,
    day: u8,
    hour: u8,
    min: u8,
    sec: u8,
};

