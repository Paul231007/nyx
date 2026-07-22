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

/// Parse `s` as a hexadecimal number.  An optional "0x" / "0X" prefix is
/// accepted.  Digits are case-insensitive.  Returns null on empty input or an
/// invalid hex character.
pub fn parseHex(s: []const u8) ?u64 {
    var rest = s;
    if (rest.len >= 2 and rest[0] == '0' and (rest[1] == 'x' or rest[1] == 'X')) {
        rest = rest[2..];
    }
    return parseUint(rest, 16);
}

/// Compare up to `n` bytes of `a` and `b`.  Returns <0, 0, or >0 following
/// the same convention as C's `strncmp`.  Bytes past the end of a shorter
/// slice are treated as 0 (as if null-terminated).
pub fn strncmp(a: []const u8, b: []const u8, n: usize) i32 {
    var ii: usize = 0;
    while (ii < n) : (ii += 1) {
        const ca: u8 = if (ii < a.len) a[ii] else 0;
        const cb: u8 = if (ii < b.len) b[ii] else 0;
        if (ca < cb) return -1;
        if (ca > cb) return 1;
        if (ca == 0) return 0; // both reached a null — equal
    }
    return 0;
}

/// Return the index of the first occurrence of `needle` in `haystack`, or
/// null if it is not present.
pub fn indexOf(haystack: []const u8, needle: u8) ?usize {
    for (haystack, 0..) |c, i| {
        if (c == needle) return i;
    }
    return null;
}
