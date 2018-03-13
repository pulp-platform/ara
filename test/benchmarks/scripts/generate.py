#!/usr/bin/env python3
# Fabian Schuiki <fschuiki@iis.ee.ethz.ch>

import argparse
import os
import numpy as np

# Parse command line arguments.
parser = argparse.ArgumentParser(description="Generate benchmark data sets")
parser.add_argument("outdir", metavar="OUTDIR", help="output directory for data sets")
args = parser.parse_args()

def store_dataset(name, dim, *data):
	path = args.outdir+"/"+name
	os.makedirs(path, exist_ok=True)

	for (name, value) in data:
		value.tofile(path+"/"+name+".dat")

	with open(path+"/data.S", "w") as asm:
		asm.write(".section .rawdata\n\n")

		asm.write(".align 6\n")
		asm.write(".globl in_dim\n")
		asm.write("in_dim: .dword %d\n" % dim)

		for (name, _) in data:
			asm.write("\n")
			asm.write(".align 6\n")
			asm.write(".globl %s\n" % name)
			asm.write("%s:\n" % name)
			asm.write(".incbin \"%s/%s.dat\"\n" % (path, name))

def make_float_gemm(name, dtype, dim):
	in_alpha = np.random.randn(1).astype(dtype)
	in_beta = np.random.randn(1).astype(dtype)
	in_A = np.random.randn(dim, dim).astype(dtype)
	in_B = np.random.randn(dim, dim).astype(dtype)
	in_C = np.random.randn(dim, dim).astype(dtype)
	store_dataset("%s_%04d" % (name, dim), dim,
		("in_alpha", in_alpha),
		("in_beta", in_beta),
		("in_A", in_A),
		("in_B", in_B),
		("in_C", in_C),
		("exp", in_alpha * in_A * in_B + in_beta * in_C),
	)

for i in range(2,7):
	make_float_gemm("sgemm", np.float32, 2**i)
	make_float_gemm("dgemm", np.float64, 2**i)
