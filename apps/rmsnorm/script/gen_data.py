#!/usr/bin/env python3
# Copyright 2026 ETH Zurich and University of Bologna.
#
# SPDX-License-Identifier: Apache-2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Author: Hong Pang <hopang@iis.ee.ethz.ch>

import numpy as np
import sys

def emit(name, array, alignment='8'):
  print(".global %s" % name)
  print(".balign " + alignment)
  print("%s:" % name)
  bs = array.tobytes()
  for i in range(0, len(bs), 4):
    s = ""
    for n in range(4):
      s += "%02x" % bs[i+3-n]
    print("    .word 0x%s" % s)

############
## SCRIPT ##
############

# Arguments: rows hidden_size FP32
EPS = 1e-5
args = sys.argv[1:]
nums = [a for a in args if a.upper() != "FP32"]
if "FP32" not in (a.upper() for a in args) or len(nums) != 2:
  print("Error. Give me the number of rows, the hidden size and FP32.",
        file=sys.stderr)
  sys.exit(1)
R = int(nums[0])
D = int(nums[1])

x = np.random.randn(R, D).astype(np.float32)
gamma = np.random.uniform(0.5, 1.5, D).astype(np.float32)

xd = x.astype(np.float64)
gold = xd / np.sqrt(np.mean(xd * xd, axis=1, keepdims=True) + EPS) * gamma

print(".section .data,\"aw\",@progbits")
emit("R", np.array(R, dtype=np.uint64))
emit("D", np.array(D, dtype=np.uint64))
emit("x", x, 'NR_LANES*8')
emit("gamma_v", gamma, 'NR_LANES*8')
emit("y", np.zeros(R * D, dtype=np.float32), 'NR_LANES*8')
emit("gold_y", gold.astype(np.float32), 'NR_LANES*8')
