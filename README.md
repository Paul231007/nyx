# nyx

A small **freestanding x86 (i386) operating-system kernel**, written from scratch in
**Zig 0.15.2** with no libc and no external dependencies. It boots on bare QEMU and
brings the machine up through the classic kernel-bring-up sequence all the way to an
**interactive shell** with a real filesystem, disk driver, syscall layer, and self-test
harness.


