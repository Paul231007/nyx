//! int 0x80 syscall interface.
//!
//! dispatch()  — kernel side: called from the int 0x80 ISR with nr/args.
//! invoke()    — call side: issues `int $0x80` from ring-0 code.

const console = @import("console.zig");
const timer = @import("timer.zig");
const vfs = @import("vfs.zig");

pub const Nr = enum(u32) {
    write = 1,
    read = 2,
    open = 3,
    close = 4,
    getpid = 5,
    uptime = 6,
};


