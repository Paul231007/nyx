//! Flat (segmentation-disabled) GDT for protected mode.
//! Three descriptors: null, ring-0 code, ring-0 data — all base 0, 4 GiB limit.
//! After loading we reload the segment registers so the new descriptors take
//! effect (CS via a far jump, the rest via plain moves).

/// One 8-byte GDT descriptor, laid out exactly as the CPU expects.
/// Fields are bit-packed LSB-first to match the hardware encoding.
const GdtEntry = packed struct {
    limit_lo: u16,
    base_lo: u16,
    base_mid: u8,
    access: u8,
    limit_hi: u4,
    flags: u4,
    base_hi: u8,
};

/// The operand for `lgdt`: 16-bit limit + 32-bit linear base.
const Gdtr = packed struct {
    limit: u16,
    base: u32,
};

var gdt: [3]GdtEntry = undefined;
var gdtr: Gdtr = undefined;


