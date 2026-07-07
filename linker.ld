/* linker.ld — lay the kernel out starting at the conventional 1 MiB mark.
   The .multiboot section must come first so the bootloader finds the header
   within the first 8 KiB of the image. */
ENTRY(_start)

SECTIONS
{
    . = 1M;
    kernel_start = .;

    .multiboot : ALIGN(4) { *(.multiboot) }

