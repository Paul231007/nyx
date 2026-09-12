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

