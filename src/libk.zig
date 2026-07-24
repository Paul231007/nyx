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

/// Convert `c` to uppercase if it is a lowercase ASCII letter; otherwise
/// return `c` unchanged.
pub fn toUpper(c: u8) u8 {
    return if (c >= 'a' and c <= 'z') c - ('a' - 'A') else c;
}

/// Convert `c` to lowercase if it is an uppercase ASCII letter; otherwise
/// return `c` unchanged.
pub fn toLower(c: u8) u8 {
    return if (c >= 'A' and c <= 'Z') c + ('a' - 'A') else c;
}

/// Return true when `s` begins with `prefix`.
pub fn startsWith(s: []const u8, prefix: []const u8) bool {
    if (prefix.len > s.len) return false;
    return std.mem.eql(u8, s[0..prefix.len], prefix);
}

/// Format `v` as a decimal string into `buf`.  Returns the written slice.
/// If `buf` is too small the result is silently truncated.  Callers should
/// provide at least 20 bytes (the length of the largest u64 in decimal).
pub fn formatDec(buf: []u8, v: u64) []const u8 {
    if (buf.len == 0) return buf[0..0];
    if (v == 0) {
        buf[0] = '0';
        return buf[0..1];
    }
    // Build digits in reverse order into a temporary stack array.
    var tmp: [20]u8 = undefined;
    var pos: usize = 0;
    var val: u64 = v;
    while (val > 0) : (val /= 10) {
        tmp[pos] = '0' + @as(u8, @truncate(val % 10));
        pos += 1;
    }
    // Copy reversed into `buf`.
    const n = @min(pos, buf.len);
    var di: usize = 0;
    while (di < n) : (di += 1) {
        buf[di] = tmp[pos - 1 - di];
    }
    return buf[0..n];
}

/// Format `v` as a lowercase hexadecimal string (no "0x" prefix) into `buf`.
/// Returns the written slice.  Provide at least 16 bytes for a full u64.
pub fn formatHex(buf: []u8, v: u64) []const u8 {
    if (buf.len == 0) return buf[0..0];
    if (v == 0) {
        buf[0] = '0';
        return buf[0..1];
    }
    const digits = "0123456789abcdef";
    var tmp: [16]u8 = undefined;
    var pos: usize = 0;
    var val: u64 = v;
    while (val > 0) : (val >>= 4) {
        tmp[pos] = digits[@as(usize, @truncate(val & 0xF))];
        pos += 1;
    }
    const n = @min(pos, buf.len);
    var di: usize = 0;
    while (di < n) : (di += 1) {
        buf[di] = tmp[pos - 1 - di];
    }
    return buf[0..n];
}

/// Canonical hex dumper: prints 16-byte rows as "OFFSET  hex bytes  ascii".
pub const HexDump = struct {
    /// Dump `len` bytes starting at virtual address `addr`.
    /// Each formatted line is passed to `out` as a byte slice.
    pub fn dump(addr: usize, len: usize, out: *const fn ([]const u8) void) void {
        const mem: [*]const u8 = @ptrFromInt(addr);
        var offset: usize = 0;
        var line_buf: [80]u8 = undefined;

        while (offset < len) {
            const row_len = @min(16, len - offset);
            const row = mem[offset .. offset + row_len];
            var pos: usize = 0;

            // "XXXXXXXX  " — 8-digit zero-padded hex offset
            const hdr = std.fmt.bufPrint(&line_buf, "{X:0>8}  ", .{offset}) catch break;
            pos = hdr.len;

            // Hex bytes, two columns of eight with an extra space in the middle
            var col: usize = 0;
            while (col < 16) : (col += 1) {
                if (col < row_len) {
                    const hw = std.fmt.bufPrint(line_buf[pos..], "{X:0>2} ", .{row[col]}) catch break;
                    pos += hw.len;
                } else {
                    // Pad missing columns
                    if (pos + 3 <= line_buf.len) {
                        line_buf[pos] = ' ';
                        line_buf[pos + 1] = ' ';
                        line_buf[pos + 2] = ' ';
                        pos += 3;
                    }
                }
                // Extra space after the eighth byte
                if (col == 7 and pos < line_buf.len) {
                    line_buf[pos] = ' ';
                    pos += 1;
                }
            }

            // Separator before ASCII
            if (pos < line_buf.len) {
                line_buf[pos] = ' ';
                pos += 1;
            }

            // ASCII column: printable chars verbatim, others as '.'
            for (row) |b| {
                if (pos < line_buf.len) {
                    line_buf[pos] = if (b >= 0x20 and b < 0x7F) b else '.';
                    pos += 1;
                }
            }

            if (pos < line_buf.len) {
                line_buf[pos] = '\n';
                pos += 1;
            }


