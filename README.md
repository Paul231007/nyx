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


