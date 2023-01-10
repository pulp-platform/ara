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
# Check that the HW measured cycles are not too far off wrt the SW measured cycles
# This redundancy adds reliability to the measurement

import sys
import numpy as np

threshold = {
  'imatmul'    : 500,
  'fmatmul'    : 500,
  'iconv2d'    : 500,
  'fconv2d'    : 500,
  'fconv3d'    : 500,
  'jacobi2d'   : 500,
  'dropout'    : 500,
  'fft'        : 500,
  'dwt'        : 500,
  'exp'        : 500,
  'softmax'    : 500,
  'pathfinder' : 500,
  'roi_align'  : 500,
}

skip_check = {
  'imatmul'    : 0,
  'fmatmul'    : 0,
  'iconv2d'    : 0,
  'fconv2d'    : 0,
  'fconv3d'    : 0,
  'jacobi2d'   : 0,
  'dropout'    : 0,
  'fft'        : 0,
  'dwt'        : 0,
  'exp'        : 0,
  'softmax'    : 0,
  'pathfinder' : 0,
  'roi_align'  : 1, # This program has a larger scalar component
}

def main():
  kernel   = sys.argv[1]
  hwcycles = int(sys.argv[2])
  swcycles = int(sys.argv[3])
  # Extract performance information
  try:
    # Check absolute thresholds
    if (abs(hwcycles - swcycles) > threshold[kernel]):
      # Check for exception rule
      if not skip_check[kernel]:
        sys.exit('Error: the difference in hw_cycles ({}) and sw_cycles ({}) for kernel {} is too high.'.format(
          hwcycles, swcycles, kernel))
  except KeyError:
    sys.exit('Error: the kernel "' + kernel + '" is not valid')

if __name__ == '__main__':
  main()
