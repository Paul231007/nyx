# nyx

A small **freestanding x86 (i386) operating-system kernel**, written from scratch in
**Zig 0.15.2** with no libc and no external dependencies. It boots on bare QEMU and
brings the machine up through the classic kernel-bring-up sequence all the way to an
**interactive shell** with a real filesystem, disk driver, syscall layer, and self-test
harness.

```
$ zig build run
================================
  nyx -- a small x86 kernel
================================
nyx: M0 OK
nyx: M2 OK
nyx: M3 OK
...
nyx: M16 OK
================================
  nyx shell -- type 'help'
================================
nyx> help
nyx> mem
frames: total=15933 used=1044 free=14889
usable: 62 MiB total, 58 MiB free
heap:   base=0xD0000000 size=4096 KiB
nyx> echo hello
hello
nyx> date
2026-06-26 14:22:05
nyx> ls
- hello.txt
- motd
nyx> cat /hello.txt
hello nyx
```

## Build & run

Requires `zig` (0.15.2) and `qemu-system-i386`.

```sh
zig build            # builds zig-out/bin/kernel.elf (a multiboot1 ELF)
zig build run        # boots it in QEMU with the serial console on stdio
```

QEMU boots the kernel directly via `-kernel` (multiboot1) — no GRUB or ISO needed.

### Disk image

The ATA driver (M12) and block cache require an IDE disk. The `build.zig` passes:

```
-drive file=nyx.img,if=ide,format=raw
```

Create a blank image before the first run if it does not exist:

```sh
dd if=/dev/zero of=nyx.img bs=512 count=65536  # 32 MiB
```

### Headless testing

`tools/qrun.sh` boots the kernel with no display, captures the serial output, and
times out so a hang or triple-fault can never wedge the harness. The shell reads
from both the PS/2 keyboard and COM1, so it is fully driveable headlessly:
