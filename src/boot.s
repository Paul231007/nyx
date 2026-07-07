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

/* 16 KiB boot stack */
.section .bss
.align 16
stack_bottom:
.skip 16384
stack_top:

.section .text
.global _start
.type _start, @function
_start:
    mov $stack_top, %esp     /* set up the stack */
    push %ebx                /* arg2: multiboot info pointer */
    push %eax                /* arg1: multiboot magic */
    call kmain               /* into Zig */
    cli
1:  hlt
    jmp 1b
.size _start, . - _start
