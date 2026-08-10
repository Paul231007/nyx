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


