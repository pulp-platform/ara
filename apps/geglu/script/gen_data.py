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

# Arguments: vector length
if len(sys.argv) != 2:
  print("Error. Give me the vector length.", file=sys.stderr)
  sys.exit(1)
N = int(sys.argv[1])

g = np.random.uniform(-4, 4, N).astype(np.float32)
u = np.random.uniform(-4, 4, N).astype(np.float32)

gd = g.astype(np.float64)
gold = 0.5 * gd * (1 + np.tanh(np.sqrt(2 / np.pi) * (gd + 0.044715 * gd ** 3))) * u

print(".section .data,\"aw\",@progbits")
emit("N", np.array(N, dtype=np.uint64))
emit("g", g, 'NR_LANES*8')
emit("u", u, 'NR_LANES*8')
emit("o", np.zeros(N, dtype=np.float32), 'NR_LANES*8')
emit("gold_o", gold.astype(np.float32), 'NR_LANES*8')
