OUTPUT_ARCH("riscv")
ENTRY(_start)

SECTIONS {
  ROM_BASE = 0x80000000; /* ... but actually position independent */

  eoc_address_reg        = 0xD0000000;
  dram_start_address_reg = 0xD0000008;
  dram_end_address_reg   = 0xD0000010;

  . = ROM_BASE;
  .text : {
    *(.text.init)
    *(.text)
  }

  . = ALIGN(0x10);
  .data           : { *(.data) }
  .rodata         : { *(.rodata .rodata.* .gnu.linkonce.r.*) }
  .rodata1        : { *(.rodata1) }
  .sdata2         : {
    *(.sdata2 .sdata2.* .gnu.linkonce.s2.*)
  }
  .sdata          : {
    __global_pointer$ = . + 0x800;
    *(.srodata.cst16) *(.srodata.cst8) *(.srodata.cst4) *(.srodata.cst2) *(.srodata .srodata.*)
    *(.sdata .sdata.* .gnu.linkonce.s.*)
  }
  . = .;

  __bss_start = .;
  .sbss2          : { *(.sbss2 .sbss2.* .gnu.linkonce.sb2.*) }
  .bss            : { *(.bss) }
  __bss_end = .;

  fake_uart = 0xC0000000;
}
