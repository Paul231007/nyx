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

