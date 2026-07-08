const std = @import("std");

pub fn build(b: *std.Build) void {
    // Freestanding 32-bit x86. Disable all the vector/FP features the kernel
    // never sets up, and pull in soft-float so the compiler never emits SSE.
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .x86,
        .os_tag = .freestanding,
        .abi = .none,
        .cpu_features_sub = std.Target.x86.featureSet(&.{
            .mmx, .sse, .sse2, .sse3, .ssse3, .sse4_1, .sse4_2, .avx, .avx2,
        }),
        .cpu_features_add = std.Target.x86.featureSet(&.{.soft_float}),
    });

    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .Debug });

    const kernel = b.addExecutable(.{
        .name = "kernel.elf",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    kernel.addAssemblyFile(b.path("src/boot.s"));
    kernel.setLinkerScript(b.path("linker.ld"));
    kernel.want_lto = false;
    b.installArtifact(kernel);

    // `zig build run` ...
    const run = b.addSystemCommand(&.{"qemu-system-i386"});
    run.addArg("-kernel");
    run.addArtifactArg(kernel);
    run.addArgs(&.{
        "-serial",  "stdio",
        "-display", "none",
        "-no-reboot",
        "-device",  "isa-debug-exit,iobase=0xf4,iosize=0x04",
        "-m",       "64",
        "-drive",   "file=/tmp/nyx-disk.img,format=raw,if=ide",
    });
    b.step("run", "Boot the kernel in QEMU (serial on stdio)").dependOn(&run.step);
}
