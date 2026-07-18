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


