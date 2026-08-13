//! PCI bus enumeration via legacy Configuration Mechanism #1 (ports 0xCF8/0xCFC).

const io = @import("io.zig");

/// A discovered PCI device.
pub const Device = struct {
    bus: u8,
    slot: u8,
    func: u8,
    vendor: u16,
    device: u16,
    class: u8,
    subclass: u8,
};

/// Build a PCI configuration address word.
inline fn cfgAddr(bus: u8, slot: u8, func: u8, offset: u8) u32 {
    return 0x80000000 |
        (@as(u32, bus) << 16) |
        (@as(u32, slot) << 11) |
        (@as(u32, func) << 8) |
        (@as(u32, offset) & 0xFC);
}

/// Read a 32-bit value from PCI configuration space.
inline fn cfgRead32(bus: u8, slot: u8, func: u8, offset: u8) u32 {
    io.outl(0xCF8, cfgAddr(bus, slot, func, offset));
    return io.inl(0xCFC);
}

/// Brute-force scan buses 0..255 (or a subset), slots 0..31, funcs 0..7.
/// Fills `out` with discovered devices and returns the count found.
pub fn enumerate(out: []Device) usize {
    var count: usize = 0;
    var bus: u16 = 0;
    while (bus < 256) : (bus += 1) {
        var slot: u8 = 0;
        while (slot < 32) : (slot += 1) {
            var func: u8 = 0;
            while (func < 8) : (func += 1) {
                if (count >= out.len) return count;

                const id = cfgRead32(@truncate(bus), slot, func, 0x00);
                const vendor: u16 = @truncate(id & 0xFFFF);
                if (vendor == 0xFFFF) {
                    // No device; if func 0 is absent skip remaining funcs.
                    if (func == 0) break;
                    continue;
                }
                const dev_id: u16 = @truncate((id >> 16) & 0xFFFF);

                const class_dword = cfgRead32(@truncate(bus), slot, func, 0x08);
                const subclass: u8 = @truncate((class_dword >> 16) & 0xFF);
                const class: u8 = @truncate((class_dword >> 24) & 0xFF);

                out[count] = Device{
                    .bus = @truncate(bus),
                    .slot = slot,
                    .func = func,
                    .vendor = vendor,
                    .device = dev_id,
                    .class = class,
                    .subclass = subclass,
                };
                count += 1;
            }
        }
    }
    return count;
}


