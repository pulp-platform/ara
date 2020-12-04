add wave -noupdate -group ARA -group Lane[$1] -group sequencer /ara_tb/dut/i_ara/gen_lanes[$1]/i_lane/i_lane_sequencer/*

add wave -noupdate -group ARA -group Lane[$1] -group operand_requester /ara_tb/dut/i_ara/gen_lanes[$1]/i_lane/i_operand_requester/*

add wave -noupdate -group ARA -group Lane[$1] -group vector_regfile /ara_tb/dut/i_ara/gen_lanes[$1]/i_lane/i_vrf/*

add wave -noupdate -group ARA -group Lane[$1] -group operand_queues -group alu_a /ara_tb/dut/i_ara/gen_lanes[$1]/i_lane/i_operand_queues/i_operand_queue_alu_a/*
add wave -noupdate -group ARA -group Lane[$1] -group operand_queues -group alu_b /ara_tb/dut/i_ara/gen_lanes[$1]/i_lane/i_operand_queues/i_operand_queue_alu_b/*
add wave -noupdate -group ARA -group Lane[$1] -group operand_queues -group mfpu_a /ara_tb/dut/i_ara/gen_lanes[$1]/i_lane/i_operand_queues/i_operand_queue_mfpu_a/*
add wave -noupdate -group ARA -group Lane[$1] -group operand_queues -group mfpu_b /ara_tb/dut/i_ara/gen_lanes[$1]/i_lane/i_operand_queues/i_operand_queue_mfpu_b/*
add wave -noupdate -group ARA -group Lane[$1] -group operand_queues -group mfpu_c /ara_tb/dut/i_ara/gen_lanes[$1]/i_lane/i_operand_queues/i_operand_queue_mfpu_c/*
add wave -noupdate -group ARA -group Lane[$1] -group operand_queues -group mfpu_c /ara_tb/dut/i_ara/gen_lanes[$1]/i_lane/i_operand_queues/i_operand_queue_mfpu_c/*
add wave -noupdate -group ARA -group Lane[$1] -group operand_queues -group st_a /ara_tb/dut/i_ara/gen_lanes[$1]/i_lane/i_operand_queues/i_operand_queue_st_a/*
add wave -noupdate -group ARA -group Lane[$1] -group operand_queues -group addrgen_a /ara_tb/dut/i_ara/gen_lanes[$1]/i_lane/i_operand_queues/i_operand_queue_addrgen_a/*
add wave -noupdate -group ARA -group Lane[$1] -group operand_queues /ara_tb/dut/i_ara/gen_lanes[$1]/i_lane/i_operand_queues/*

add wave -noupdate -group ARA -group Lane[$1] -group vector_functional_units -group valu /ara_tb/dut/i_ara/gen_lanes[$1]/i_lane/i_vfus/i_valu/*
add wave -noupdate -group ARA -group Lane[$1] -group vector_functional_units /ara_tb/dut/i_ara/gen_lanes[$1]/i_lane/i_vfus/*

add wave -noupdate -group ARA -group Lane[$1] /ara_tb/dut/i_ara/gen_lanes[$1]/i_lane/*
