#!/usr/bin/env python
# Copyright 2022 ETH Zurich and University of Bologna.
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
#
# Author: Matteo Perotti, ETH Zurich
#
# Calculate throughput performance metric for a particular kernel, cycle count,
# and environment conditions

import sys
import numpy as np

# Performance extractors: returns problem size and performance (throughput)
def imatmul(args, cycles):
  m           = int(args[0])
  n           = int(args[1])
  p           = int(args[2])
  if (m == n and n == p):
    size = m
  else:
    sys.exit('Unimplemented return value for performance function if !(M == N == P) in "' + kernel)
  performance = 2 * size * size * size / cycles
  return [size, performance]
def fmatmul(args, cycles):
  m           = int(args[0])
  n           = int(args[1])
  p           = int(args[2])
  if (m == n and n == p):
    size = m
  else:
    sys.exit('Unimplemented return value for performance function if !(M == N == P) in "' + kernel)
  performance = 2 * size * size * size / cycles
  return [size, performance]
def iconv2d(args, cycles):
  size        = int(args[0])
  filter      = int(args[1])
  performance = 2 * filter * filter * size * size / cycles
  return [size, performance]
def fconv2d(args, cycles):
  size        = int(args[0])
  filter      = int(args[1])
  performance = 2 * filter * filter * size * size / cycles
  return [size, performance]
def fconv3d(args, cycles):
  size        = int(args[0])
  filter      = int(args[1])
  performance = 2 * 3 * filter * filter * size * size / cycles
  return [size, performance]
def jacobi2d(args, cycles):
  size        = int(args[0])
  trash_0     = args[1]
  performance = 2 * 5 * (size-1) * (size-1) / cycles
  return [size, performance]
def dropout(args, cycles):
  size        = int(args[0])
  performance = size / cycles
  return [size, performance]
def fft(args, cycles):
  size        = int(args[0])
  dtype       = args[1]
  performance = 5 * size * np.log2(size) / cycles
  return [size, performance]
def dwt(args, cycles):
  size        = int(args[0])
  k           = 0
  for den in range(0, int(np.log2(size))):
    k += 1/(2**den)
  performance = 3 * k * size / cycles
  return [size, performance]
def exp(args, cycles):
  size        = int(args[0])
  performance = 30 * size / cycles
  return [size, performance]
def softmax(args, cycles):
  channels    = int(args[0])
  insize      = int(args[1])
  performance = 25 * channels * insize / cycles
  return [insize, performance]
def pathfinder(args, cycles):
  num_runs = int(args[0])
  cols     = int(args[1])
  rows     = int(args[2])
  performance = 3 * num_runs * (cols - 1) * (rows - 1) / cycles
  return [cols, performance]
def dotproduct(args, cycles):
  size        = int(args[0])
  performance = 2 * size / cycles
  return [size, performance]
def fdotproduct(args, cycles):
  size        = int(args[0])
  performance = 2 * size / cycles
  return [size, performance]
def roi_align(args, cycles):
  batch   = int(args[0])
  depth   = int(args[1])
  height  = int(args[2])
  width   = int(args[3])
  n_boxes = int(args[4])
  crop_h  = int(args[5])
  crop_w  = int(args[6])
  performance = 9 * depth / cycles
  return [depth, performance]
def lavamd(args, cycles):
  box1d   = int(args[0])
  par4box = int(args[1])
  alpha   = float(args[2])
  maxelm  = int(args[3])
  # pseudo lavaMD iteration bounds: 1, 2, 4, par4box
  performance = (1 * 2 * 4 * (51 * par4box + 4 * min(par4box, maxelm))) / cycles
  return [par4box, performance]

