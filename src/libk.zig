//! libk — freestanding string and numeric helper library.
//! No dynamic allocation; all functions operate on caller-supplied buffers or
//! raw pointers. Safe to call from any kernel context.

const std = @import("std");

/// Copy min(dst.len, src.len) bytes from `src` into `dst`.
pub fn memcpy(dst: []u8, src: []const u8) void {
    const n = @min(dst.len, src.len);
    @memcpy(dst[0..n], src[0..n]);
}


