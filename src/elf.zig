//! elf — minimal ELF32 header + program-header inspector (M18).
//! Read-only: parses the on-disk/in-memory image, never loads or executes.

pub const Header = struct {
    class:   u8,
    data:    u8,
    etype:   u16,
    machine: u16,
    entry:   u32,
    phoff:   u32,
    phnum:   u16,
    shnum:   u16,
};

pub const ParseError = error{ BadMagic, NotElf32 };

/// Parse an ELF image from a byte slice.  Only ELF32 little-endian is accepted.
/// Fields are read directly from the standard ELF header offsets.
pub fn parse(image: []const u8) ParseError!Header {
    if (image.len < 52) return error.BadMagic;
    // Check magic: 0x7F 'E' 'L' 'F'
    if (image[0] != 0x7F or image[1] != 'E' or image[2] != 'L' or image[3] != 'F')
        return error.BadMagic;
    // EI_CLASS must be 1 (ELF32)
    if (image[4] != 1) return error.NotElf32;

    return Header{
        .class   = image[4],
        .data    = image[5],
        .etype   = readU16(image, 16),
        .machine = readU16(image, 18),
        .entry   = readU32(image, 24),
        .phoff   = readU32(image, 28),
        .phnum   = readU16(image, 44),
        .shnum   = readU16(image, 48),
    };
}


