#!/usr/bin/env python3
# Copyright 2021 ETH Zurich and University of Bologna.
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

# arg1: vector size, arg2: filter size

import random as rand
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

def rand_matrix(N, dtype):
  return np.random.rand(N).astype(dtype)

############
## SCRIPT ##
############

if len(sys.argv) == 2:
  N_f64 = int(sys.argv[1])
  N_f32 = 2 * N_f64
else:
  print("Error. Give me one argument: the number of vector elements.")
  sys.exit()

# Vector of samples
args_f64 = rand_matrix(N_f64, np.float64).astype(np.float64)
args_f32 = rand_matrix(N_f32, np.float32).astype(np.float32)

# Results buffer
results_f64 = np.zeros(N_f64, dtype=np.float64)
results_f32 = np.zeros(N_f32, dtype=np.float32)

# Gold results
gold_results_f64 = np.log(args_f64, dtype=np.float64)
gold_results_f32 = np.log(args_f32, dtype=np.float32)

# Create the file
print(".section .data,\"aw\",@progbits")
emit("N_f64", np.array(N_f64, dtype=np.uint64))
emit("args_f64", args_f64, 'NR_LANES*4')
emit("results_f64", results_f64, 'NR_LANES*4')
emit("gold_results_f64", gold_results_f64, 'NR_LANES*4')
emit("N_f32", np.array(N_f32, dtype=np.uint32))
emit("args_f32", args_f32, 'NR_LANES*4')
emit("results_f32", results_f32, 'NR_LANES*4')
emit("gold_results_f32", gold_results_f32, 'NR_LANES*4')
