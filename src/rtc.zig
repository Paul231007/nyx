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

/// Read a single CMOS register.
inline fn cmosRead(reg: u8) u8 {
    io.outb(0x70, reg);
    return io.inb(0x71);
}

/// Convert a BCD byte to binary.
inline fn fromBcd(v: u8) u8 {
    return (v >> 4) * 10 + (v & 0x0F);
}


