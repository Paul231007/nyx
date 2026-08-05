//! acpi — ACPI RSDP/RSDT finder (M20).
//! Scans the two standard memory regions for the "RSD PTR " signature.
//! Read-only: never modifies ACPI tables.

pub const Rsdp = struct {
    found:     bool,
    oem:       [6]u8,
    revision:  u8,
    rsdt_addr: u32,
};

fn checkSignature(ptr: [*]const u8) bool {
    const sig = "RSD PTR ";
    var ii: usize = 0;
    while (ii < 8) : (ii += 1) {
        if (ptr[ii] != sig[ii]) return false;
    }
    return true;
}

fn checksum20(ptr: [*]const u8) bool {
    var sum: u8 = 0;
    var ii: usize = 0;
    while (ii < 20) : (ii += 1) {
        sum +%= ptr[ii];
    }
    return sum == 0;
}


