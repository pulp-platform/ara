# Copyright 2022 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51

set PROJECT   ara
set TIMESTAMP [exec date +%Y%m%d_%H%M%S]

new_project sg_projects/${PROJECT}_${TIMESTAMP}
current_methodology $env(SPYGLASS_HOME)/GuideWare/latest/block/rtl_handoff

# Read the RTL
read_file -type sourcelist tmp/files

set_option enableSV09 yes
set_option language_mode mixed
set_option allow_module_override yes
set_option designread_disable_flatten no
set_option mthresh 32768
set_option top ara_soc_wrap

# Read constraints
current_design ara_soc_wrap
set_option sdc2sgdc yes
sdc_data -file sdc/func.sdc

# Link Design
compile_design

# Set lint_rtl goal and run
current_goal lint/lint_rtl
run_goal

# Create a link to the results
exec rm -rf sg_projects/${PROJECT}
exec ln -sf ${PROJECT}_${TIMESTAMP} sg_projects/${PROJECT}

# Ciao!
exit -save
