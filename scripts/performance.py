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
  performance = 10 * size * np.log2(size) / cycles
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
  performance = 2 * num_runs * (cols - 1) * (rows - 1) / cycles
  return [cols, performance]
def roi_align(args, cycles):
  batch   = int(args[0])
  depth   = int(args[1])
  height  = int(args[2])
  width   = int(args[3])
  n_boxes = int(args[4])
  crop_h  = int(args[5])
  crop_w  = int(args[6])
  performance = 9 * batch * depth * n_boxes * crop_h * crop_w / cycles
  return [depth, performance]

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
  'roi_align'  : roi_align,
}

def main():
  kernel   = str(sys.argv[1])
  args     = str(sys.argv[2]).split()
  cycles   = int(sys.argv[3])
  # Extract performance information
  try:
    result = perfExtr[kernel](args, cycles)
  except KeyError:
    sys.exit('Error: the kernel "' + kernel + '" is not valid')

  # Print performance information on file
  print(result[0], result[1])

if __name__ == '__main__':
  main()
