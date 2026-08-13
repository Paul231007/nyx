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

/// Return a human-readable class/subclass description for a PCI device.
/// Covers PCI class codes 0x00–0x13 with common subclasses.
pub fn classNameOf(class: u8, subclass: u8) []const u8 {
    return switch (class) {
        0x00 => switch (subclass) {
            0x00 => "Unclassified / Non-VGA",
            0x01 => "Unclassified / VGA-Compatible",
            else => "Unclassified",
        },
        0x01 => switch (subclass) {
            0x00 => "Storage / SCSI",
            0x01 => "Storage / IDE",
            0x02 => "Storage / Floppy",
            0x03 => "Storage / IPI Bus",
            0x04 => "Storage / RAID",
            0x05 => "Storage / ATA",
            0x06 => "Storage / SATA (AHCI)",
            0x07 => "Storage / SAS",
            0x08 => "Storage / NVM Express",
            0x80 => "Storage / Other",
            else => "Storage",
        },
        0x02 => switch (subclass) {
            0x00 => "Network / Ethernet",
            0x01 => "Network / Token Ring",
            0x02 => "Network / FDDI",
            0x03 => "Network / ATM",
            0x04 => "Network / ISDN",
            0x05 => "Network / WorldFip",
            0x06 => "Network / PICMG 2.14",
            0x07 => "Network / InfiniBand",
            0x08 => "Network / Fabric",
            0x80 => "Network / Other",
            else => "Network",
        },
        0x03 => switch (subclass) {
            0x00 => "Display / VGA Compatible",
            0x01 => "Display / XGA",
            0x02 => "Display / 3D (non-VGA)",
            0x80 => "Display / Other",
            else => "Display",
        },
        0x04 => switch (subclass) {
            0x00 => "Multimedia / Video",
            0x01 => "Multimedia / Audio",
            0x02 => "Multimedia / Telephony",
            0x03 => "Multimedia / Mixed Mode",
            0x80 => "Multimedia / Other",
            else => "Multimedia",
        },
        0x05 => switch (subclass) {
            0x00 => "Memory / RAM",
            0x01 => "Memory / Flash",
            0x80 => "Memory / Other",
            else => "Memory",
        },
        0x06 => switch (subclass) {
            0x00 => "Bridge / Host",
            0x01 => "Bridge / ISA",
            0x02 => "Bridge / EISA",
            0x03 => "Bridge / MCA",
            0x04 => "Bridge / PCI-to-PCI",
            0x05 => "Bridge / PCMCIA",
            0x06 => "Bridge / NuBus",
            0x07 => "Bridge / CardBus",
            0x08 => "Bridge / RACEway",
            0x09 => "Bridge / Semi-Transparent PCI-to-PCI",
            0x0A => "Bridge / InfiniBand-to-PCI",
            0x80 => "Bridge / Other",
            else => "Bridge",
        },
        0x07 => switch (subclass) {
            0x00 => "Communication / Serial",
            0x01 => "Communication / Parallel",
            0x02 => "Communication / Multiport Serial",
            0x03 => "Communication / Modem",
            0x04 => "Communication / IEEE 488 (GPIB)",
            0x05 => "Communication / Smart Card",
            0x80 => "Communication / Other",
            else => "Communication",
        },
        0x08 => switch (subclass) {
            0x00 => "System / PIC",
            0x01 => "System / DMA Controller",
            0x02 => "System / Timer",
            0x03 => "System / RTC",
            0x04 => "System / PCI Hot-Plug",
            0x05 => "System / SD Host Controller",
            0x06 => "System / IOMMU",
            0x80 => "System / Other",
            else => "System",
        },
        0x09 => switch (subclass) {
            0x00 => "Input / Keyboard",
            0x01 => "Input / Digitizer (Pen)",
            0x02 => "Input / Mouse",
            0x03 => "Input / Scanner",
            0x04 => "Input / Gameport",
            0x80 => "Input / Other",
            else => "Input",
        },
        0x0A => switch (subclass) {
            0x00 => "Docking Station / Generic",
            0x80 => "Docking Station / Other",
            else => "Docking Station",
        },
        0x0B => switch (subclass) {
            0x00 => "Processor / 386",
            0x01 => "Processor / 486",
            0x02 => "Processor / Pentium",
            0x03 => "Processor / Pentium Pro",
            0x10 => "Processor / Alpha",
            0x20 => "Processor / PowerPC",
            0x30 => "Processor / MIPS",
            0x40 => "Processor / Co-processor",
            0x80 => "Processor / Other",
            else => "Processor",
        },
        0x0C => switch (subclass) {
            0x00 => "Serial Bus / FireWire (IEEE 1394)",
            0x01 => "Serial Bus / ACCESS.bus",
            0x02 => "Serial Bus / SSA",
            0x03 => "Serial Bus / USB",
            0x04 => "Serial Bus / Fibre Channel",
            0x05 => "Serial Bus / SMBus",
            0x06 => "Serial Bus / InfiniBand",
            0x07 => "Serial Bus / IPMI Interface",
            0x08 => "Serial Bus / SERCOS Interface",
            0x09 => "Serial Bus / CAN bus",
            0x80 => "Serial Bus / Other",
            else => "Serial Bus",
        },
        0x0D => switch (subclass) {
            0x00 => "Wireless / iRDA",
            0x01 => "Wireless / Consumer IR",
            0x10 => "Wireless / RF Controller",
            0x11 => "Wireless / Bluetooth",
            0x12 => "Wireless / Broadband",
            0x20 => "Wireless / Ethernet 802.11a (5 GHz)",
            0x21 => "Wireless / Ethernet 802.11b (2.4 GHz)",
            0x80 => "Wireless / Other",
            else => "Wireless",
        },
        0x0E => switch (subclass) {
            0x00 => "Intelligent I/O (I2O)",
            else => "Intelligent I/O",
        },
        0x0F => switch (subclass) {
            0x00 => "Satellite / TV",
            0x01 => "Satellite / Audio",
            0x02 => "Satellite / Voice",
            0x03 => "Satellite / Data",
            else => "Satellite",
        },
        0x10 => switch (subclass) {
            0x00 => "Encryption / Network and Computing",
            0x10 => "Encryption / Entertainment",
            0x80 => "Encryption / Other",
            else => "Encryption",
        },
        0x11 => switch (subclass) {
            0x00 => "Signal Processing / DPIO Modules",
            0x01 => "Signal Processing / Performance Counters",
            0x10 => "Signal Processing / Communication Synchronizer",
            0x20 => "Signal Processing / Management Card",
            0x80 => "Signal Processing / Other",
            else => "Signal Processing",
        },
        0x12 => "Processing Accelerator",
        0x13 => "Non-Essential Instrumentation",
        0xFF => "Unassigned / Vendor-Specific",
        else => "Unknown Class",
    };
}


