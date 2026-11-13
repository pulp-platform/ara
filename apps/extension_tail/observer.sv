// SPDX-License-Identifier: Apache-2.0
// Passive checks for the fixed two-lane/VLEN2048 extension regression.
`define ARA_OBS ara_tb.dut.i_ara_soc.i_system.i_ara
`define VALU_OBS(L) `ARA_OBS.gen_lanes[L].i_lane.i_vfus.i_valu
module extension_observer;
  import ara_pkg::*;
  import rvv_pkg::*;
  for (genvar lane = 0; lane < 2; lane++) begin : gen_observer
    bit active[NrVInsn], closed[NrVInsn];
    int writes[NrVInsn];
    int accepted, completed, total_writes, errors;
    always @(posedge `ARA_OBS.clk_i) begin
      if (!`ARA_OBS.rst_ni) begin
        accepted = 0; completed = 0; total_writes = 0; errors = 0;
        for (int id = 0; id < NrVInsn; id++) begin
          active[id] = 0; closed[id] = 0; writes[id] = 0;
        end
      end else begin
        if (`VALU_OBS(lane).vfu_operation_valid_i && `VALU_OBS(lane).alu_ready_o) begin
          automatic int id = `VALU_OBS(lane).vfu_operation_i.id;
          closed[id] = 0;
          if (`VALU_OBS(lane).vfu_operation_i.fill_agnostic) begin
            if (active[id]) begin errors++; $error("EXT_OBS reused live id"); end
            active[id] = 1; writes[id] = 0; accepted++;
            $display("EXT_ACCEPT lane=%0d id=%0d vl=%0d", lane, id,
                     `VALU_OBS(lane).vfu_operation_i.vl);
          end
        end
        if (`VALU_OBS(lane).alu_result_req_o && `VALU_OBS(lane).alu_result_gnt_i) begin
          automatic int id = `VALU_OBS(lane).alu_result_id_o;
          if (closed[id]) begin errors++; $error("EXT_OBS late write after done"); end
          if (active[id]) begin
            writes[id]++; total_writes++;
            if (`VALU_OBS(lane).alu_result_be_o !== 8'hff ||
                $isunknown({`VALU_OBS(lane).alu_result_addr_o,
                            `VALU_OBS(lane).alu_result_wdata_o})) begin
              errors++; $error("EXT_OBS unknown write or incomplete byte enable");
            end
          end
        end
        for (int id = 0; id < NrVInsn; id++) begin
          if (active[id] && `VALU_OBS(lane).alu_vinsn_done_o[id]) begin
            // Four 2048-bit destination registers / two lanes / 64-bit write.
            if (writes[id] != 64) begin errors++; $error("EXT_OBS premature done"); end
            $display("EXT_COMPLETE lane=%0d id=%0d writes=%0d", lane, id, writes[id]);
            active[id] = 0; closed[id] = 1; completed++;
          end
        end
      end
    end
    final begin
      for (int id = 0; id < NrVInsn; id++) if (active[id]) errors++;
      $display("EXT_OBS lane=%0d accepted=%0d completed=%0d writes=%0d errors=%0d",
               lane, accepted, completed, total_writes, errors);
      if (accepted != 4 || completed != 4 || total_writes != 256 || errors != 0)
        $error("EXT_OBS incomplete final state");
    end
  end
endmodule
`undef VALU_OBS
`undef ARA_OBS
