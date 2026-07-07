/* boot.s — multiboot1 header + kernel entry point (32-bit x86).
   QEMU's `-kernel` loads a multiboot1 ELF directly: no GRUB/ISO needed.
   The bootloader jumps to _start with EAX = 0x2BADB002 and EBX = *mboot_info. */


