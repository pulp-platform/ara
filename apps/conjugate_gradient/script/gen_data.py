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

# arg1: size, arg2: steps, arg3: sparse density

import random
import numpy as np
import sys
from sklearn.datasets import make_spd_matrix
from sklearn.datasets import make_sparse_spd_matrix

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

def genSymetricPositveDenseMatrix(size,data_type):
	A = make_spd_matrix(size)
	M = np.array(A, dtype=data_type)
	return M
	pass

def genSymetricPositveSparseMatrix(size,data_type, idx_type,density,element_byte):
	alpha=1.0-density
	M = make_sparse_spd_matrix(size)
	M = np.array(M, dtype=data_type)
	insert_list = list(np.flatnonzero(M))
	non_zero = len(insert_list)
	sparsity = float(non_zero)/float(size*size)
	num_row = size
	num_col = size

	# nz_coo = np.nonzero(M)
	# nz_coo_row = nz_coo[0]
	# nz_coo_col = nz_coo[1]

	coo = np.transpose(np.nonzero(M))

	#generate data
	data_list = []
	for x in range(non_zero):
		# data_list.append(random.random())
		a = coo[x][0]
		b = coo[x][1]
		data_list.append(M[a][b])
		pass

	#Count for p_row
	p_row = []
	p_row.append(0)
	acc_bar = num_col
	acc_cnt = 0
	for x in range(non_zero):
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

	#generate indicies
	index_list = []
	for x in range(non_zero):
		idx = insert_list[x]
		max_idx = num_col
		while(idx>=max_idx):
			idx = idx - max_idx
			pass
		index_list.append(idx*element_byte)
		pass

	#form an equvelant dense matrix
	A = np.zeros([size,size], dtype=data_type)
	cnt = 0
	for x in range(size):
		row_len = p_row[x+1] - p_row[x]
		for y in range(row_len):
			if cnt != y+p_row[x]:
				print("Error. paralyze sparse matrix wrong")
				sys.exit()
				pass
			idx = int((index_list[cnt])/element_byte)
			A[x][idx] = data_list[cnt]
			cnt = cnt + 1
			pass
		pass

	#check dialog elements
	for x in range(size):
		if A[x][x] == 0:
			print("Error. paralyze dialog wrong")
			sys.exit()
			pass
		pass

	#check symetric
	for x in range(size):
		for y in range(size):
			if A[x][y] != A[y][x]:
				print("Error. paralyze dialog wrong")
				sys.exit()
				pass
			pass
		pass

	#check transform correctness
	for x in range(size):
		for y in range(size):
			if A[x][y] != M[x][y]:
				print("Error. CSR transform wrong")
				sys.exit()
				pass
			pass
		pass

	#Form numpy data
	A_PROW = np.array(p_row, dtype=idx_type)
	A_IDX = np.array(index_list, dtype=idx_type)
	A_DATA = np.array(data_list, dtype=data_type)

	return A_PROW, A_IDX, A_DATA, sparsity
	pass

def genRandomVector(size,data_type):
	v=np.zeros([size], dtype=data_type)
	for x in range(size):
		v[x] = random.random();
		pass
	return v
	pass

############
## SCRIPT ##
############



if len(sys.argv) == 4:
  S = int(sys.argv[1])
  N = int(sys.argv[2])
  D = float(sys.argv[3])
else:
  print("Error. Give me one argument: the number of vector elements.")
  sys.exit()

data_type = np.float64
idx_type = np.int32
element_byte = 8

A=genSymetricPositveDenseMatrix(S,data_type)
A_PROW, A_IDX, A_DATA, sparsity = genSymetricPositveSparseMatrix(S,data_type, idx_type,D,element_byte)
b=genRandomVector(S,data_type)
x=np.zeros([S], dtype=data_type)
r=np.zeros([S], dtype=data_type)
p=np.zeros([S], dtype=data_type)
Ax=np.zeros([S,S], dtype=data_type)
Ap=np.zeros([S,S], dtype=data_type)


print(".section .data,\"aw\",@progbits")
emit("size", np.array(S, dtype=np.uint64))
emit("step", np.array(N, dtype=np.uint64))
emit("sparsity", np.array(sparsity, dtype=np.float64))
emit("A", A, 'NR_LANES*4')
emit("b", b, 'NR_LANES*4')
emit("x", x, 'NR_LANES*4')
emit("r", r, 'NR_LANES*4')
emit("p", p, 'NR_LANES*4')
emit("Ax", Ax, 'NR_LANES*4')
emit("Ap", Ap, 'NR_LANES*4')
emit("A_PROW", A_PROW, 'NR_LANES*4')
emit("A_IDX", A_IDX, 'NR_LANES*4')
emit("A_DATA", A_DATA, 'NR_LANES*4')
