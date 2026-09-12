# Shell, syscalls, and self-tests

## shell.zig — Interactive command shell (M9)

`shell.run()` is the final call in `kmain` and never returns. It is the interactive
endpoint of the kernel: a classic read-eval-print loop over the unified input ring.

### Command loop

