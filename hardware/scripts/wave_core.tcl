# Copyright 2021 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51
#
# Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>

add wave -noupdate -group CVA6 -group core /ara_tb/dut/i_ara_soc/i_system/i_ariane/*

add wave -noupdate -group CVA6 -group frontend /ara_tb/dut/i_ara_soc/i_system/i_ariane/i_frontend/*
add wave -noupdate -group CVA6 -group frontend -group icache /ara_tb/dut/i_ara_soc/i_system/i_ariane/genblk4/i_cache_subsystem/*
# add wave -noupdate -group CVA6 -group frontend -group ras /ara_tb/dut/i_ara_soc/i_system/i_ariane/i_frontend/i_ras/*
# add wave -noupdate -group CVA6 -group frontend -group btb /ara_tb/dut/i_ara_soc/i_system/i_ariane/i_frontend/i_btb/*
# add wave -noupdate -group CVA6 -group frontend -group bht /ara_tb/dut/i_ara_soc/i_system/i_ariane/i_frontend/i_bht/*
# add wave -noupdate -group CVA6 -group frontend -group instr_scan /ara_tb/dut/i_ara_soc/i_system/i_ariane/i_frontend/*/i_instr_scan/*
# add wave -noupdate -group CVA6 -group frontend -group fetch_fifo /ara_tb/dut/i_ara_soc/i_system/i_ariane/i_frontend/i_fetch_fifo/*

add wave -noupdate -group CVA6 -group id_stage -group decoder /ara_tb/dut/i_ara_soc/i_system/i_ariane/id_stage_i/decoder_i/*
add wave -noupdate -group CVA6 -group id_stage -group compressed_decoder /ara_tb/dut/i_ara_soc/i_system/i_ariane/id_stage_i/genblk1/compressed_decoder_i/*
add wave -noupdate -group CVA6 -group id_stage /ara_tb/dut/i_ara_soc/i_system/i_ariane/id_stage_i/*

add wave -noupdate -group CVA6 -group issue_stage -group scoreboard /ara_tb/dut/i_ara_soc/i_system/i_ariane/issue_stage_i/i_scoreboard/*
add wave -noupdate -group CVA6 -group issue_stage -group issue_read_operands /ara_tb/dut/i_ara_soc/i_system/i_ariane/issue_stage_i/i_issue_read_operands/*
add wave -noupdate -group CVA6 -group issue_stage -group rename /ara_tb/dut/i_ara_soc/i_system/i_ariane/issue_stage_i/i_re_name/*
add wave -noupdate -group CVA6 -group issue_stage /ara_tb/dut/i_ara_soc/i_system/i_ariane/issue_stage_i/*

add wave -noupdate -group CVA6 -group ex_stage -group alu /ara_tb/dut/i_ara_soc/i_system/i_ariane/ex_stage_i/alu_i/*
add wave -noupdate -group CVA6 -group ex_stage -group mult /ara_tb/dut/i_ara_soc/i_system/i_ariane/ex_stage_i/i_mult/*
add wave -noupdate -group CVA6 -group ex_stage -group mult -group mul /ara_tb/dut/i_ara_soc/i_system/i_ariane/ex_stage_i/i_mult/i_multiplier/*
add wave -noupdate -group CVA6 -group ex_stage -group mult -group div /ara_tb/dut/i_ara_soc/i_system/i_ariane/ex_stage_i/i_mult/i_div/*
add wave -noupdate -group CVA6 -group ex_stage -group fpu /ara_tb/dut/i_ara_soc/i_system/i_ariane/ex_stage_i/fpu_gen/fpu_i/*
add wave -noupdate -group CVA6 -group ex_stage -group fpu -group fpnew /ara_tb/dut/i_ara_soc/i_system/i_ariane/ex_stage_i/fpu_gen/fpu_i/fpu_gen/i_fpnew_bulk/*

add wave -noupdate -group CVA6 -group ex_stage -group lsu /ara_tb/dut/i_ara_soc/i_system/i_ariane/ex_stage_i/lsu_i/*
add wave -noupdate -group CVA6 -group ex_stage -group lsu  -group lsu_bypass /ara_tb/dut/i_ara_soc/i_system/i_ariane/ex_stage_i/lsu_i/lsu_bypass_i/*
add wave -noupdate -group CVA6 -group ex_stage -group lsu -group mmu /ara_tb/dut/i_ara_soc/i_system/i_ariane/ex_stage_i/lsu_i/gen_mmu_sv39/i_cva6_mmu/*
add wave -noupdate -group CVA6 -group ex_stage -group lsu -group mmu -group itlb /ara_tb/dut/i_ara_soc/i_system/i_ariane/ex_stage_i/lsu_i/gen_mmu_sv39/i_cva6_mmu/i_itlb/*
add wave -noupdate -group CVA6 -group ex_stage -group lsu -group mmu -group dtlb /ara_tb/dut/i_ara_soc/i_system/i_ariane/ex_stage_i/lsu_i/gen_mmu_sv39/i_cva6_mmu/i_dtlb/*
add wave -noupdate -group CVA6 -group ex_stage -group lsu -group mmu -group ptw /ara_tb/dut/i_ara_soc/i_system/i_ariane/ex_stage_i/lsu_i/gen_mmu_sv39/i_cva6_mmu/i_ptw/*

add wave -noupdate -group CVA6 -group ex_stage -group lsu -group store_unit /ara_tb/dut/i_ara_soc/i_system/i_ariane/ex_stage_i/lsu_i/i_store_unit/*
add wave -noupdate -group CVA6 -group ex_stage -group lsu -group store_unit -group store_buffer /ara_tb/dut/i_ara_soc/i_system/i_ariane/ex_stage_i/lsu_i/i_store_unit/store_buffer_i/*

add wave -noupdate -group CVA6 -group ex_stage -group lsu -group load_unit /ara_tb/dut/i_ara_soc/i_system/i_ariane/ex_stage_i/lsu_i/i_load_unit/*

add wave -noupdate -group CVA6 -group ex_stage -group branch_unit /ara_tb/dut/i_ara_soc/i_system/i_ariane/ex_stage_i/branch_unit_i/*

add wave -noupdate -group CVA6 -group ex_stage -group csr_buffer /ara_tb/dut/i_ara_soc/i_system/i_ariane/ex_stage_i/csr_buffer_i/*

add wave -noupdate -group CVA6 -group ex_stage /ara_tb/dut/i_ara_soc/i_system/i_ariane/ex_stage_i/*

add wave -noupdate -group CVA6 -group commit_stage /ara_tb/dut/i_ara_soc/i_system/i_ariane/commit_stage_i/*

add wave -noupdate -group CVA6 -group csr_file /ara_tb/dut/i_ara_soc/i_system/i_ariane/csr_regfile_i/*

add wave -noupdate -group CVA6 -group controller /ara_tb/dut/i_ara_soc/i_system/i_ariane/controller_i/*

add wave -noupdate -group CVA6 -group wt_dcache /ara_tb/dut/i_ara_soc/i_system/i_ariane/genblk4/i_cache_subsystem/i_wt_dcache/*
add wave -noupdate -group CVA6 -group wt_dcache -group miss_handler /ara_tb/dut/i_ara_soc/i_system/i_ariane/genblk4/i_cache_subsystem/i_wt_dcache/i_wt_dcache_missunit/*

add wave -noupdate -group CVA6 -group wt_dcache -group load {/ara_tb/dut/i_ara_soc/i_system/i_ariane/genblk4/i_cache_subsystem/i_wt_dcache/gen_rd_ports[0]/i_wt_dcache_ctrl/*}
add wave -noupdate -group CVA6 -group wt_dcache -group ptw {/ara_tb/dut/i_ara_soc/i_system/i_ariane/genblk4/i_cache_subsystem/i_wt_dcache/gen_rd_ports[1]/i_wt_dcache_ctrl/*}

add wave -noupdate -group CVA6 -group dispatcher /ara_tb/dut/i_ara_soc/i_system/i_ariane/gen_accelerator/i_acc_dispatcher/*

add wave -noupdate -group CVA6 -group perf_counters /ara_tb/dut/i_ara_soc/i_system/i_ariane/gen_perf_counter/perf_counters_i/*
