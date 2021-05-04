OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY {
  L2 : ORIGIN = 0x80000000, LENGTH = 0x02000000
}

SECTIONS {
  .text : {
    *(.text.init)
    *(.text)
  } > L2

  .data : {
    . = ALIGN(0x10);
    *(.data)
  } > L2

  .rodata  : { *(.rodata .rodata.* .gnu.linkonce.r.*) } > L2
  .rodata1 : { *(.rodata1) } > L2
  .sdata2  : {
    *(.sdata2 .sdata2.* .gnu.linkonce.s2.*)
  } > L2
  .sdata   : {
    __global_pointer$ = . + 0x800;
    *(.srodata.cst16) *(.srodata.cst8) *(.srodata.cst4) *(.srodata.cst2) *(.srodata .srodata.*)
    *(.sdata .sdata.* .gnu.linkonce.s.*)
  } > L2

  .bss : {
    __bss_start = .;
    *(.bss)
    *(.sbss .sbss.* .sbss2 .sbss2.* .gnu.linkonce.sb2.*);
    __bss_end = .;
  } > L2

  .l2 : {
    . = ALIGN(0x10);
    *(.l2)
    timer = .;
    . = . + 0x8;
    l2_alloc_base = ALIGN(0x10);
  } > L2

  .comment : { *(.comment) } > L2

  eoc_address_reg        = 0xD0000000;
  dram_start_address_reg = 0xD0000008;
  dram_end_address_reg   = 0xD0000010;

  fake_uart              = 0xC0000000;
}
