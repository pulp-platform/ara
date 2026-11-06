# Linpack Benchmark for Ara2

A full Linpack benchmark (blocked LU decomposition with partial pivoting +
triangular solve) for Ara2, built on hand-written RVV 1.0 intrinsics DGEMM
kernels with parameterizable register blocking.

## Features

- **26 DGEMM kernel configurations** (MR × LMUL × KC × pipeline) generated
  via C macro templates, selectable at runtime
- **Full Linpack chain**: blocked LU + partial pivoting + HPL-style residual
  verification (IEEE FP64)
- **VLEN-agnostic**: same binary runs on any RVV 1.0 implementation
  (verified on QEMU at VLEN=128~1024, Verilator RTL, and SiPtech C908
  commercial silicon at VLEN=128)
- **Microarchitecture-aware design rules**:
  - Bandwidth matching: MR ≥ 4 to balance VLSU (4L B/cyc) vs FPU (8L B/cyc)
  - VRF budget: MR×LMUL + LMUL + 2 ≤ 30 to avoid register spilling
  - Issue budget: LMUL increases vector length to amortize CVA6 issue rate

## Usage

```bash
cd apps
make bin/linpack

# RTL simulation
cd ../hardware
app=linpack make simv

# Different lane configs
app=linpack make simv config=4_lanes
```

## Results (RTL, Verilator, 4 lanes)

| Metric | Value |
|---|---|
| Functional checks | 14 configs, maxdiff = 0 (bit-exact) |
| Best kernel utilization | 61.9% (mr8/lmul2/kc128) |
| Scalar baseline | 1.68% |
| On C908 (VLEN=128) | 3.38× speedup, best config mr2×lmul8 |

## Authors

- Team "光明未来" — RISC-V Innovation Competition 2026
  - Linpack kernels, RVV intrinsics engine: initial draft
  - RTL port & cycle-accurate measurement: integration and validation

## License

SPDX-License-Identifier: Apache-2.0
