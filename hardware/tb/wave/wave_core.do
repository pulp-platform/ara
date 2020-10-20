config wave -signalnamewidth 1

add wave -noupdate -group ariane -group core /core_tb/dut/i_ara_system/i_ariane/*

add wave -noupdate -group ariane -group frontend /core_tb/dut/i_ara_system/i_ariane/i_frontend/*
add wave -noupdate -group ariane -group frontend -group wt_icache /core_tb/dut/i_ara_system/i_ariane/i_cache_subsystem/i_wt_icache/*
add wave -noupdate -group ariane -group frontend -group ras /core_tb/dut/i_ara_system/i_ariane/i_frontend/i_ras/*
add wave -noupdate -group ariane -group frontend -group btb /core_tb/dut/i_ara_system/i_ariane/i_frontend/i_btb/*
add wave -noupdate -group ariane -group frontend -group bht /core_tb/dut/i_ara_system/i_ariane/i_frontend/i_bht/*
# add wave -noupdate -group ariane -group frontend -group instr_scan /core_tb/dut/i_ara_system/i_ariane/i_frontend/*/i_instr_scan/*
# add wave -noupdate -group ariane -group frontend -group fetch_fifo /core_tb/dut/i_ara_system/i_ariane/i_frontend/i_fetch_fifo/*

add wave -noupdate -group ariane -group id_stage -group decoder /core_tb/dut/i_ara_system/i_ariane/id_stage_i/decoder_i/*
add wave -noupdate -group ariane -group id_stage -group compressed_decoder /core_tb/dut/i_ara_system/i_ariane/id_stage_i/compressed_decoder_i/*
add wave -noupdate -group ariane -group id_stage -group instr_realigner /core_tb/dut/i_ara_system/i_ariane/id_stage_i/instr_realigner_i/*
add wave -noupdate -group ariane -group id_stage /core_tb/dut/i_ara_system/i_ariane/id_stage_i/*

add wave -noupdate -group ariane -group issue_stage -group scoreboard /core_tb/dut/i_ara_system/i_ariane/issue_stage_i/i_scoreboard/*
add wave -noupdate -group ariane -group issue_stage -group issue_read_operands /core_tb/dut/i_ara_system/i_ariane/issue_stage_i/i_issue_read_operands/*
add wave -noupdate -group ariane -group issue_stage -group rename /core_tb/dut/i_ara_system/i_ariane/issue_stage_i/i_re_name/*
add wave -noupdate -group ariane -group issue_stage /core_tb/dut/i_ara_system/i_ariane/issue_stage_i/*

add wave -noupdate -group ariane -group ex_stage -group alu /core_tb/dut/i_ara_system/i_ariane/ex_stage_i/alu_i/*
add wave -noupdate -group ariane -group ex_stage -group mult /core_tb/dut/i_ara_system/i_ariane/ex_stage_i/i_mult/*
add wave -noupdate -group ariane -group ex_stage -group mult -group mul /core_tb/dut/i_ara_system/i_ariane/ex_stage_i/i_mult/i_multiplier/*
add wave -noupdate -group ariane -group ex_stage -group mult -group div /core_tb/dut/i_ara_system/i_ariane/ex_stage_i/i_mult/i_div/*
add wave -noupdate -group ariane -group ex_stage -group fpu /core_tb/dut/i_ara_system/i_ariane/ex_stage_i/fpu_gen/fpu_i/*
#add wave -noupdate -group ariane -group ex_stage -group fpu -group fpnew /core_tb/dut/i_ara_system/i_ariane/ex_stage_i/fpu_gen/fpu_i/fpu_gen/i_fpnew_bulk/*
add wave -noupdate -group ariane -group ex_stage -group ara /core_tb/dut/i_ara_system/i_ariane/ex_stage_i/ara_gen/i_ara_frontend/*
add wave -noupdate -group ariane -group ex_stage -group ara -group decoder /core_tb/dut/i_ara_system/i_ariane/ex_stage_i/ara_gen/i_ara_frontend/i_decoder/*
add wave -noupdate -group ariane -group ex_stage -group ara -group issue -group vrf_organizer /core_tb/dut/i_ara_system/i_ariane/ex_stage_i/ara_gen/i_ara_frontend/i_dispatcher/i_vrf_organizer/*
add wave -noupdate -group ariane -group ex_stage -group ara -group issue /core_tb/dut/i_ara_system/i_ariane/ex_stage_i/ara_gen/i_ara_frontend/i_dispatcher/*

add wave -noupdate -group ariane -group ex_stage -group lsu /core_tb/dut/i_ara_system/i_ariane/ex_stage_i/lsu_i/*
add wave -noupdate -group ariane -group ex_stage -group lsu  -group lsu_bypass /core_tb/dut/i_ara_system/i_ariane/ex_stage_i/lsu_i/lsu_bypass_i/*
add wave -noupdate -group ariane -group ex_stage -group lsu -group mmu /core_tb/dut/i_ara_system/i_ariane/ex_stage_i/lsu_i/i_mmu/*
add wave -noupdate -group ariane -group ex_stage -group lsu -group mmu -group itlb /core_tb/dut/i_ara_system/i_ariane/ex_stage_i/lsu_i/i_mmu/i_itlb/*
add wave -noupdate -group ariane -group ex_stage -group lsu -group mmu -group dtlb /core_tb/dut/i_ara_system/i_ariane/ex_stage_i/lsu_i/i_mmu/i_dtlb/*
add wave -noupdate -group ariane -group ex_stage -group lsu -group mmu -group ptw /core_tb/dut/i_ara_system/i_ariane/ex_stage_i/lsu_i/i_mmu/i_ptw/*

add wave -noupdate -group ariane -group ex_stage -group lsu -group store_unit /core_tb/dut/i_ara_system/i_ariane/ex_stage_i/lsu_i/i_store_unit/*
add wave -noupdate -group ariane -group ex_stage -group lsu -group store_unit -group store_buffer /core_tb/dut/i_ara_system/i_ariane/ex_stage_i/lsu_i/i_store_unit/store_buffer_i/*

add wave -noupdate -group ariane -group ex_stage -group lsu -group load_unit /core_tb/dut/i_ara_system/i_ariane/ex_stage_i/lsu_i/i_load_unit/*

add wave -noupdate -group ariane -group ex_stage -group branch_unit /core_tb/dut/i_ara_system/i_ariane/ex_stage_i/branch_unit_i/*

add wave -noupdate -group ariane -group ex_stage -group csr_buffer /core_tb/dut/i_ara_system/i_ariane/ex_stage_i/csr_buffer_i/*
add wave -noupdate -group ariane -group ex_stage /core_tb/dut/i_ara_system/i_ariane/ex_stage_i/*

add wave -noupdate -group ariane -group commit_stage /core_tb/dut/i_ara_system/i_ariane/commit_stage_i/*

add wave -noupdate -group ariane -group csr_file /core_tb/dut/i_ara_system/i_ariane/csr_regfile_i/*

add wave -noupdate -group ariane -group controller /core_tb/dut/i_ara_system/i_ariane/controller_i/*

add wave -noupdate -group ariane -group wt_dcache /core_tb/dut/i_ara_system/i_ariane/i_cache_subsystem/i_wt_dcache/*

add wave -noupdate -group ariane -group perf_counters /core_tb/dut/i_ara_system/i_ariane/i_perf_counters/*

add wave -noupdate -group ariane -group dm_top /core_tb/dut/i_dm_top/*
add wave -noupdate -group ariane -group dm_top -group dm_csrs /core_tb/dut/i_dm_top/i_dm_csrs/*
add wave -noupdate -group ariane -group dm_top -group dm_mem /core_tb/dut/i_dm_top/i_dm_mem/*

add wave -noupdate -group ariane -group bootrom /core_tb/dut/i_bootrom/*

add wave -noupdate -group ariane -group tracer_if /core_tb/dut/i_ara_system/i_ariane/instr_tracer_i/tracer_if/*

add wave -group ariane -group SimJTAG /core_tb/dut/i_SimJTAG/*

add wave -group ariane -group dmi_jtag /core_tb/dut/i_dmi_jtag/*
add wave -group ariane -group dmi_jtag -group dmi_jtag_tap /core_tb/dut/i_dmi_jtag/i_dmi_jtag_tap/*
add wave -group ariane -group dmi_jtag -group dmi_cdc /core_tb/dut/i_dmi_jtag/i_dmi_cdc/*



add wave -noupdate -group ara

add wave -noupdate -group ara -group sequencer /core_tb/dut/i_ara_system/i_ara/i_sequencer/*

add wave -noupdate -group ara -group sldu /core_tb/dut/i_ara_system/i_ara/i_sldu/*

add wave -noupdate -group ara -group vlsu -group vldu /core_tb/dut/i_ara_system/i_ara/i_vlsu/i_vldu/*
add wave -noupdate -group ara -group vlsu -group vstu /core_tb/dut/i_ara_system/i_ara/i_vlsu/i_vstu/*
add wave -noupdate -group ara -group vlsu -group addrgen /core_tb/dut/i_ara_system/i_ara/i_vlsu/i_addrgen/*
add wave -noupdate -group ara -group vlsu /core_tb/dut/i_ara_system/i_ara/i_vlsu/*

for {set lane 0} {$lane < 4} {incr lane} {
    add wave -noupdate -group ara -group "lane[$lane]" -group sequencer /core_tb/dut/i_ara_system/i_ara/gen_lanes[$lane]/i_lane/i_lane_sequencer/*

    add wave -noupdate -group ara -group "lane[$lane]" -group operand_req -group arbiter /core_tb/dut/i_ara_system/i_ara/gen_lanes[$lane]/i_lane/i_opreq_stage/i_vrf_arbiter/*
    add wave -noupdate -group ara -group "lane[$lane]" -group operand_req /core_tb/dut/i_ara_system/i_ara/gen_lanes[$lane]/i_lane/i_opreq_stage/*

    add wave -noupdate -group ara -group "lane[$lane]" -group access_stage /core_tb/dut/i_ara_system/i_ara/gen_lanes[$lane]/i_lane/i_vaccess_stage/*

    add wave -noupdate -group ara -group "lane[$lane]" -group conv_stage -group mfpu_m /core_tb/dut/i_ara_system/i_ara/gen_lanes[$lane]/i_lane/i_vconv_stage/i_opqueue_mfpu_m/*
    add wave -noupdate -group ara -group "lane[$lane]" -group conv_stage -group mfpu_a /core_tb/dut/i_ara_system/i_ara/gen_lanes[$lane]/i_lane/i_vconv_stage/i_opqueue_mfpu_a/*
    add wave -noupdate -group ara -group "lane[$lane]" -group conv_stage -group mfpu_b /core_tb/dut/i_ara_system/i_ara/gen_lanes[$lane]/i_lane/i_vconv_stage/i_opqueue_mfpu_b/*
    add wave -noupdate -group ara -group "lane[$lane]" -group conv_stage -group mfpu_c /core_tb/dut/i_ara_system/i_ara/gen_lanes[$lane]/i_lane/i_vconv_stage/i_opqueue_mfpu_c/*
    add wave -noupdate -group ara -group "lane[$lane]" -group conv_stage -group alu_sld_m /core_tb/dut/i_ara_system/i_ara/gen_lanes[$lane]/i_lane/i_vconv_stage/i_opqueue_alu_sld_m/*
    add wave -noupdate -group ara -group "lane[$lane]" -group conv_stage -group alu_sld_a /core_tb/dut/i_ara_system/i_ara/gen_lanes[$lane]/i_lane/i_vconv_stage/i_opqueue_alu_sld_a/*
    add wave -noupdate -group ara -group "lane[$lane]" -group conv_stage -group alu_b /core_tb/dut/i_ara_system/i_ara/gen_lanes[$lane]/i_lane/i_vconv_stage/i_opqueue_alu_b/*
    add wave -noupdate -group ara -group "lane[$lane]" -group conv_stage -group ld_st_m /core_tb/dut/i_ara_system/i_ara/gen_lanes[$lane]/i_lane/i_vconv_stage/i_opqueue_vlsu_m/*
    add wave -noupdate -group ara -group "lane[$lane]" -group conv_stage -group st_a /core_tb/dut/i_ara_system/i_ara/gen_lanes[$lane]/i_lane/i_vconv_stage/i_opqueue_vstu_a/*
    add wave -noupdate -group ara -group "lane[$lane]" -group conv_stage -group addrgen_a /core_tb/dut/i_ara_system/i_ara/gen_lanes[$lane]/i_lane/i_vconv_stage/i_opqueue_addrgen_a/*
    add wave -noupdate -group ara -group "lane[$lane]" -group conv_stage /core_tb/dut/i_ara_system/i_ara/gen_lanes[$lane]/i_lane/i_vconv_stage/*

    add wave -noupdate -group ara -group "lane[$lane]" -group ex_stage -group valu -group simd_alu /core_tb/dut/i_ara_system/i_ara/gen_lanes[$lane]/i_lane/i_vex_stage/i_valu/i_simd_alu/*
    add wave -noupdate -group ara -group "lane[$lane]" -group ex_stage -group valu /core_tb/dut/i_ara_system/i_ara/gen_lanes[$lane]/i_lane/i_vex_stage/i_valu/*
    add wave -noupdate -group ara -group "lane[$lane]" -group ex_stage -group vmfpu -group simd_mul /core_tb/dut/i_ara_system/i_ara/gen_lanes[$lane]/i_lane/i_vex_stage/i_vmfpu/i_simd_mul/*
    add wave -noupdate -group ara -group "lane[$lane]" -group ex_stage -group vmfpu /core_tb/dut/i_ara_system/i_ara/gen_lanes[$lane]/i_lane/i_vex_stage/i_vmfpu/*
    add wave -noupdate -group ara -group "lane[$lane]" -group ex_stage /core_tb/dut/i_ara_system/i_ara/gen_lanes[$lane]/i_lane/i_vex_stage/*

    add wave -noupdate -group ara -group "lane[$lane]" /core_tb/dut/i_ara_system/i_ara/gen_lanes[$lane]/i_lane/*
}

add wave -noupdate -group ara /core_tb/dut/i_ara_system/i_ara/*