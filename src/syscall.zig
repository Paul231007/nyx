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

/// Kernel-side syscall handler: maps nr → action, returns result.
pub fn dispatch(nr: u32, a: usize, b: usize, c: usize) usize {
    return switch (nr) {
        1 => blk: { // write: a=ptr, b=len
            const ptr: [*]const u8 = @ptrFromInt(a);
            console.write(ptr[0..b]);
            break :blk b;
        },
        2 => blk: { // read: a=fd, b=bufptr, c=len
            const fd: vfs.Fd = @intCast(a & 0xFF);
            const buf_ptr: [*]u8 = @ptrFromInt(b);
            const n = vfs.read(fd, buf_ptr[0..c]);
            break :blk @as(usize, n);
        },
        3 => blk: { // open: a=path_ptr, b=path_len
            const path_ptr: [*]const u8 = @ptrFromInt(a);
            const path = path_ptr[0..b];
            if (vfs.open(path)) |fd| break :blk @as(usize, fd) else break :blk 0xFFFFFFFF;
        },
        4 => blk: { // close: a=fd
            vfs.close(@intCast(a & 0xFF));
            break :blk 0;
        },
        5 => 1, // getpid: always 1 (single process kernel)
        6 => @as(usize, @truncate(timer.ticks())), // uptime
        else => 0,
    };
}

/// User-side: upt nr→eax, a→ebx, b→ecx, c→edx, fire int 0x80, return eax. pub fn invoke(nr: Nr, a: usize, b: usize, c: usize) usize { return asm volatile ("int $0x80" : [ret] "={eax}" (-> usize), : [nr] "{eax}" (@intFromEnum(nr)), [aa] "{ebx}" (a), [bb] "{ecx}" (b), [cc] "{edx}" (c), : .{ .memory = true } ); }