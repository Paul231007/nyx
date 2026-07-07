/* linker.ld — lay the kernel out starting at the conventional 1 MiB mark.
   The .multiboot section must come first so the bootloader finds the header
   within the first 8 KiB of the image. */
ENTRY(_start)

SECTIONS
{
    . = 1M;
    kernel_start = .;

    .multiboot : ALIGN(4) { *(.multiboot) }

    .text : ALIGN(4K) { *(.text*) }
    .rodata : ALIGN(4K) { *(.rodata*) }
    .data : ALIGN(4K) { *(.data*) }
    .bss : ALIGN(4K) {
        *(COMMON)
        *(.bss*)
    }

    kernel_end = .;
}
