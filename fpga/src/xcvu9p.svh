// Description: Set global FPGA degines
// Author: MohammadHossein AskariHemmat m.h.askari.hemmat@gmail.com

`define xcvu9p

//=============================================================================
// CVA6 Configurations
//=============================================================================
`define ARIANE_DATA_WIDTH 64
// Instantiate protocl checker
// `define PROTOCOL_CHECKER
// write-back cache
// `define WB_DCACHE
// write-through cache
`define WT_DCACHE 1

`define RVV_ARIANE 1

//=============================================================================
// Ara Configurations
//=============================================================================
`define NrLanes 4
`define VLEN 4096
