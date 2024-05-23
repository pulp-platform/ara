// 

module ara_lw_decoder import rvv_pkg::*; import ariane_pkg::*; #(
	parameter type x_issue_req_t = core_v_xif_pkg::x_issue_req_t,
	parameter type x_issue_resp_t = core_v_xif_pkg::x_issue_resp_t
	) (
    input  x_issue_req_t 		issue_req_i, 	// Issue interface request
    output x_issue_resp_t		issue_resp_o, 	// Issue interface response
    output scoreboard_entry_t 	instruction_o   // predecoded instruction
  );

  logic        is_rs1;
  logic        is_rs2;
  logic        is_rd;
  logic        is_fs1;
  logic        is_fs2;
  logic        is_fd;
  logic        is_vfp;      // is a vector floating-point instruction
  logic        is_load;
  logic        is_store;

  logic opVec, opLoad, opStore, opAmo, opSys;

  // Cast instruction into the `rvv_instruction_t` struct
  rvv_instruction_t instr;
  assign instr = rvv_instruction_t'(issue_req_i.instr);

  // Cast instruction into scalar `instruction_t` struct
  riscv::instruction_t instr_scalar;
  assign instr_scalar = riscv::instruction_t'(issue_req_i.instr);

  always_comb begin
    // Default values
    issue_resp_o.accept = 1'b0;
    is_rs1   = 1'b0;
    is_rs2   = 1'b0;
    is_rd    = 1'b0;
    is_fs1   = 1'b0;
    is_fs2   = 1'b0;
    is_fd    = 1'b0;
    is_vfp   = 1'b0;
    is_load  = instr.i_type.opcode == riscv::OpcodeLoadFp;
    is_store = instr.i_type.opcode == riscv::OpcodeStoreFp;

    opVec = '0;
    opLoad = '0;
    opStore = '0;
    opAmo = '0;
    opSys = '0;

    // Decode based on the opcode
    case (instr.i_type.opcode)

      // Arithmetic vector operations
      riscv::OpcodeVec: begin
        opVec = 1'b1;
        issue_resp_o.accept = 1'b1;
        case (instr.varith_type.func3)
          OPFVV: begin
            is_fd  = instr.varith_type.func6 == 6'b010_000; // VFWUNARY0
            is_vfp = 1'b1;
          end
          OPMVV: is_rd  = instr.varith_type.func6 == 6'b010_000; // VWXUNARY0
          OPIVX: is_rs1 = 1'b1 ;
          OPFVF: begin
            is_fs1 = 1'b1;
            is_vfp = 1'b1;
          end
          OPMVX: is_rs1 = 1'b1 ;
          OPCFG: begin
            is_rs1 = instr.vsetivli_type.func2 != 2'b11; // not vsetivli
            is_rs2 = instr.vsetvl_type.func7 == 7'b100_0000; // vsetvl
            is_rd  = 1'b1 ;
          end
        endcase
      end

      // Memory vector operations
      riscv::OpcodeLoadFp,
      riscv::OpcodeStoreFp: begin
        opLoad = 1'b1;
        opStore = 1'b1;
        case ({instr.vmem_type.mew, instr.vmem_type.width})
          4'b0000, //VLxE8/VSxE8
          4'b0101, //VLxE16/VSxE16
          4'b0110, //VLxE32/VSxE32
          4'b0111, //VLxE64/VSxE64
          4'b1000, //VLxE128/VSxE128
          4'b1101, //VLxE256/VSxE256
          4'b1110, //VLxE512/VSxE512
          4'b1111: begin //VLxE1024/VSxE1024
            issue_resp_o.accept = 1'b1 ;
            is_rs1   = 1'b1 ;
            is_rs2   = instr.vmem_type.mop == 2'b10; // Strided operation
          end
        endcase
      end

      // Atomic vector operations
      riscv::OpcodeAmo: begin
        opAmo = 1'b1;
        case (instr.vamo_type.width)
          3'b000, //VAMO*EI8.V
          3'b101, //VAMO*EI16.V
          3'b110, //VAMO*EI32.V
          3'b111: begin //VAMO*EI64.V
            issue_resp_o.accept = 1'b1;
            is_rs1   = 1'b1;
          end
        endcase
      end

      // CSRR/W instructions into vector CSRs
      riscv::OpcodeSystem: begin
        opSys = 1'b1;
        case (instr.i_type.funct3)
          3'b001, //CSRRW
          3'b010, //CSRRS,
          3'b011, //CSRRC,
          3'b101, //CSRRWI
          3'b110, //CSRRSI
          3'b111: begin //CSRRCI
            issue_resp_o.accept = is_vector_csr(riscv::csr_reg_t'(instr.i_type.imm));
            is_rs1   = is_vector_csr(riscv::csr_reg_t'(instr.i_type.imm));
            is_rs2   = is_vector_csr(riscv::csr_reg_t'(instr.i_type.imm));
            is_rd    = is_vector_csr(riscv::csr_reg_t'(instr.i_type.imm));
          end
        endcase
      end
    endcase
  end

  // Assign outputs for XIF issue resp
  assign issue_resp_o.writeback 		    = (is_rd || is_fd);
  assign issue_resp_o.register_read[0] 	= (is_rs1 || is_fs1);
  assign issue_resp_o.register_read[1] 	= (is_rs2 || is_fs2);
  assign issue_resp_o.is_vfp 			      = is_vfp;
 
endmodule