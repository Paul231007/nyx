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

/// Read the current time from the CMOS RTC.
/// Waits for any in-progress update to complete before sampling.
pub fn read() Time {
    // Wait for the Update-In-Progress flag (status register A, bit 7) to clear.
    var guard: u32 = 0;
    while ((cmosRead(0x0A) & 0x80) != 0 and guard < 1_000_000) : (guard += 1) {}

    const raw_sec = cmosRead(0x00);
    const raw_min = cmosRead(0x02);
    const raw_hour = cmosRead(0x04);
    const raw_day = cmosRead(0x07);
    const raw_month = cmosRead(0x08);
    const raw_year = cmosRead(0x09);

    const regb = cmosRead(0x0B);
    const is_bcd = (regb & 0x04) == 0;

    var t: Time = undefined;
    if (is_bcd) {
        t.sec = fromBcd(raw_sec);
        t.min = fromBcd(raw_min);
        t.hour = fromBcd(raw_hour);
        t.day = fromBcd(raw_day);
        t.month = fromBcd(raw_month);
        t.year = @as(u16, fromBcd(raw_year)) + 2000;
    } else {
        t.sec = raw_sec;
        t.min = raw_min;
        t.hour = raw_hour;
        t.day = raw_day;
        t.month = raw_month;
        t.year = @as(u16, raw_year) + 2000;
    }
    return t;
}
