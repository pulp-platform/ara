// Description:
// Pattern classification (Sec. 5.1 of the prefetcher design). Purely
// combinational: RVV gives stride directly in the instruction encoding, so
// there is nothing to infer here, unlike a classic IP-stride prefetcher.
// VLE/VLSE are prefetchable; everything else (indexed, segment, all stores)
// is not.
//
// size_o mirrors pe_req_i.vtype.vsew (the AXI size encoding Ara's own
// addrgen already uses for this access) so that downstream hit comparisons
// can check {addr, size}, not just addr -- two accesses to the same address
// at different element widths must not be allowed to alias one another.
// size is computed independently of byte_stride_o so a bug in the stride
// arithmetic can never masquerade as a size bug or vice versa.

module pf_classifier import ara_pkg::*; #(
    parameter type pe_req_t = logic,
    parameter type stride_t = logic,
    parameter type size_t   = logic
  ) (
    input  pe_req_t pe_req_i,
    output logic    prefetchable_o,
    output stride_t byte_stride_o,
    output size_t   size_o
  );

  always_comb begin
    prefetchable_o = 1'b0;
    byte_stride_o  = '0;
    size_o         = '0;

    case (pe_req_i.op)
      VLE: begin
        prefetchable_o = 1'b1;
        byte_stride_o  = stride_t'(1) << pe_req_i.vtype.vsew;
        size_o         = size_t'(pe_req_i.vtype.vsew);
      end
      VLSE: begin
        prefetchable_o = 1'b1;
        byte_stride_o  = stride_t'(pe_req_i.stride);
        size_o         = size_t'(pe_req_i.vtype.vsew);
      end
      default: ; // VLXE/VSXE, segment ops, all stores: never prefetched
    endcase
  end

endmodule : pf_classifier
