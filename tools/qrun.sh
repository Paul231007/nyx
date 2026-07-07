#!/usr/bin/env bash
# qrun.sh — boot the kernel headless in QEMU, capture serial output, with a
# hard timeout so a hang or triple-fault can never wedge the build.
#
# Usage: qrun.sh [kernel.elf] [input-bytes] [timeout-seconds]
#   input-bytes: optional; fed to the serial line (use \n for newlines).
set -u
KERNEL="${1:-zig-out/bin/kernel.elf}"
INPUT="${2:-}"
TIMEOUT="${3:-10}"

QEMU=(qemu-system-i386 -kernel "$KERNEL"
      -serial stdio -display none -no-reboot
      -device isa-debug-exit,iobase=0xf4,iosize=0x04
      -m 64)

if [ -n "$INPUT" ]; then
  printf '%b' "$INPUT" | timeout "$TIMEOUT" "${QEMU[@]}" 2>/dev/null
else
  timeout "$TIMEOUT" "${QEMU[@]}" </dev/null 2>/dev/null
fi
# Always succeed: callers grep the captured serial output for pass markers.
exit 0
