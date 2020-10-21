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

for PORTS in 1 2; do
  for LATENCY in 0 1 2; do
    for WORDS in 1 420 1024; do
      for DWIDTH in 1 42 64; do
        for BYTEWIDTH in 1 8 9; do
          call_vsim tb_tc_sram -GNumPorts=$PORTS -GLatency=$LATENCY -GNumWords=$WORDS -GDataWidth=$DWIDTH -GByteWidth=$BYTEWIDTH
       done
      done
    done
  done
done

