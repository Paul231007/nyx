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

/// Map a machine value to a human-readable string.
pub fn machineName(m: u16) []const u8 {
    return switch (m) {
        0    => "None",
        1    => "AT&T WE 32100",
        2    => "SPARC",
        3    => "x86 (i386)",
        4    => "Motorola 68000",
        5    => "Motorola 88000",
        7    => "Intel 80860",
        8    => "MIPS I",
        0x14 => "PowerPC",
        0x28 => "ARM",
        0x2A => "SuperH",
        0x32 => "IA-64",
        0x3E => "x86-64 (AMD64)",
        0xB7 => "AArch64",
        0xF3 => "RISC-V",
        else => "Unknown",
    };
}

/// Map an ELF program-header type (p_type) to a human-readable string.
pub fn phTypeName(pt: u32) []const u8 {
    return switch (pt) {
        0          => "PT_NULL",
        1          => "PT_LOAD",
        2          => "PT_DYNAMIC",
        3          => "PT_INTERP",
        4          => "PT_NOTE",
        5          => "PT_SHLIB",
        6          => "PT_PHDR",
        7          => "PT_TLS",
        0x60000000 => "PT_LOOS",
        0x6474E550 => "PT_GNU_EH_FRAME",
        0x6474E551 => "PT_GNU_STACK",
        0x6474E552 => "PT_GNU_RELRO",
        0x6FFFFFFF => "PT_HIOS",
        0x70000000 => "PT_LOPROC",
        0x7FFFFFFF => "PT_HIPROC",
        else       => "PT_UNKNOWN",
    };
}

/// Map an ELF program-header flags field to a compact 3-char string.
/// Bit 2 = R, bit 1 = W, bit 0 = X.
pub fn phFlagsStr(flags: u32) [3]u8 {
    var out: [3]u8 = "---".*;
    if (flags & 4 != 0) out[0] = 'R';
    if (flags & 2 != 0) out[1] = 'W';
    if (flags & 1 != 0) out[2] = 'X';
    return out;
}

/// A decoded ELF32 program header.
pub const ProgramHeader = struct {
    ptype:  u32,   // p_type
    offset: u32,   // p_offset
    vaddr:  u32,   // p_vaddr
    paddr:  u32,   // p_paddr
    filesz: u32,   // p_filesz
    memsz:  u32,   // p_memsz
    flags:  u32,   // p_flags
    align_: u32,   // p_align
};

/// Parse program header `idx` from an ELF32 image.
/// Returns null when `idx` is out of range or the image is too short.
pub fn programHeader(image: []const u8, hdr: Header, idx: u16) ?ProgramHeader {
    if (idx >= hdr.phnum) return null;
    const ph_size: usize = 32; // ELF32 Phdr is exactly 32 bytes
    const base: usize = hdr.phoff + @as(usize, idx) * ph_size;
    if (base + ph_size > image.len) return null;
    return ProgramHeader{
        .ptype  = readU32(image, base +  0),
        .offset = readU32(image, base +  4),
        .vaddr  = readU32(image, base +  8),
        .paddr  = readU32(image, base + 12),
        .filesz = readU32(image, base + 16),
        .memsz  = readU32(image, base + 20),
        .flags  = readU32(image, base + 24),
        .align_ = readU32(image, base + 28),
    };
}

/// Walk all program headers and call `cb` with each decoded entry.
/// Stops early if `cb` returns false.  Returns the number of headers visited.
pub fn walkPhdrs(
    image: []const u8,
    hdr: Header,
    cb: *const fn (idx: u16, ph: ProgramHeader) bool,
) u16 {
    var i: u16 = 0;
    while (i < hdr.phnum) : (i += 1) {
        const ph = programHeader(image, hdr, i) orelse break;
        if (!cb(i, ph)) break;
    }
    return i;
}

