//! COM1 serial driver. Doubles as the headless console for testing: we can
//! drive the kernel by piping bytes into QEMU's `-serial stdio` and read its
//! output back the same way.

const io = @import("io.zig");

