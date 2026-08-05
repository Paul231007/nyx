//! acpi — ACPI RSDP/RSDT finder (M20).
//! Scans the two standard memory regions for the "RSD PTR " signature.
//! Read-only: never modifies ACPI tables.

pub const Rsdp = struct {
    found:     bool,
    oem:       [6]u8,
    revision:  u8,
    rsdt_addr: u32,
};

