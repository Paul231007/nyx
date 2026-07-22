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

/// Return the length of the null-terminated C string `s` (sentinel not counted).
pub fn strlen(s: [*:0]const u8) usize {
    var i: usize = 0;
    while (s[i] != 0) : (i += 1) {}
    return i;
}

/// Parse `s` as an unsigned integer in base 10 or 16.
/// Returns null when `s` is empty or any character is not a valid digit for
/// the requested base.  Base values other than 10 and 16 return null.
pub fn parseUint(s: []const u8, base: u8) ?u64 {
    if (s.len == 0) return null;
    var result: u64 = 0;
    for (s) |c| {
        const digit: u64 = switch (base) {
            10 => blk: {
                if (c >= '0' and c <= '9') break :blk c - '0';
                return null;
            },
            16 => blk: {
                if (c >= '0' and c <= '9') break :blk c - '0';
                if (c >= 'a' and c <= 'f') break :blk c - 'a' + 10;
                if (c >= 'A' and c <= 'F') break :blk c - 'A' + 10;
                return null;
            },
            else => return null,
        };
        result = result * @as(u64, base) + digit;
    }
    return result;
}


