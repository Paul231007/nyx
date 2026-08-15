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


