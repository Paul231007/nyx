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

