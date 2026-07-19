//! timefmt — human-friendly date/time formatter for the nyx kernel.
//!
//! Operates entirely on stack-allocated buffers; no heap required.
//! Accepts `rtc.Time` values and formats them into caller-supplied slices.
//! Also provides weekday computation via Tomohiko Sakamoto's algorithm and
//! Unix epoch helpers for sorting and delta calculations.

const std = @import("std");
const rtc = @import("rtc.zig");

// ---- month and day name tables ------------------------------------------------

/// Full English month names, 1-indexed (index 0 is unused).
pub const MONTH_NAME = [_][]const u8{
    "???",       // 0 — unused sentinel
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December",
};

/// Abbreviated month names (3 letters), 1-indexed.
pub const MONTH_ABBR = [_][]const u8{
    "???",
    "Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
};

/// Days in each month for a common year, 1-indexed.
const DAYS_IN_MONTH = [_]u8{
    0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31,
};

/// Full English weekday names, 0 = Sunday.
pub const DAY_NAME = [_][]const u8{
    "Sunday",
    "Monday",
    "Tuesday",
    "Wednesday",
    "Thursday",
    "Friday",
    "Saturday",
};

/// Abbreviated weekday names (3 letters), 0 = Sunday.
pub const DAY_ABBR = [_][]const u8{
    "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat",
};

// ---- calendar helpers --------------------------------------------------------

/// Return true when `year` is a Gregorian leap year.
pub fn isLeapYear(year: u16) bool {
    return (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0);
}

/// Return the number of days in `month` of `year` (1-indexed month).
pub fn daysInMonth(year: u16, month: u8) u8 {
    if (month < 1 or month > 12) return 0;
    if (month == 2 and isLeapYear(year)) return 29;
    return DAYS_IN_MONTH[month];
}

/// Compute the day of the week for the given date using Tomohiko Sakamoto's
/// algorithm.  Returns 0 = Sunday … 6 = Saturday.
pub fn weekday(year: u16, month: u8, day: u8) u8 {
    // Sakamoto's table: offsets for months in a standard year.
    const t = [_]i32{ 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4 };
    var y: i32 = @as(i32, year);
    const m: i32 = @as(i32, month);
    const d: i32 = @as(i32, day);
    if (m < 3) y -= 1;
    const sum: i32 = y + @divFloor(y, 4) - @divFloor(y, 100) + @divFloor(y, 400) + t[@intCast(m - 1)] + d;
    return @truncate(@as(u32, @intCast(@mod(sum, @as(i32, 7)))));
}

/// Return the day-of-year (1 = Jan 1) for the given date.
pub fn dayOfYear(year: u16, month: u8, day: u8) u16 {
    var doy: u16 = 0;
    var m: u8 = 1;
    while (m < month) : (m += 1) {
        doy += daysInMonth(year, m);
    }
    doy += day;
    return doy;
}

// ---- epoch helpers -----------------------------------------------------------

/// Days since 1970-01-01 up to the start of `year` (proleptic Gregorian).
/// Works for years >= 1970.
pub fn daysSinceEpochYear(year: u16) u32 {
    if (year < 1970) return 0;
    const y: u32 = year - 1970;
    // Leap years between 1970 and year-1 (exclusive upper bound).
    const base_year: u32 = 1970;
    var leaps: u32 = 0;
    var ly: u32 = base_year;
    while (ly < year) : (ly += 1) {
        if (isLeapYear(@truncate(ly))) leaps += 1;
    }
    return y * 365 + leaps;
}

