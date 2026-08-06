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

/// Search for the RSDP.  Checks the EBDA first, then scans 0xE0000..0xFFFFF.
pub fn find() Rsdp {
    // Check EBDA: the segment pointer lives at physical 0x40E; shift left 4.
    const bda_seg_ptr: *const u16 = @ptrFromInt(0x40E);
    const ebda_phys: u32 = @as(u32, bda_seg_ptr.*) << 4;
    if (ebda_phys >= 0x80000 and ebda_phys < 0xA0000) {
        var off: u32 = 0;
        while (off < 1024) : (off += 16) {
            const ptr: [*]const u8 = @ptrFromInt(ebda_phys + off);
            if (checkSignature(ptr) and checksum20(ptr)) {
                return parseRsdp(ptr);
            }
        }
    }
    // Scan the BIOS read-only memory area 0xE0000..0xFFFFF on 16-byte boundaries.
    var addr: u32 = 0x000E0000;
    while (addr < 0x00100000) : (addr += 16) {
        const ptr: [*]const u8 = @ptrFromInt(addr);
        if (checkSignature(ptr) and checksum20(ptr)) {
            return parseRsdp(ptr);
        }
    }
    return Rsdp{
        .found     = false,
        .oem       = [_]u8{0} ** 6,
        .revision  = 0,
        .rsdt_addr = 0,
    };
}

