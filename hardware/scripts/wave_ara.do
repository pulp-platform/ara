add wave -noupdate -group ARA -group core /ara_tb/dut/i_ara_soc/i_ara/*

add wave -noupdate -group ARA -group dispatcher /ara_tb/dut/i_ara_soc/i_ara/i_dispatcher/*
add wave -noupdate -group ARA -group sequencer /ara_tb/dut/i_ara_soc/i_ara/i_sequencer/*

# Add waves from all the lanes
for {set lane 0}  {$lane < [examine -radix dec ara_tb.NrLanes]} {incr lane} {
    do ../scripts/wave_lane.do $lane
}

add wave -noupdate -group ARA -group vlsu -group addrgen /ara_tb/dut/i_ara_soc/i_ara/i_vlsu/i_addrgen/*
add wave -noupdate -group ARA -group vlsu -group vldu /ara_tb/dut/i_ara_soc/i_ara/i_vlsu/i_vldu/*
add wave -noupdate -group ARA -group vlsu -group vstu /ara_tb/dut/i_ara_soc/i_ara/i_vlsu/i_vstu/*
add wave -noupdate -group ARA -group vlsu /ara_tb/dut/i_ara_soc/i_ara/i_vlsu/*
