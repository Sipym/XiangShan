OUTPUT_ARCH("riscv")
ENTRY(_start)

SECTIONS
{
  . = 0x80000000;
  .text : { *(.text.init) *(.text .text.*) }
  . = ALIGN(0x1000);
  .data : { *(.rodata .rodata.*) *(.data .data.*) *(.sdata .sdata.*) }
  .bss : { *(.bss .bss.*) *(.sbss .sbss.*) }
  . = ALIGN(0x1000);
  . += 0x4000;
  _stack_top = .;
}
