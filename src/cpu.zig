//! cpu — CPUID wrapper (M19).
//! Freestanding: no std lib runtime.  Uses inline assembly for CPUID.

pub const VendorString = [12]u8;

/// Query CPUID leaf 0 and return the 12-byte vendor string (GenuineIntel,
/// AuthenticAMD, etc.).  The register order is ebx, edx, ecx.
pub fn vendor() VendorString {
    var eax_out: u32 = undefined;
    var ebx_out: u32 = undefined;
    var ecx_out: u32 = undefined;
    var edx_out: u32 = undefined;
    asm volatile ("cpuid"
        : [eax] "={eax}" (eax_out),
          [ebx] "={ebx}" (ebx_out),
          [ecx] "={ecx}" (ecx_out),
          [edx] "={edx}" (edx_out)
        : [leaf] "{eax}" (@as(u32, 0)),
    );
    var result: VendorString = undefined;
    result[0]  = @as(u8, @truncate(ebx_out        & 0xFF));
    result[1]  = @as(u8, @truncate((ebx_out >>  8) & 0xFF));
    result[2]  = @as(u8, @truncate((ebx_out >> 16) & 0xFF));
    result[3]  = @as(u8, @truncate((ebx_out >> 24) & 0xFF));
    result[4]  = @as(u8, @truncate(edx_out        & 0xFF));
    result[5]  = @as(u8, @truncate((edx_out >>  8) & 0xFF));
    result[6]  = @as(u8, @truncate((edx_out >> 16) & 0xFF));
    result[7]  = @as(u8, @truncate((edx_out >> 24) & 0xFF));
    result[8]  = @as(u8, @truncate(ecx_out        & 0xFF));
    result[9]  = @as(u8, @truncate((ecx_out >>  8) & 0xFF));
    result[10] = @as(u8, @truncate((ecx_out >> 16) & 0xFF));
    result[11] = @as(u8, @truncate((ecx_out >> 24) & 0xFF));
    return result;
}

