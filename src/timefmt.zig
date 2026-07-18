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


