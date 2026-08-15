//! tar — minimal POSIX ustar parser for unpacking an initrd image into ramfs.
//!
//! Header layout (512-byte blocks):
//!   offset   0: name      (100 bytes, NUL-terminated)
//!   offset 124: size      (12 bytes, octal ASCII, NUL-/space-terminated)
//!   offset 156: typeflag  ('0' or 0 = file, '5' = directory)
//!
//! After each header there are ceil(size/512) data blocks. Two consecutive
//! all-zero blocks mark the end of the archive.


