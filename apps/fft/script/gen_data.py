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

# arg1: image size, arg2: filter size

import numpy as np
import sys

FFT2_SAMPLE_DYN = 13
FFT_TWIDDLE_DYN = 15

#def setupTwiddlesLUT(Twiddles, Nfft):
#  Theta = (2 * np.pi) / Nfft;
#  with np.nditer(Twiddles, op_flags=['readwrite']) as it:
#    for idx, twi in enumerate(it):
#      # Even idx
#      if not (idx % 2):
#        Phi = Theta * idx;
#        twi[...] = np.cos(Phi) * ((1 << FFT_TWIDDLE_DYN) - 1)
#      # Odd idx
#      else:
#        Phi = Theta * (idx - 1);
#        twi[...] = np.sin(Phi) * ((1 << FFT_TWIDDLE_DYN) - 1)
#  # Cast to short
#  Twiddles.astype(np.int16)

def serialize_cmplx(vector, NFFT, dtype):
  # Split the real and imaginary parts
  vector_re = np.real(vector)
  vector_im = np.imag(vector)
  # Serialize the vectors
  serial_vec = np.empty(2 * NFFT, dtype=dtype)
  serial_vec[0::2] = vector_re
  serial_vec[1::2] = vector_im
  return serial_vec

def setupTwiddlesLUT(Twiddles_vec, Nfft):
  Theta = (2 * np.pi) / Nfft;
  with np.nditer(Twiddles_vec, op_flags=['readwrite']) as it:
    for idx, twi in enumerate(it):
      Phi = Theta * idx;
      twi[...]['re'] = np.cos(Phi)
      twi[...]['im'] = np.sin(Phi)

# For this first trial, let's suppose to have in memory all the
# Twiddle factors, for each stage, already ordered, in contiguous
# memory space
def setupTwiddlesLUT_dif_vec(Twiddles_vec, Nfft):
  # Nfft power of 2
  stages = int(np.log2(Nfft))
  Theta = (2 * np.pi) / Nfft;
  # Twiddle factors ([[twi0_re, twi0_im], [twi1_re, twi1_im]])
  twi = [[np.cos(i * Theta), np.sin(i * Theta)] for i in range(int(Nfft/2))]
  # Write the Twiddle factors
  for s in range(stages):
    for t in range(int(Nfft/2)):
      Twiddles_vec[int(s * Nfft / 2 + t)]['re'] = twi[int((2**(s) * t) % int(Nfft / 2))][0]
      Twiddles_vec[int(s * Nfft / 2 + t)]['im'] = twi[int((2**(s) * t) % int(Nfft / 2))][1]
  return Twiddles_vec

  with np.nditer(Twiddles_vec, op_flags=['readwrite']) as it:
    for idx, twi in enumerate(it):
      Phi = Theta * idx;
      twi[...]['re'] = np.cos(Phi)
      twi[...]['im'] = np.sin(Phi)

def setupInput(samples, Nfft, dyn):
  with np.nditer(samples, op_flags=['readwrite']) as it:
    for samp in it:
      samp[...]['re'] = np.random.rand(1)
      samp[...]['im'] = np.random.rand(1)

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

if len(sys.argv) == 3:
  NFFT = int(sys.argv[1])
  dtype = sys.argv[2]
else:
  print("Error. Give me two arguments: the number of samples and the data type.")
  sys.exit()

if   dtype == "int16":
  dtype = np.dtype(np.int16)
elif dtype == "float16":
  dtype = np.dtype(np.float16)
elif dtype == "float32":
  dtype = np.dtype(np.float32)
else:
  print("Data type not recognized. Available are [float32|float16|int16]")
  sys.exit()

N_TWID_V = int(np.log2(NFFT)*NFFT/2)

# Complex data type with int16 for real and img parts
dtype_cplx = np.dtype([('re', dtype), ('im', dtype)])

# Vector of samples
samples   = np.empty(NFFT, dtype=dtype_cplx)
twiddle   = np.empty(NFFT, dtype=dtype_cplx)
twiddle_v = np.empty(N_TWID_V, dtype=dtype_cplx)
gold_out  = np.empty(NFFT, dtype=dtype_cplx)

# Initialize the twiddle factors
setupTwiddlesLUT(twiddle, NFFT)
twiddle_v = setupTwiddlesLUT_dif_vec(twiddle_v, NFFT)

# Initialize the input samples
setupInput(samples, NFFT, FFT2_SAMPLE_DYN)

# Calculate the golden FFT
#print(samples)
#print(samples['re'] + 1j * samples['im'])
gold_out = np.fft.fft(samples['re'] + 1j * samples['im'])
#print(gold_out)

# Serialize the complex array
samples_s    = serialize_cmplx(samples['re'] + 1j * samples['im'], NFFT, dtype)
twiddle_s    = serialize_cmplx(twiddle['re'] + 1j * twiddle['im'], NFFT, dtype)
twiddle_v_s  = serialize_cmplx(twiddle_v['re'] + 1j * twiddle_v['im'], N_TWID_V, dtype)
gold_out_s   = serialize_cmplx(gold_out, NFFT, dtype)
#print(gold_out_s)

# Create the sequential vectors - Real, and Imaginary
samples_reim              = np.empty(2 * NFFT, dtype=dtype)
samples_reim[   0:  NFFT] = samples_s[0::2]
samples_reim[NFFT:2*NFFT] = samples_s[1::2]

twiddle_vec_reim                      = np.empty(2*N_TWID_V, dtype=dtype)
twiddle_vec_reim[   0:      N_TWID_V] = twiddle_v_s[0::2]
twiddle_vec_reim[N_TWID_V:2*N_TWID_V] = twiddle_v_s[1::2]

# Create the file
print(".section .data,\"aw\",@progbits")
emit("NFFT", np.array(NFFT, dtype=np.uint64))
emit("samples", samples_s.astype(dtype), 'NR_LANES*4')
emit("samples_s", samples_s.astype(dtype), 'NR_LANES*4')
emit("samples_reim", samples_reim.astype(dtype), 'NR_LANES*4')
emit("samples_reim_s", samples_reim.astype(dtype), 'NR_LANES*4')
emit("twiddle", twiddle_s.astype(dtype), 'NR_LANES*4')
emit("twiddle_vec", twiddle_v_s.astype(dtype), 'NR_LANES*4')
emit("twiddle_vec_reim", twiddle_vec_reim.astype(dtype), 'NR_LANES*4')
emit("gold_out", gold_out_s.astype(dtype), 'NR_LANES*4')
