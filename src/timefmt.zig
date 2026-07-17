//! timefmt — human-friendly date/time formatter for the nyx kernel.
//!
//! Operates entirely on stack-allocated buffers; no heap required.
//! Accepts `rtc.Time` values and formats them into caller-supplied slices.
//! Also provides weekday computation via Tomohiko Sakamoto's algorithm and
//! Unix epoch helpers for sorting and delta calculations.

const std = @import("std");
const rtc = @import("rtc.zig");


