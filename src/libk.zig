//! libk — freestanding string and numeric helper library.
//! No dynamic allocation; all functions operate on caller-supplied buffers or
//! raw pointers. Safe to call from any kernel context.

const std = @import("std");

/// Copy min(dst.len, src.len) bytes from `src` into `dst`.
pub fn memcpy(dst: []u8, src: []const u8) void {
    const n = @min(dst.len, src.len);
    @memcpy(dst[0..n], src[0..n]);
}

/// Fill every byte of `dst` with `val`.
pub fn memset(dst: []u8, val: u8) void {
    @memset(dst, val);
}

/// Return true when `a` and `b` are byte-for-byte identical.
pub fn streq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    return std.mem.eql(u8, a, b);
}

