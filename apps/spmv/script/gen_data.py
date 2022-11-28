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

# // Author: Chi Zhang, ETH Zurich <chizhang@iis.ee.ethz.ch>


# arg1: row, arg2: column, arg3: density
# default configuration:
# # INT32 idx
# # FP64  data

import random
import numpy as np
import sys

#fun for froming file
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

#generate random CSR format sparse matrix
def randomCSR(num_row, num_col, density, element_byte):
  non_zero = int(num_row * num_col * density)
  # print("non_zero="+str(non_zero))
  # random insert
  insert_list = []
  pool = list(range(num_row*num_col))
  for x in range(non_zero):
    insert = random.choice(pool)
    pool.remove(insert)
    # print(insert)
    insert_list.append(insert)
    # print("inseting: "+str(x)+"/"+str(non_zero), end="\r")
    pass
  insert_list.sort()
  # print(insert_list)

  #Count for p_row
  p_row = []
  p_row.append(0)
  acc_bar = num_col
  acc_cnt = 0
  for x in range(non_zero):
    # print("generate p_row: "+str(x)+"/"+str(non_zero), end="\r")
    if insert_list[x] >= acc_bar:
      p_row.append(x)
      acc_bar = acc_bar + num_col
      acc_cnt = acc_cnt +1
      while insert_list[x] >= acc_bar:
        p_row.append(x)
        acc_bar = acc_bar + num_col
        acc_cnt = acc_cnt +1
        pass
      pass
    pass
  for x in range(num_row-acc_cnt):
    p_row.append(non_zero)
    pass
  # print(p_row)

  #generate indicies
  index_list = []
  for x in range(num_row):
    # print("generate index: "+str(x)+"/"+str(num_row), end="\r")
    length = p_row[x+1]- p_row[x]
    row_idx_list = []
    pool = list(range(0,num_col*element_byte,element_byte))
    for x in range(length):
      index = random.choice(pool)
      pool.remove(index)
      row_idx_list.append(index)
      pass
    row_idx_list.sort()
    index_list = index_list + row_idx_list
    pass

  #generate data
  # print("start generate data")
  data_list = []
  for x in range(non_zero):
    # data_list.append(random.random())
    data_list.append(x)
    pass

  #generate vector
  # print("start generate vector")
  vector_list = []
  for x in range(num_col):
    vector_list.append(random.random())
    # vector_list.append(x)
    pass

  return non_zero, p_row, index_list, data_list, vector_list

  pass

############
## SCRIPT ##
############



if len(sys.argv) == 4:
  R = int(sys.argv[1])
  C = int(sys.argv[2])
  D = float(sys.argv[3])
else:
  print("Error. Give me one argument: the number of vector elements.")
  sys.exit()

data_type = np.float64
idx_type = np.int32
element_byte = 8
idx_byte = 4

#generate sparse matrix
non_zero, p_row, index_list, data_list, vector_list = randomCSR(R, C, D, element_byte)

# Create the file
print(".section .data,\"aw\",@progbits")
emit("R", np.array(R, dtype=np.uint64))
emit("C", np.array(C, dtype=np.uint64))
emit("NZ", np.array(non_zero, dtype=np.uint64))
emit("CSR_PROW", np.array(p_row, dtype=idx_type), 'NR_LANES*4')
emit("CSR_INDEX", np.array(index_list, dtype=idx_type), 'NR_LANES*4')
emit("CSR_DATA", np.array(data_list, dtype=data_type), 'NR_LANES*4')
emit("CSR_IN_VECTOR", np.array(vector_list, dtype=data_type), 'NR_LANES*4')
emit("CSR_OUT_VECTOR", np.zeros([C], dtype=data_type), 'NR_LANES*4')


# TSTEPS = 1

# # Fill in the extra data to align the matrices to 4*NrLanes in SW
# maxNrLanes   = 16
# maxAlignment = 4*maxNrLanes              # [B]
# sizeOfDType  = np.dtype(dtype).itemsize  # [B]
# R_ext = int(R + (maxAlignment / sizeOfDType))
# C_ext = int(C + (maxAlignment / sizeOfDType))

# # Vector of samples (padding is random since it does not impact performance)
# A = np.random.rand(R_ext, C_ext).astype(dtype)
# B = np.zeros([R_ext, C_ext], dtype=dtype)

# Create the file
# print(".section .data,\"aw\",@progbits")
# emit("R", np.array(R, dtype=np.uint64))
# emit("C", np.array(C, dtype=np.uint64))
# emit("TSTEPS", np.array(TSTEPS, dtype=np.uint64))
# emit("A_v", A, 'NR_LANES*4')
# emit("B_v", B, 'NR_LANES*4')
# if not OnlyVec:
#   emit("A_s", A, 'NR_LANES*4')
#   emit("B_s", B, 'NR_LANES*4')
