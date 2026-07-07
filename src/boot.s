/* boot.s — multiboot1 header + kernel entry point (32-bit x86).
   QEMU's `-kernel` loads a multiboot1 ELF directly: no GRUB/ISO needed.
   The bootloader jumps to _start with EAX = 0x2BADB002 and EBX = *mboot_info. */

.set ALIGN,    1<<0              /* align loaded modules on page boundaries */
.set MEMINFO,  1<<1              /* provide a memory map */
.set FLAGS,    ALIGN | MEMINFO   /* multiboot flag field */
.set MAGIC,    0x1BADB002        /* the magic number identifying the header */
.set CHECKSUM, -(MAGIC + FLAGS)  /* checksum so (MAGIC+FLAGS+CHECKSUM)==0 */

.section .multiboot, "a"
.align 4
.long MAGIC
.long FLAGS
.long CHECKSUM

