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

fn parseRsdp(ptr: [*]const u8) Rsdp {
    var oem: [6]u8 = undefined;
    var ii: usize = 0;
    while (ii < 6) : (ii += 1) {
        oem[ii] = ptr[9 + ii];
    }
    const revision = ptr[15];
    const rsdt_addr: u32 =
        @as(u32, ptr[16]) |
        (@as(u32, ptr[17]) << 8) |
        (@as(u32, ptr[18]) << 16) |
        (@as(u32, ptr[19]) << 24);
    return Rsdp{
        .found     = true,
        .oem       = oem,
        .revision  = revision,
        .rsdt_addr = rsdt_addr,
    };
}

