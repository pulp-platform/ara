#!/bin/bash
# Copyright (c) 2014-2018 ETH Zurich, University of Bologna
#
# Copyright and related rights are licensed under the Solderpad Hardware
# License, Version 0.51 (the "License"); you may not use this file except in
# compliance with the License.  You may obtain a copy of the License at
# http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
# or agreed to in writing, software, hardware and materials distributed under
# this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
# CONDITIONS OF ANY KIND, either express or implied. See the License for the
# specific language governing permissions and limitations under the License.
#
# Fabian Schuiki <fschuiki@iis.ee.ethz.ch>
# Andreas Kurth  <akurth@iis.ee.ethz.ch>

set -e
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

[ ! -z "$VSIM" ] || VSIM=vsim

call_vsim() {
    echo "run -all" | $VSIM "$@" | tee vsim.log 2>&1
    grep "Errors: 0," vsim.log
}

exec_test() {
    if [ ! -e "$ROOT/test/tb_$1.sv" ]; then
        echo "Testbench for '$1' not found!"
        exit 1
    fi
    case "$1" in
        axi_lite_to_axi)
            for DW in 8 16 32 64 128 256 512 1024; do
                call_vsim tb_axi_lite_to_axi -GDW=$DW -t 1ps -c
            done
            ;;
        axi_dw_downsizer)
            for AxiSlvPortDataWidth in 8 16 32 64 128 256 512 1024; do
                for (( AxiMstPortDataWidth = 8; AxiMstPortDataWidth < $AxiSlvPortDataWidth; AxiMstPortDataWidth *= 2 )); do
                    call_vsim tb_axi_dw_downsizer -GAxiSlvPortDataWidth=$AxiSlvPortDataWidth -GAxiMstPortDataWidth=$AxiMstPortDataWidth -t 1ps -c
                done
            done
            ;;
        axi_dw_upsizer)
            for AxiSlvPortDataWidth in 8 16 32 64 128 256 512 1024; do
                for (( AxiMstPortDataWidth = $AxiSlvPortDataWidth*2; AxiMstPortDataWidth <= 1024; AxiMstPortDataWidth *= 2 )); do
                    call_vsim tb_axi_dw_upsizer -GAxiSlvPortDataWidth=$AxiSlvPortDataWidth -GAxiMstPortDataWidth=$AxiMstPortDataWidth -t 1ps -c
                done
            done
            ;;
        axi_cdc|axi_delayer)
            call_vsim tb_$1
            ;;
        axi_atop_filter)
            for MAX_TXNS in 1 3 12; do
                call_vsim tb_axi_atop_filter -GN_TXNS=1000 -GAXI_MAX_WRITE_TXNS=$MAX_TXNS
            done
            ;;
        axi_lite_regs)
            for PRIV in 0 1; do
                for SECU in 0 1; do
                    call_vsim tb_axi_lite_regs -GPrivProtOnly=$PRIV -GSecuProtOnly=$SECU
                done
            done
            ;;
        axi_xbar)
            for GEN_ATOP in 0 1; do
                for NUM_MST in 1 6; do
                    for NUM_SLV in 2 9; do
                        for MST_ID_USE in 3 5; do
                            MST_ID=5
                            for DATA_WIDTH in 64 256; do
                                for PIPE in 0 1; do
                                    call_vsim tb_axi_xbar -t 1ns -voptargs="+acc" \
                                        -gTbNumMasters=$NUM_MST       \
                                        -gTbNumSlaves=$NUM_SLV        \
                                        -gTbAxiIdWidthMasters=$MST_ID \
                                        -gTbAxiIdUsed=$MST_ID_USE     \
                                        -gTbAxiDataWidth=$DATA_WIDTH  \
                                        -gTbPipeline=$PIPE            \
                                        -gTbEnAtop=$GEN_ATOP
                                done
                            done
                        done
                    done
                done
            done
            ;;
        axi_to_mem_banked)
            for MEM_LAT in 1 2; do
                for BANK_FACTOR in 1 2; do
                    for NUM_BANKS in 1 2 4 ; do
                        for AXI_DATA_WIDTH in 64 256 ; do
                            for NUM_WORDS in 512 2048; do
                                ACT_BANKS=$((2*$BANK_FACTOR*$NUM_BANKS))
                                MEM_DATA_WIDTH=$(($AXI_DATA_WIDTH/$NUM_BANKS))
                                call_vsim tb_axi_to_mem_banked \
                                    -voptargs="+acc +cover=bcesfx" \
                                    -gTbAxiDataWidth=$AXI_DATA_WIDTH \
                                    -gTbNumWords=$NUM_WORDS \
                                    -gTbNumBanks=$ACT_BANKS \
                                    -gTbMemDataWidth=$MEM_DATA_WIDTH \
                                    -gTbMemLatency=$MEM_LAT
                            done
                        done
                    done
                done
            done
            ;;
        *)
            call_vsim tb_$1 -t 1ns -coverage -voptargs="+acc +cover=bcesfx"
            ;;
    esac
    touch "$1.tested"
}

if [ "$#" -eq 0 ]; then
    tests=()
    while IFS=  read -r -d $'\0'; do
        tb_name="$(basename -s .sv $REPLY)"
        dut_name="${tb_name#tb_}"
        tests+=("$dut_name")
    done < <(find "$ROOT/test" -name 'tb_*.sv' -a \( ! -name '*_pkg.sv' \) -print0)
else
    tests=("$@")
fi

for t in "${tests[@]}"; do
    exec_test $t
done
