//! 256-entry Interrupt Descriptor Table.
//! Gates are filled in by callers (e.g. the exception layer) via `setGate`,
//! then committed to the CPU with `load`.

/// One 8-byte IDT gate descriptor, bit-packed LSB-first.
const IdtEntry = packed struct {
    offset_lo: u16, // bits 0..15 of the handler address
    selector: u16, // code segment selector (0x08)
    zero: u8, // always 0
    type_attr: u8, // gate type + DPL + present
    offset_hi: u16, // bits 16..31 of the handler address
};

/// The operand for `lidt`.
const Idtr = packed struct {
    limit: u16,
    base: u32,
};

var idt: [256]IdtEntry = undefined;
var idtr: Idtr = undefined;
