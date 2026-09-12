# Shell, syscalls, and self-tests

## shell.zig — Interactive command shell (M9)

`shell.run()` is the final call in `kmain` and never returns. It is the interactive
endpoint of the kernel: a classic read-eval-print loop over the unified input ring.

### Command loop

```
shell.run()
  while true:
    console.write("nyx> ")
    n = input.readLine(&line)
    text = trim(line[0..n])
    if text is empty: continue
    split text into cmd (first token) and args (remainder)
    dispatch to handler or print "unknown command"
```

`trim()` strips leading/trailing ASCII whitespace using `std.mem.trim`. The split
finds the first space with `std.mem.indexOfScalar`. This means commands like
`write /foo bar baz` pass `"/foo bar baz"` as `args`, and individual handlers do
their own secondary splits as needed (`cmdWrite` splits at the first space to
separate path from content).

### Built-in commands

| Command | Handler | Description |
|---------|---------|-------------|
| `help` | `cmdHelp()` | Prints the command list |
| `echo <args>` | inline | `console.write(args)` + newline |
| `mem` | `cmdMem()` | `pmm.stats()` + `heap.HEAP_BASE/HEAP_SIZE` |
| `uptime` | `cmdUptime()` | `timer.ticks()` and ticks / `timer.hz()` |
| `ps` | `cmdPs()` | `sched.taskCount()` and `sched.liveCount()` |
| `clear` | inline | `vga.clear()` + ANSI `\x1b[2J\x1b[H` on serial |
| `reboot` | inline | `io.outb(0x64, 0xFE)` — pulse 8042 CPU reset line |
| `date` | `cmdDate()` | `rtc.read()` formatted as ISO 8601 datetime |
| `lspci` | `cmdLspci()` | `pci.enumerate()` + formatted print per device |
| `diskinfo` | `cmdDiskinfo()` | `ata.identify()` — sectors and model string |
| `ls [path]` | `cmdLs()` | `vfs.open(path)` then `vfs.readdir()` loop |
| `cat <path>` | `cmdCat()` | `vfs.open()` + `vfs.read()` loop |
| `write <path> <s>` | `cmdWrite()` | `ramfs.create()` + `vfs.open()` + `vfs.write()` |
| `mkdir <path>` | `cmdMkdir()` | `ramfs.create(path, .dir)` |
| `rm <path>` | `cmdRm()` | `ramfs.remove(path)` |
| `test` | inline | `ktest.runAll()` |