perfExtr = {
  'imatmul'    : imatmul,
  'fmatmul'    : fmatmul,
  'iconv2d'    : iconv2d,
  'fconv2d'    : fconv2d,
  'fconv3d'    : fconv3d,
  'jacobi2d'   : jacobi2d,
  'dropout'    : dropout,
  'fft'        : fft,
  'dwt'        : dwt,
  'exp'        : exp,
  'softmax'    : softmax,
  'pathfinder' : pathfinder,
  'dotproduct' : dotproduct,
  'fdotproduct': fdotproduct,
  'roi_align'  : roi_align,
  'lavamd'     : lavamd,
}

# Maximum performance if Ara's BW can be fully utilized
ideal_maxPerf = {
  'imatmul'    : lambda l, s : 2 * l * 8/s,
  'fmatmul'    : lambda l, s : 2 * l * 8/s,
  'iconv2d'    : lambda l, s : 2 * l * 8/s,
  'fconv2d'    : lambda l, s : 2 * l * 8/s,
  'fconv3d'    : lambda l, s : 2 * l * 8/s,
  'jacobi2d'   : lambda l, s : l * 8/s,
  'dropout'    : lambda l, s : 4 * l / (2*s + 1/8),
  'fft'        : lambda l, s : 6/5 * l * 8/s,
  'dwt'        : lambda l, s : 4 * l / s,
  'exp'        : lambda l, s : 28/23 * l * 8/s,
  'softmax'    : lambda l, s : 32/25 * l * 8/s,
  'pathfinder' : lambda l, s : l * 8/s,
  'dotproduct' : lambda l, s : l * 8/s,
  'fdotproduct': lambda l, s : l * 8/s,
  'roi_align'  : lambda l, s : l * 8/s,
  'lavamd'     : lambda l, s : 0,
}

# Maximum performance taking into account Ara's limited
# memory BW
real_maxPerf = {
  'imatmul'    : lambda l, s : 2 * l * 8/s,
  'fmatmul'    : lambda l, s : 2 * l * 8/s,
  'iconv2d'    : lambda l, s : 2 * l * 8/s,
  'fconv2d'    : lambda l, s : 2 * l * 8/s,
  'fconv3d'    : lambda l, s : 2 * l * 8/s,
  'jacobi2d'   : lambda l, s : l * 8/s,
  'dropout'    : lambda l, s : 4 * l / (2*s + 1/8),
  'fft'        : lambda l, s : 6/5 * l * 8/s,
  'dwt'        : lambda l, s : 4 * l / s,
  'exp'        : lambda l, s : 28/23 * l * 8/s,
  'softmax'    : lambda l, s : 32/25 * l * 8/s,
  'pathfinder' : lambda l, s : l * 8/s,
  'dotproduct' : lambda l, s : 4 * l/s,
  'fdotproduct': lambda l, s : 4 * l/s,
  'roi_align'  : lambda l, s : 3/5 * l * 8/s,
  'lavamd'     : lambda l, s : 0,
}

def main():
  # kernel lanes vsize sew ideal_dispatcher
  metadata    = str(sys.argv[1]).split()
  args        = str(sys.argv[2]).split()
  cycles      = int(sys.argv[3])
  if len(sys.argv) > 4:
    dcache_stall= int(sys.argv[4])
    icache_stall= int(sys.argv[5])
    sb_full     = int(sys.argv[6])
  # Extract performance information
  try:
    result   = perfExtr[metadata[0]](args, cycles)
    real_max_perf  = real_maxPerf[metadata[0]](int(metadata[1]), int(metadata[3]))
    ideal_max_perf = ideal_maxPerf[metadata[0]](int(metadata[1]), int(metadata[3]))
  except KeyError:
    sys.exit('Error: the kernel "' + metadata[0] + '" is not valid')

  # Print performance information on file
  # kernel, lanes, vsize, sew, perf, max_perf, ideal_disp
  if len(sys.argv) > 4:
    print(metadata[0], metadata[1], result[0], metadata[3], result[1], real_max_perf, metadata[4], dcache_stall, icache_stall, sb_full)
  else:
    # CI run. Print only basic information for the roofline plots
    print(result[0], result[1])

if __name__ == '__main__':
  main()
