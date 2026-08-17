//! tar — minimal POSIX ustar parser for unpacking an initrd image into ramfs.
//!
//! Header layout (512-byte blocks):
//!   offset   0: name      (100 bytes, NUL-terminated)
//!   offset 124: size      (12 bytes, octal ASCII, NUL-/space-terminated)
//!   offset 156: typeflag  ('0' or 0 = file, '5' = directory)
//!
//! After each header there are ceil(size/512) data blocks. Two consecutive
//! all-zero blocks mark the end of the archive.

const std = @import("std");
const vfs = @import("vfs.zig");
const ramfs = @import("ramfs.zig");

const HDR: usize = 512;

/// Parse a NUL/space-terminated octal string.
fn parseOctal(s: []const u8) usize {
    var result: usize = 0;
    for (s) |c| {
        if (c == 0 or c == ' ') break;
        if (c >= '0' and c <= '7') {
            result = result * 8 + (c - '0');
        } else break;
    }
    return result;
}

/// Strip a "./" prefix and a trailing "/" from a tar name, then prepend "/".
/// Writes the result into `buf` and returns the slice.
fn normalizePath(name: []const u8, buf: []u8) []const u8 {
    var s = name;
    if (std.mem.startsWith(u8, s, "./")) s = s[2..];
    // Strip trailing slashes.
    while (s.len > 0 and s[s.len - 1] == '/') s = s[0 .. s.len - 1];
    if (s.len == 0) {
        buf[0] = '/';
        return buf[0..1];
    }
    buf[0] = '/';
    const copy_len = @min(s.len, buf.len - 1);
    std.mem.copyForwards(u8, buf[1 .. 1 + copy_len], s[0..copy_len]);
    return buf[0 .. 1 + copy_len];
}

/// Unpack `image` (a raw ustar byte slice) into the given `into` filesystem,
/// using ramfs.create to allocate entries. Returns the number of entries created.
pub fn unpackInto(image: []const u8, into: *vfs.FileSystem) usize {
    var offset: usize = 0;
    var created: usize = 0;
    var zero_blocks: usize = 0;

    while (offset + HDR <= image.len) {
        const hdr = image[offset .. offset + HDR];
        offset += HDR;

        // Detect an all-zero block (end-of-archive sentinel).
        var is_zero = true;
        for (hdr) |b| {
            if (b != 0) { is_zero = false; break; }
        }
        if (is_zero) {
            zero_blocks += 1;
            if (zero_blocks >= 2) break;
            continue;
        }
        zero_blocks = 0;

        // Parse name (NUL-terminated, max 100 bytes).
        var name_len: usize = 0;
        while (name_len < 100 and hdr[name_len] != 0) : (name_len += 1) {}
        const raw_name = hdr[0..name_len];

        // Size field: bytes 124..135 (12 bytes octal).
        const file_size = parseOctal(hdr[124..136]);

        // Typeflag: byte 156.
        const typeflag = hdr[156];
        const is_dir = typeflag == '5';
        const is_file = (typeflag == '0') or (typeflag == 0);

        const data_blocks = (file_size + HDR - 1) / HDR;

