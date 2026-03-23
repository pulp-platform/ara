// Copyright 2024 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Description:
// AES (Zvkned) combinational unit operating on 128-bit element groups.
// Implements SubBytes, ShiftRows, MixColumns, and their inverses,
// plus AES key schedule (vaeskf1/vaeskf2).

module simd_aes import ara_pkg::*; import rvv_pkg::*; (
    input  logic [127:0] state_i,     // Current AES state (from vd)
    input  logic [127:0] round_key_i, // Round key (from vs2)
    input  ara_op_e      op_i,
    input  logic [4:0]   uimm_i,      // Round number for key schedule ops
    output logic [127:0] result_o
  );

  ///////////////////
  //  AES S-boxes  //
  ///////////////////

  // Forward S-box lookup table
  function automatic logic [7:0] sbox_fwd(input logic [7:0] in);
    unique case (in)
      8'h00: sbox_fwd = 8'h63; 8'h01: sbox_fwd = 8'h7c; 8'h02: sbox_fwd = 8'h77; 8'h03: sbox_fwd = 8'h7b;
      8'h04: sbox_fwd = 8'hf2; 8'h05: sbox_fwd = 8'h6b; 8'h06: sbox_fwd = 8'h6f; 8'h07: sbox_fwd = 8'hc5;
      8'h08: sbox_fwd = 8'h30; 8'h09: sbox_fwd = 8'h01; 8'h0a: sbox_fwd = 8'h67; 8'h0b: sbox_fwd = 8'h2b;
      8'h0c: sbox_fwd = 8'hfe; 8'h0d: sbox_fwd = 8'hd7; 8'h0e: sbox_fwd = 8'hab; 8'h0f: sbox_fwd = 8'h76;
      8'h10: sbox_fwd = 8'hca; 8'h11: sbox_fwd = 8'h82; 8'h12: sbox_fwd = 8'hc9; 8'h13: sbox_fwd = 8'h7d;
      8'h14: sbox_fwd = 8'hfa; 8'h15: sbox_fwd = 8'h59; 8'h16: sbox_fwd = 8'h47; 8'h17: sbox_fwd = 8'hf0;
      8'h18: sbox_fwd = 8'had; 8'h19: sbox_fwd = 8'hd4; 8'h1a: sbox_fwd = 8'ha2; 8'h1b: sbox_fwd = 8'haf;
      8'h1c: sbox_fwd = 8'h9c; 8'h1d: sbox_fwd = 8'ha4; 8'h1e: sbox_fwd = 8'h72; 8'h1f: sbox_fwd = 8'hc0;
      8'h20: sbox_fwd = 8'hb7; 8'h21: sbox_fwd = 8'hfd; 8'h22: sbox_fwd = 8'h93; 8'h23: sbox_fwd = 8'h26;
      8'h24: sbox_fwd = 8'h36; 8'h25: sbox_fwd = 8'h3f; 8'h26: sbox_fwd = 8'hf7; 8'h27: sbox_fwd = 8'hcc;
      8'h28: sbox_fwd = 8'h34; 8'h29: sbox_fwd = 8'ha5; 8'h2a: sbox_fwd = 8'he5; 8'h2b: sbox_fwd = 8'hf1;
      8'h2c: sbox_fwd = 8'h71; 8'h2d: sbox_fwd = 8'hd8; 8'h2e: sbox_fwd = 8'h31; 8'h2f: sbox_fwd = 8'h15;
      8'h30: sbox_fwd = 8'h04; 8'h31: sbox_fwd = 8'hc7; 8'h32: sbox_fwd = 8'h23; 8'h33: sbox_fwd = 8'hc3;
      8'h34: sbox_fwd = 8'h18; 8'h35: sbox_fwd = 8'h96; 8'h36: sbox_fwd = 8'h05; 8'h37: sbox_fwd = 8'h9a;
      8'h38: sbox_fwd = 8'h07; 8'h39: sbox_fwd = 8'h12; 8'h3a: sbox_fwd = 8'h80; 8'h3b: sbox_fwd = 8'he2;
      8'h3c: sbox_fwd = 8'heb; 8'h3d: sbox_fwd = 8'h27; 8'h3e: sbox_fwd = 8'hb2; 8'h3f: sbox_fwd = 8'h75;
      8'h40: sbox_fwd = 8'h09; 8'h41: sbox_fwd = 8'h83; 8'h42: sbox_fwd = 8'h2c; 8'h43: sbox_fwd = 8'h1a;
      8'h44: sbox_fwd = 8'h1b; 8'h45: sbox_fwd = 8'h6e; 8'h46: sbox_fwd = 8'h5a; 8'h47: sbox_fwd = 8'ha0;
      8'h48: sbox_fwd = 8'h52; 8'h49: sbox_fwd = 8'h3b; 8'h4a: sbox_fwd = 8'hd6; 8'h4b: sbox_fwd = 8'hb3;
      8'h4c: sbox_fwd = 8'h29; 8'h4d: sbox_fwd = 8'he3; 8'h4e: sbox_fwd = 8'h2f; 8'h4f: sbox_fwd = 8'h84;
      8'h50: sbox_fwd = 8'h53; 8'h51: sbox_fwd = 8'hd1; 8'h52: sbox_fwd = 8'h00; 8'h53: sbox_fwd = 8'hed;
      8'h54: sbox_fwd = 8'h20; 8'h55: sbox_fwd = 8'hfc; 8'h56: sbox_fwd = 8'hb1; 8'h57: sbox_fwd = 8'h5b;
      8'h58: sbox_fwd = 8'h6a; 8'h59: sbox_fwd = 8'hcb; 8'h5a: sbox_fwd = 8'hbe; 8'h5b: sbox_fwd = 8'h39;
      8'h5c: sbox_fwd = 8'h4a; 8'h5d: sbox_fwd = 8'h4c; 8'h5e: sbox_fwd = 8'h58; 8'h5f: sbox_fwd = 8'hcf;
      8'h60: sbox_fwd = 8'hd0; 8'h61: sbox_fwd = 8'hef; 8'h62: sbox_fwd = 8'haa; 8'h63: sbox_fwd = 8'hfb;
      8'h64: sbox_fwd = 8'h43; 8'h65: sbox_fwd = 8'h4d; 8'h66: sbox_fwd = 8'h33; 8'h67: sbox_fwd = 8'h85;
      8'h68: sbox_fwd = 8'h45; 8'h69: sbox_fwd = 8'hf9; 8'h6a: sbox_fwd = 8'h02; 8'h6b: sbox_fwd = 8'h7f;
      8'h6c: sbox_fwd = 8'h50; 8'h6d: sbox_fwd = 8'h3c; 8'h6e: sbox_fwd = 8'h9f; 8'h6f: sbox_fwd = 8'ha8;
      8'h70: sbox_fwd = 8'h51; 8'h71: sbox_fwd = 8'ha3; 8'h72: sbox_fwd = 8'h40; 8'h73: sbox_fwd = 8'h8f;
      8'h74: sbox_fwd = 8'h92; 8'h75: sbox_fwd = 8'h9d; 8'h76: sbox_fwd = 8'h38; 8'h77: sbox_fwd = 8'hf5;
      8'h78: sbox_fwd = 8'hbc; 8'h79: sbox_fwd = 8'hb6; 8'h7a: sbox_fwd = 8'hda; 8'h7b: sbox_fwd = 8'h21;
      8'h7c: sbox_fwd = 8'h10; 8'h7d: sbox_fwd = 8'hff; 8'h7e: sbox_fwd = 8'hf3; 8'h7f: sbox_fwd = 8'hd2;
      8'h80: sbox_fwd = 8'hcd; 8'h81: sbox_fwd = 8'h0c; 8'h82: sbox_fwd = 8'h13; 8'h83: sbox_fwd = 8'hec;
      8'h84: sbox_fwd = 8'h5f; 8'h85: sbox_fwd = 8'h97; 8'h86: sbox_fwd = 8'h44; 8'h87: sbox_fwd = 8'h17;
      8'h88: sbox_fwd = 8'hc4; 8'h89: sbox_fwd = 8'ha7; 8'h8a: sbox_fwd = 8'h7e; 8'h8b: sbox_fwd = 8'h3d;
      8'h8c: sbox_fwd = 8'h64; 8'h8d: sbox_fwd = 8'h5d; 8'h8e: sbox_fwd = 8'h19; 8'h8f: sbox_fwd = 8'h73;
      8'h90: sbox_fwd = 8'h60; 8'h91: sbox_fwd = 8'h81; 8'h92: sbox_fwd = 8'h4f; 8'h93: sbox_fwd = 8'hdc;
      8'h94: sbox_fwd = 8'h22; 8'h95: sbox_fwd = 8'h2a; 8'h96: sbox_fwd = 8'h90; 8'h97: sbox_fwd = 8'h88;
      8'h98: sbox_fwd = 8'h46; 8'h99: sbox_fwd = 8'hee; 8'h9a: sbox_fwd = 8'hb8; 8'h9b: sbox_fwd = 8'h14;
      8'h9c: sbox_fwd = 8'hde; 8'h9d: sbox_fwd = 8'h5e; 8'h9e: sbox_fwd = 8'h0b; 8'h9f: sbox_fwd = 8'hdb;
      8'ha0: sbox_fwd = 8'he0; 8'ha1: sbox_fwd = 8'h32; 8'ha2: sbox_fwd = 8'h3a; 8'ha3: sbox_fwd = 8'h0a;
      8'ha4: sbox_fwd = 8'h49; 8'ha5: sbox_fwd = 8'h06; 8'ha6: sbox_fwd = 8'h24; 8'ha7: sbox_fwd = 8'h5c;
      8'ha8: sbox_fwd = 8'hc2; 8'ha9: sbox_fwd = 8'hd3; 8'haa: sbox_fwd = 8'hac; 8'hab: sbox_fwd = 8'h62;
      8'hac: sbox_fwd = 8'h91; 8'had: sbox_fwd = 8'h95; 8'hae: sbox_fwd = 8'he4; 8'haf: sbox_fwd = 8'h79;
      8'hb0: sbox_fwd = 8'he7; 8'hb1: sbox_fwd = 8'hc8; 8'hb2: sbox_fwd = 8'h37; 8'hb3: sbox_fwd = 8'h6d;
      8'hb4: sbox_fwd = 8'h8d; 8'hb5: sbox_fwd = 8'hd5; 8'hb6: sbox_fwd = 8'h4e; 8'hb7: sbox_fwd = 8'ha9;
      8'hb8: sbox_fwd = 8'h6c; 8'hb9: sbox_fwd = 8'h56; 8'hba: sbox_fwd = 8'hf4; 8'hbb: sbox_fwd = 8'hea;
      8'hbc: sbox_fwd = 8'h65; 8'hbd: sbox_fwd = 8'h7a; 8'hbe: sbox_fwd = 8'hae; 8'hbf: sbox_fwd = 8'h08;
      8'hc0: sbox_fwd = 8'hba; 8'hc1: sbox_fwd = 8'h78; 8'hc2: sbox_fwd = 8'h25; 8'hc3: sbox_fwd = 8'h2e;
      8'hc4: sbox_fwd = 8'h1c; 8'hc5: sbox_fwd = 8'ha6; 8'hc6: sbox_fwd = 8'hb4; 8'hc7: sbox_fwd = 8'hc6;
      8'hc8: sbox_fwd = 8'he8; 8'hc9: sbox_fwd = 8'hdd; 8'hca: sbox_fwd = 8'h74; 8'hcb: sbox_fwd = 8'h1f;
      8'hcc: sbox_fwd = 8'h4b; 8'hcd: sbox_fwd = 8'hbd; 8'hce: sbox_fwd = 8'h8b; 8'hcf: sbox_fwd = 8'h8a;
      8'hd0: sbox_fwd = 8'h70; 8'hd1: sbox_fwd = 8'h3e; 8'hd2: sbox_fwd = 8'hb5; 8'hd3: sbox_fwd = 8'h66;
      8'hd4: sbox_fwd = 8'h48; 8'hd5: sbox_fwd = 8'h03; 8'hd6: sbox_fwd = 8'hf6; 8'hd7: sbox_fwd = 8'h0e;
      8'hd8: sbox_fwd = 8'h61; 8'hd9: sbox_fwd = 8'h35; 8'hda: sbox_fwd = 8'h57; 8'hdb: sbox_fwd = 8'hb9;
      8'hdc: sbox_fwd = 8'h86; 8'hdd: sbox_fwd = 8'hc1; 8'hde: sbox_fwd = 8'h1d; 8'hdf: sbox_fwd = 8'h9e;
      8'he0: sbox_fwd = 8'he1; 8'he1: sbox_fwd = 8'hf8; 8'he2: sbox_fwd = 8'h98; 8'he3: sbox_fwd = 8'h11;
      8'he4: sbox_fwd = 8'h69; 8'he5: sbox_fwd = 8'hd9; 8'he6: sbox_fwd = 8'h8e; 8'he7: sbox_fwd = 8'h94;
      8'he8: sbox_fwd = 8'h9b; 8'he9: sbox_fwd = 8'h1e; 8'hea: sbox_fwd = 8'h87; 8'heb: sbox_fwd = 8'he9;
      8'hec: sbox_fwd = 8'hce; 8'hed: sbox_fwd = 8'h55; 8'hee: sbox_fwd = 8'h28; 8'hef: sbox_fwd = 8'hdf;
      8'hf0: sbox_fwd = 8'h8c; 8'hf1: sbox_fwd = 8'ha1; 8'hf2: sbox_fwd = 8'h89; 8'hf3: sbox_fwd = 8'h0d;
      8'hf4: sbox_fwd = 8'hbf; 8'hf5: sbox_fwd = 8'he6; 8'hf6: sbox_fwd = 8'h42; 8'hf7: sbox_fwd = 8'h68;
      8'hf8: sbox_fwd = 8'h41; 8'hf9: sbox_fwd = 8'h99; 8'hfa: sbox_fwd = 8'h2d; 8'hfb: sbox_fwd = 8'h0f;
      8'hfc: sbox_fwd = 8'hb0; 8'hfd: sbox_fwd = 8'h54; 8'hfe: sbox_fwd = 8'hbb; 8'hff: sbox_fwd = 8'h16;
    endcase
  endfunction

  // Inverse S-box lookup table
  function automatic logic [7:0] sbox_inv(input logic [7:0] in);
    unique case (in)
      8'h00: sbox_inv = 8'h52; 8'h01: sbox_inv = 8'h09; 8'h02: sbox_inv = 8'h6a; 8'h03: sbox_inv = 8'hd5;
      8'h04: sbox_inv = 8'h30; 8'h05: sbox_inv = 8'h36; 8'h06: sbox_inv = 8'ha5; 8'h07: sbox_inv = 8'h38;
      8'h08: sbox_inv = 8'hbf; 8'h09: sbox_inv = 8'h40; 8'h0a: sbox_inv = 8'ha3; 8'h0b: sbox_inv = 8'h9e;
      8'h0c: sbox_inv = 8'h81; 8'h0d: sbox_inv = 8'hf3; 8'h0e: sbox_inv = 8'hd7; 8'h0f: sbox_inv = 8'hfb;
      8'h10: sbox_inv = 8'h7c; 8'h11: sbox_inv = 8'he3; 8'h12: sbox_inv = 8'h39; 8'h13: sbox_inv = 8'h82;
      8'h14: sbox_inv = 8'h9b; 8'h15: sbox_inv = 8'h2f; 8'h16: sbox_inv = 8'hff; 8'h17: sbox_inv = 8'h87;
      8'h18: sbox_inv = 8'h34; 8'h19: sbox_inv = 8'h8e; 8'h1a: sbox_inv = 8'h43; 8'h1b: sbox_inv = 8'h44;
      8'h1c: sbox_inv = 8'hc4; 8'h1d: sbox_inv = 8'hde; 8'h1e: sbox_inv = 8'he9; 8'h1f: sbox_inv = 8'hcb;
      8'h20: sbox_inv = 8'h54; 8'h21: sbox_inv = 8'h7b; 8'h22: sbox_inv = 8'h94; 8'h23: sbox_inv = 8'h32;
      8'h24: sbox_inv = 8'ha6; 8'h25: sbox_inv = 8'hc2; 8'h26: sbox_inv = 8'h23; 8'h27: sbox_inv = 8'h3d;
      8'h28: sbox_inv = 8'hee; 8'h29: sbox_inv = 8'h4c; 8'h2a: sbox_inv = 8'h95; 8'h2b: sbox_inv = 8'h0b;
      8'h2c: sbox_inv = 8'h42; 8'h2d: sbox_inv = 8'hfa; 8'h2e: sbox_inv = 8'hc3; 8'h2f: sbox_inv = 8'h4e;
      8'h30: sbox_inv = 8'h08; 8'h31: sbox_inv = 8'h2e; 8'h32: sbox_inv = 8'ha1; 8'h33: sbox_inv = 8'h66;
      8'h34: sbox_inv = 8'h28; 8'h35: sbox_inv = 8'hd9; 8'h36: sbox_inv = 8'h24; 8'h37: sbox_inv = 8'hb2;
      8'h38: sbox_inv = 8'h76; 8'h39: sbox_inv = 8'h5b; 8'h3a: sbox_inv = 8'ha2; 8'h3b: sbox_inv = 8'h49;
      8'h3c: sbox_inv = 8'h6d; 8'h3d: sbox_inv = 8'h8b; 8'h3e: sbox_inv = 8'hd1; 8'h3f: sbox_inv = 8'h25;
      8'h40: sbox_inv = 8'h72; 8'h41: sbox_inv = 8'hf8; 8'h42: sbox_inv = 8'hf6; 8'h43: sbox_inv = 8'h64;
      8'h44: sbox_inv = 8'h86; 8'h45: sbox_inv = 8'h68; 8'h46: sbox_inv = 8'h98; 8'h47: sbox_inv = 8'h16;
      8'h48: sbox_inv = 8'hd4; 8'h49: sbox_inv = 8'ha4; 8'h4a: sbox_inv = 8'h5c; 8'h4b: sbox_inv = 8'hcc;
      8'h4c: sbox_inv = 8'h5d; 8'h4d: sbox_inv = 8'h65; 8'h4e: sbox_inv = 8'hb6; 8'h4f: sbox_inv = 8'h92;
      8'h50: sbox_inv = 8'h6c; 8'h51: sbox_inv = 8'h70; 8'h52: sbox_inv = 8'h48; 8'h53: sbox_inv = 8'h50;
      8'h54: sbox_inv = 8'hfd; 8'h55: sbox_inv = 8'hed; 8'h56: sbox_inv = 8'hb9; 8'h57: sbox_inv = 8'hda;
      8'h58: sbox_inv = 8'h5e; 8'h59: sbox_inv = 8'h15; 8'h5a: sbox_inv = 8'h46; 8'h5b: sbox_inv = 8'h57;
      8'h5c: sbox_inv = 8'ha7; 8'h5d: sbox_inv = 8'h8d; 8'h5e: sbox_inv = 8'h9d; 8'h5f: sbox_inv = 8'h84;
      8'h60: sbox_inv = 8'h90; 8'h61: sbox_inv = 8'hd8; 8'h62: sbox_inv = 8'hab; 8'h63: sbox_inv = 8'h00;
      8'h64: sbox_inv = 8'h8c; 8'h65: sbox_inv = 8'hbc; 8'h66: sbox_inv = 8'hd3; 8'h67: sbox_inv = 8'h0a;
      8'h68: sbox_inv = 8'hf7; 8'h69: sbox_inv = 8'he4; 8'h6a: sbox_inv = 8'h58; 8'h6b: sbox_inv = 8'h05;
      8'h6c: sbox_inv = 8'hb8; 8'h6d: sbox_inv = 8'hb3; 8'h6e: sbox_inv = 8'h45; 8'h6f: sbox_inv = 8'h06;
      8'h70: sbox_inv = 8'hd0; 8'h71: sbox_inv = 8'h2c; 8'h72: sbox_inv = 8'h1e; 8'h73: sbox_inv = 8'h8f;
      8'h74: sbox_inv = 8'hca; 8'h75: sbox_inv = 8'h3f; 8'h76: sbox_inv = 8'h0f; 8'h77: sbox_inv = 8'h02;
      8'h78: sbox_inv = 8'hc1; 8'h79: sbox_inv = 8'haf; 8'h7a: sbox_inv = 8'hbd; 8'h7b: sbox_inv = 8'h03;
      8'h7c: sbox_inv = 8'h01; 8'h7d: sbox_inv = 8'h13; 8'h7e: sbox_inv = 8'h8a; 8'h7f: sbox_inv = 8'h6b;
      8'h80: sbox_inv = 8'h3a; 8'h81: sbox_inv = 8'h91; 8'h82: sbox_inv = 8'h11; 8'h83: sbox_inv = 8'h41;
      8'h84: sbox_inv = 8'h4f; 8'h85: sbox_inv = 8'h67; 8'h86: sbox_inv = 8'hdc; 8'h87: sbox_inv = 8'hea;
      8'h88: sbox_inv = 8'h97; 8'h89: sbox_inv = 8'hf2; 8'h8a: sbox_inv = 8'hcf; 8'h8b: sbox_inv = 8'hce;
      8'h8c: sbox_inv = 8'hf0; 8'h8d: sbox_inv = 8'hb4; 8'h8e: sbox_inv = 8'he6; 8'h8f: sbox_inv = 8'h73;
      8'h90: sbox_inv = 8'h96; 8'h91: sbox_inv = 8'hac; 8'h92: sbox_inv = 8'h74; 8'h93: sbox_inv = 8'h22;
      8'h94: sbox_inv = 8'he7; 8'h95: sbox_inv = 8'had; 8'h96: sbox_inv = 8'h35; 8'h97: sbox_inv = 8'h85;
      8'h98: sbox_inv = 8'he2; 8'h99: sbox_inv = 8'hf9; 8'h9a: sbox_inv = 8'h37; 8'h9b: sbox_inv = 8'he8;
      8'h9c: sbox_inv = 8'h1c; 8'h9d: sbox_inv = 8'h75; 8'h9e: sbox_inv = 8'hdf; 8'h9f: sbox_inv = 8'h6e;
      8'ha0: sbox_inv = 8'h47; 8'ha1: sbox_inv = 8'hf1; 8'ha2: sbox_inv = 8'h1a; 8'ha3: sbox_inv = 8'h71;
      8'ha4: sbox_inv = 8'h1d; 8'ha5: sbox_inv = 8'h29; 8'ha6: sbox_inv = 8'hc5; 8'ha7: sbox_inv = 8'h89;
      8'ha8: sbox_inv = 8'h6f; 8'ha9: sbox_inv = 8'hb7; 8'haa: sbox_inv = 8'h62; 8'hab: sbox_inv = 8'h0e;
      8'hac: sbox_inv = 8'haa; 8'had: sbox_inv = 8'h18; 8'hae: sbox_inv = 8'hbe; 8'haf: sbox_inv = 8'h1b;
      8'hb0: sbox_inv = 8'hfc; 8'hb1: sbox_inv = 8'h56; 8'hb2: sbox_inv = 8'h3e; 8'hb3: sbox_inv = 8'h4b;
      8'hb4: sbox_inv = 8'hc6; 8'hb5: sbox_inv = 8'hd2; 8'hb6: sbox_inv = 8'h79; 8'hb7: sbox_inv = 8'h20;
      8'hb8: sbox_inv = 8'h9a; 8'hb9: sbox_inv = 8'hdb; 8'hba: sbox_inv = 8'hc0; 8'hbb: sbox_inv = 8'hfe;
      8'hbc: sbox_inv = 8'h78; 8'hbd: sbox_inv = 8'hcd; 8'hbe: sbox_inv = 8'h5a; 8'hbf: sbox_inv = 8'hf4;
      8'hc0: sbox_inv = 8'h1f; 8'hc1: sbox_inv = 8'hdd; 8'hc2: sbox_inv = 8'ha8; 8'hc3: sbox_inv = 8'h33;
      8'hc4: sbox_inv = 8'h88; 8'hc5: sbox_inv = 8'h07; 8'hc6: sbox_inv = 8'hc7; 8'hc7: sbox_inv = 8'h31;
      8'hc8: sbox_inv = 8'hb1; 8'hc9: sbox_inv = 8'h12; 8'hca: sbox_inv = 8'h10; 8'hcb: sbox_inv = 8'h59;
      8'hcc: sbox_inv = 8'h27; 8'hcd: sbox_inv = 8'h80; 8'hce: sbox_inv = 8'hec; 8'hcf: sbox_inv = 8'h5f;
      8'hd0: sbox_inv = 8'h60; 8'hd1: sbox_inv = 8'h51; 8'hd2: sbox_inv = 8'h7f; 8'hd3: sbox_inv = 8'ha9;
      8'hd4: sbox_inv = 8'h19; 8'hd5: sbox_inv = 8'hb5; 8'hd6: sbox_inv = 8'h4a; 8'hd7: sbox_inv = 8'h0d;
      8'hd8: sbox_inv = 8'h2d; 8'hd9: sbox_inv = 8'he5; 8'hda: sbox_inv = 8'h7a; 8'hdb: sbox_inv = 8'h9f;
      8'hdc: sbox_inv = 8'h93; 8'hdd: sbox_inv = 8'hc9; 8'hde: sbox_inv = 8'h9c; 8'hdf: sbox_inv = 8'hef;
      8'he0: sbox_inv = 8'ha0; 8'he1: sbox_inv = 8'he0; 8'he2: sbox_inv = 8'h3b; 8'he3: sbox_inv = 8'h4d;
      8'he4: sbox_inv = 8'hae; 8'he5: sbox_inv = 8'h2a; 8'he6: sbox_inv = 8'hf5; 8'he7: sbox_inv = 8'hb0;
      8'he8: sbox_inv = 8'hc8; 8'he9: sbox_inv = 8'heb; 8'hea: sbox_inv = 8'hbb; 8'heb: sbox_inv = 8'h3c;
      8'hec: sbox_inv = 8'h83; 8'hed: sbox_inv = 8'h53; 8'hee: sbox_inv = 8'h99; 8'hef: sbox_inv = 8'h61;
      8'hf0: sbox_inv = 8'h17; 8'hf1: sbox_inv = 8'h2b; 8'hf2: sbox_inv = 8'h04; 8'hf3: sbox_inv = 8'h7e;
      8'hf4: sbox_inv = 8'hba; 8'hf5: sbox_inv = 8'h77; 8'hf6: sbox_inv = 8'hd6; 8'hf7: sbox_inv = 8'h26;
      8'hf8: sbox_inv = 8'he1; 8'hf9: sbox_inv = 8'h69; 8'hfa: sbox_inv = 8'h14; 8'hfb: sbox_inv = 8'h63;
      8'hfc: sbox_inv = 8'h55; 8'hfd: sbox_inv = 8'h21; 8'hfe: sbox_inv = 8'h0c; 8'hff: sbox_inv = 8'h7d;
    endcase
  endfunction

  ///////////////////////////
  //  GF(2^8) Arithmetic   //
  ///////////////////////////

  // Multiply by 2 in GF(2^8) with irreducible polynomial x^8 + x^4 + x^3 + x + 1 (0x11b)
  function automatic logic [7:0] xtime(input logic [7:0] a);
    xtime = {a[6:0], 1'b0} ^ (a[7] ? 8'h1b : 8'h00);
  endfunction

  // Multiply two elements in GF(2^8)
  function automatic logic [7:0] gf_mul(input logic [7:0] a, input logic [7:0] b);
    logic [7:0] p;
    logic [7:0] aa;
    p  = '0;
    aa = a;
    for (int i = 0; i < 8; i++) begin
      if (b[i]) p = p ^ aa;
      aa = xtime(aa);
    end
    gf_mul = p;
  endfunction

  ///////////////////////////
  //  AES Transformations  //
  ///////////////////////////

  // State as a 4x4 byte matrix (column-major, matching AES spec)
  // state[col][row] — AES state is stored column-major in 32-bit words:
  //   word0 = state_i[31:0]   = column 0 = {s[0][0], s[1][0], s[2][0], s[3][0]}
  //   word1 = state_i[63:32]  = column 1 = {s[0][1], s[1][1], s[2][1], s[3][1]}
  //   word2 = state_i[95:64]  = column 2 = ...
  //   word3 = state_i[127:96] = column 3 = ...

  // SubBytes: apply forward S-box to all 16 bytes
  function automatic logic [127:0] sub_bytes(input logic [127:0] s);
    for (int i = 0; i < 16; i++)
      sub_bytes[i*8 +: 8] = sbox_fwd(s[i*8 +: 8]);
  endfunction

  // InvSubBytes: apply inverse S-box to all 16 bytes
  function automatic logic [127:0] inv_sub_bytes(input logic [127:0] s);
    for (int i = 0; i < 16; i++)
      inv_sub_bytes[i*8 +: 8] = sbox_inv(s[i*8 +: 8]);
  endfunction

  // ShiftRows: cyclic left shift of rows
  // Row 0: no shift, Row 1: shift 1, Row 2: shift 2, Row 3: shift 3
  // Byte layout within state (column-major, 32-bit words):
  //   Byte index: [col*4 + row]
  //   Row r, Col c -> byte at bit position [(c*32) + (r*8) +: 8]
  function automatic logic [127:0] shift_rows(input logic [127:0] s);
    logic [7:0] b [4][4]; // b[row][col]
    logic [7:0] r [4][4]; // result
    // Unpack to row-col form
    for (int c = 0; c < 4; c++)
      for (int rr = 0; rr < 4; rr++)
        b[rr][c] = s[(c*32) + (rr*8) +: 8];
    // Shift rows
    for (int rr = 0; rr < 4; rr++)
      for (int c = 0; c < 4; c++)
        r[rr][c] = b[rr][(c + rr) % 4];
    // Repack
    for (int c = 0; c < 4; c++)
      for (int rr = 0; rr < 4; rr++)
        shift_rows[(c*32) + (rr*8) +: 8] = r[rr][c];
  endfunction

  // InvShiftRows: cyclic right shift of rows
  function automatic logic [127:0] inv_shift_rows(input logic [127:0] s);
    logic [7:0] b [4][4];
    logic [7:0] r [4][4];
    for (int c = 0; c < 4; c++)
      for (int rr = 0; rr < 4; rr++)
        b[rr][c] = s[(c*32) + (rr*8) +: 8];
    for (int rr = 0; rr < 4; rr++)
      for (int c = 0; c < 4; c++)
        r[rr][c] = b[rr][(c - rr + 4) % 4];
    for (int c = 0; c < 4; c++)
      for (int rr = 0; rr < 4; rr++)
        inv_shift_rows[(c*32) + (rr*8) +: 8] = r[rr][c];
  endfunction

  // MixColumns: operate on each 32-bit column
  function automatic logic [127:0] mix_columns(input logic [127:0] s);
    logic [7:0] b0, b1, b2, b3;
    for (int c = 0; c < 4; c++) begin
      b0 = s[(c*32) +  0 +: 8];
      b1 = s[(c*32) +  8 +: 8];
      b2 = s[(c*32) + 16 +: 8];
      b3 = s[(c*32) + 24 +: 8];
      mix_columns[(c*32) +  0 +: 8] = gf_mul(8'h02, b0) ^ gf_mul(8'h03, b1) ^ b2             ^ b3;
      mix_columns[(c*32) +  8 +: 8] = b0             ^ gf_mul(8'h02, b1) ^ gf_mul(8'h03, b2) ^ b3;
      mix_columns[(c*32) + 16 +: 8] = b0             ^ b1             ^ gf_mul(8'h02, b2) ^ gf_mul(8'h03, b3);
      mix_columns[(c*32) + 24 +: 8] = gf_mul(8'h03, b0) ^ b1             ^ b2             ^ gf_mul(8'h02, b3);
    end
  endfunction

  // InvMixColumns
  function automatic logic [127:0] inv_mix_columns(input logic [127:0] s);
    logic [7:0] b0, b1, b2, b3;
    for (int c = 0; c < 4; c++) begin
      b0 = s[(c*32) +  0 +: 8];
      b1 = s[(c*32) +  8 +: 8];
      b2 = s[(c*32) + 16 +: 8];
      b3 = s[(c*32) + 24 +: 8];
      inv_mix_columns[(c*32) +  0 +: 8] = gf_mul(8'h0e, b0) ^ gf_mul(8'h0b, b1) ^ gf_mul(8'h0d, b2) ^ gf_mul(8'h09, b3);
      inv_mix_columns[(c*32) +  8 +: 8] = gf_mul(8'h09, b0) ^ gf_mul(8'h0e, b1) ^ gf_mul(8'h0b, b2) ^ gf_mul(8'h0d, b3);
      inv_mix_columns[(c*32) + 16 +: 8] = gf_mul(8'h0d, b0) ^ gf_mul(8'h09, b1) ^ gf_mul(8'h0e, b2) ^ gf_mul(8'h0b, b3);
      inv_mix_columns[(c*32) + 24 +: 8] = gf_mul(8'h0b, b0) ^ gf_mul(8'h0d, b1) ^ gf_mul(8'h09, b2) ^ gf_mul(8'h0e, b3);
    end
  endfunction

  ////////////////////////
  //  AES Key Schedule  //
  ////////////////////////

  // Round constants for AES-128/256 key schedule
  function automatic logic [7:0] aes_rcon(input logic [3:0] rnd);
    unique case (rnd)
      4'h0: aes_rcon = 8'h01;
      4'h1: aes_rcon = 8'h02;
      4'h2: aes_rcon = 8'h04;
      4'h3: aes_rcon = 8'h08;
      4'h4: aes_rcon = 8'h10;
      4'h5: aes_rcon = 8'h20;
      4'h6: aes_rcon = 8'h40;
      4'h7: aes_rcon = 8'h80;
      4'h8: aes_rcon = 8'h1b;
      4'h9: aes_rcon = 8'h36;
      default: aes_rcon = 8'h00;
    endcase
  endfunction

  // SubWord: apply S-box to each byte of a 32-bit word
  function automatic logic [31:0] sub_word(input logic [31:0] w);
    for (int i = 0; i < 4; i++)
      sub_word[i*8 +: 8] = sbox_fwd(w[i*8 +: 8]);
  endfunction

  // RotWord: rotate 32-bit word left by 8 bits (byte-level)
  function automatic logic [31:0] rot_word(input logic [31:0] w);
    rot_word = {w[23:0], w[31:24]};
  endfunction

  //////////////////////////
  //  Operation Dispatch  //
  //////////////////////////

  logic [127:0] state;
  logic [127:0] rkey;
  logic [127:0] aes_result;

  assign state = state_i;
  assign rkey  = round_key_i;

  always_comb begin
    aes_result = '0;

    unique case (op_i)
      // Encrypt middle round: ShiftRows -> SubBytes -> MixColumns -> AddRoundKey
      VAESEM_VV, VAESEM_VS: begin
        aes_result = mix_columns(sub_bytes(shift_rows(state))) ^ rkey;
      end

      // Encrypt final round: ShiftRows -> SubBytes -> AddRoundKey (no MixColumns)
      VAESEF_VV, VAESEF_VS: begin
        aes_result = sub_bytes(shift_rows(state)) ^ rkey;
      end

      // Decrypt middle round: InvShiftRows -> InvSubBytes -> InvMixColumns -> AddRoundKey
      VAESDM_VV, VAESDM_VS: begin
        aes_result = inv_mix_columns(inv_sub_bytes(inv_shift_rows(state))) ^ rkey;
      end

      // Decrypt final round: InvShiftRows -> InvSubBytes -> AddRoundKey (no InvMixColumns)
      VAESDF_VV, VAESDF_VS: begin
        aes_result = inv_sub_bytes(inv_shift_rows(state)) ^ rkey;
      end

      // Round zero: just AddRoundKey
      VAESZ_VS: begin
        aes_result = state ^ rkey;
      end

      // vaeskf1: AES-128 forward key schedule
      // Input: vs2 = current round key (4 words), uimm = round number (1-10)
      // Output: next round key
      VAESKF1: begin
        automatic logic [31:0] w0 = rkey[ 31:  0];
        automatic logic [31:0] w1 = rkey[ 63: 32];
        automatic logic [31:0] w2 = rkey[ 95: 64];
        automatic logic [31:0] w3 = rkey[127: 96];
        automatic logic [31:0] rcon_word = {24'h0, aes_rcon(uimm_i[3:0] - 4'h1)};
        automatic logic [31:0] tmp = sub_word(rot_word(w3)) ^ rcon_word;
        automatic logic [31:0] nw0 = w0 ^ tmp;
        automatic logic [31:0] nw1 = w1 ^ nw0;
        automatic logic [31:0] nw2 = w2 ^ nw1;
        automatic logic [31:0] nw3 = w3 ^ nw2;
        aes_result = {nw3, nw2, nw1, nw0};
      end

      // vaeskf2: AES-256 forward key schedule
      // Input: vd = previous round key, vs2 = current round key, uimm = round number (2-14)
      // Output: next round key
      VAESKF2: begin
        automatic logic [31:0] prev0 = state[ 31:  0]; // from vd
        automatic logic [31:0] prev1 = state[ 63: 32];
        automatic logic [31:0] prev2 = state[ 95: 64];
        automatic logic [31:0] prev3 = state[127: 96];
        automatic logic [31:0] cur3  = rkey[127: 96];   // from vs2
        automatic logic [31:0] tmp;
        automatic logic [31:0] nw0, nw1, nw2, nw3;
        if (uimm_i[0]) begin
          // Odd round: SubWord only (no RotWord, no Rcon)
          tmp = sub_word(cur3);
        end else begin
          // Even round: SubWord(RotWord()) XOR Rcon
          tmp = sub_word(rot_word(cur3)) ^ {24'h0, aes_rcon(uimm_i[3:1] - 3'h1)};
        end
        nw0 = prev0 ^ tmp;
        nw1 = prev1 ^ nw0;
        nw2 = prev2 ^ nw1;
        nw3 = prev3 ^ nw2;
        aes_result = {nw3, nw2, nw1, nw0};
      end

      default: aes_result = '0;
    endcase
  end

  assign result_o = aes_result;

endmodule
