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

# Performance extractors: returns problem size and performance (throughput)
def imatmul(args, cycles):
  size        = int(args[0])
  performance = 2 * size * size * size / cycles
  return [size, performance]
def fmatmul(args, cycles):
  size        = int(args[0])
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
  return [args, performance]
def fconv3d(args, cycles):
  size        = int(args[0])
  filter      = int(args[1])
  performance = 2 * 3 * filter * filter * size * size / cycles
  return [size, performance]

perfExtr = {
  'imatmul' : imatmul,
  'fmatmul' : fmatmul,
  'iconv2d' : iconv2d,
  'fconv2d' : fconv2d,
  'fconv3d' : fconv3d,
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
