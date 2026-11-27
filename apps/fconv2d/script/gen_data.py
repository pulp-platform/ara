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

#!/usr/bin/env python3

# args: M N F, then FP64/FP32/FP16

import numpy as np
import sys

def emit(name, array, alignment='8'):
	print(".global %s" % name)
	print(".balign " + alignment)
	print("%s:" % name)
	bs = array.tobytes()
	# Pad to whole .words
	bs += b"\x00" * (-len(bs) % 4)
	for i in range(0, len(bs), 4):
		s = ""
		for n in range(4):
			s += "%02x" % bs[i+3-n]
		print("    .word 0x%s" % s)

# Parse the arguments
PRECISIONS = ("FP64", "FP32", "FP16")
argv = sys.argv[1:]
prec = set(a.upper() for a in argv if a.upper() in PRECISIONS)
nums = [a for a in argv if a.upper() not in PRECISIONS]
if not prec or len(nums) != 3:
	sys.stderr.write("Error. Give me M (rows), N (columns), F (filter size) and at least "
	                 "one precision: %s.\n" % "/".join(PRECISIONS))
	sys.exit(1)
M, N, f = (int(x) for x in nums)
# Filter size must be odd
assert(f % 2 == 1), "The filter size must be an odd integer number"

padding = int(f/2)
M_pad = M + 2*padding
N_pad = N + 2*padding
assert(M % 4 == 0), "Output image dimension must be divisible by 4, pad the input image accordingly"
assert(N % 4 == 0), "Output image dimension must be divisible by 4, pad the input image accordingly"

def hw_gold(kern, img, dtype):
	"""Accumulate one tap at a time, rounding to `dtype` after each.

	This mirrors vfmacc, whose destination is the accumulator itself, so every one
	of the F*F taps rounds at the working precision. Summing in a wider type and
	rounding once diverges at fp16 far beyond rounding noise. float64 holds each
	product and partial sum exactly, so the only rounding is the deliberate one.
	"""
	F = kern.shape[0]
	XO, YO = img.shape[0] - F + 1, img.shape[1] - F + 1
	out = np.zeros((XO, YO), dtype=dtype)
	k64, i64 = kern.astype(np.float64), img.astype(np.float64)
	for a in range(F):
		for b in range(F):
			out = (out.astype(np.float64) + k64[a, b] * i64[a:a+XO, b:b+YO]).astype(dtype)
	return out

# Print information on file
print(".section .data,\"aw\",@progbits")
emit("M", np.array(M, dtype=np.uint64))
emit("N", np.array(N, dtype=np.uint64))
emit("F", np.array(f, dtype=np.uint64))

for tag, dtype in (("64", np.float64), ("32", np.float32), ("16", np.float16)):
	if "FP" + tag not in prec:
		continue
	# Random padded input image and filter
	image = np.random.rand(M_pad, N_pad).astype(dtype)
	gen_filter = np.random.rand(f, f).astype(dtype)
	emit("i" + tag, image, 'NR_LANES*8')
	emit("f" + tag, gen_filter, 'NR_LANES*8')
	emit("o" + tag, np.zeros((M, N), dtype=dtype), 'NR_LANES*8')
	emit("golden_o" + tag, hw_gold(gen_filter, image, dtype), 'NR_LANES*8')
