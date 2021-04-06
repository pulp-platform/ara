#!/usr/bin/env python3

import numpy as np
import scipy.signal
import sys

def rand_matrix(N, M, seed):
	return np.arange(seed, seed+N*M, dtype=np.float64).reshape(N, M) * 3.141

def emit(name, array, alignment='3'):
	print(".global %s" % name)
	print(".align " + alignment)
	print("%s:" % name)
	bs = array.tobytes()
	for i in range(0, len(bs), 4):
		s = ""
		for n in range(4):
			s += "%02x" % bs[i+3-n]
		print("    .word 0x%s" % s)

# Define the filter size
if len(sys.argv) > 1:
	filter_size = int(sys.argv[1])
	# Filter size must be odd
	assert(filter_size % 2 == 1), "The filter size must be an odd integer number"
else:
	filter_size = 3

# Input image
M = 64
N = 64
padding = int(filter_size/2)
M_pad = M + 2*padding
N_pad = N + 2*padding
assert(M % 4 == 0), "Output image dimension must be divisible by 4, pad the input image accordingly"
assert(N % 4 == 0), "Output image dimension must be divisible by 4, pad the input image accordingly"

# Generate a random int64 input padded image
image = np.around(rand_matrix(M_pad, N_pad, 1)).astype(np.int64)
np.random.shuffle(image.flat)

# Generate a random int64 filter
gen_filter = np.around(rand_matrix(filter_size, filter_size, 0)).astype(np.int64)
np.random.shuffle(gen_filter.flat)

# Create the empty o matrix
empty_o = np.zeros((M, N)).astype(np.int64)

# Calculate the output matrix
result = np.around(scipy.signal.convolve2d(np.flip(gen_filter), image, 'valid')).astype(np.int64) # https://stackoverflow.com/questions/41613155/what-does-scipy-signal-convolve2d-calculate

# Calculate a checksum
checksum = np.sum(result, dtype=np.int64)

# Print information on display
#print("Image:\n")
#print(image)
#print("Filter:\n")
#print(gen_filter)
#print("Results:\n")
#print(result)
#print("\n")
#print(checksum)

# Print information on file
print(".section .data,\"aw\",@progbits")
emit("M", np.array(M, dtype=np.uint64))
emit("N", np.array(N, dtype=np.uint64))
emit("F", np.array(filter_size, dtype=np.uint64))
emit("i", image, 'NR_LANES*4')
emit("f", gen_filter, 'NR_LANES*4')
emit("o", empty_o, 'NR_LANES*4')
emit("golden_o", result, 'NR_LANES*4')
emit("o_checksum", checksum)
