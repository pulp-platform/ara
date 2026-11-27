# Ara2 FPU latency: compare fix and FP32 FMA known issue

## 1. FP compare latency in `vmfpu` (bug fix)

File: `hardware/src/lane/vmfpu.sv`, function `fpu_latency()`.

**Change.**
```systemverilog
[VMFEQ:VMFGE]:          fpu_latency = LatFNonComp;
```

**Why.** `vmfpu` lets an instruction issue while another is still in fpnew only
if the new one is not faster (`latency_problem_d = issue_lat < processing_lat`).
`fpu_latency()` had no arm for `[VMFEQ:VMFGE]`, so compares got the FMA latency
of their SEW from the default arm, while fpnew runs them in the NONCOMP opgroup
(`LatFNonComp = 1`). A compare issued right behind an FP add or FMA therefore
did not stall, its mask left fpnew first, and `vmfpu` took it as the earlier
instruction's result, under that instruction's id. Both results were wrong.
With the fix, the compare waits behind the slower FP instruction (about one
stall per such compare).

**How it shows up.** `log` with its constants hoisted out of the strip loop has
`vfadd.vf v6, v6, 1.0` immediately followed by `vmflt.vf v0, v4, sqrt(0.5)`.
The compare result overtakes the add's result and both land in the wrong
destination words, so some outputs are wrong (most by a multiple of ln 2).
The intrinsic `log` re-broadcasts its constants on every
strip; the broadcasts sit between the two instructions, so it does not hit it.

**Timing.** One more range check on `op` in `fpu_latency()`, in parallel with
the existing arms. It feeds `latency_problem_d`, which is registered, so there
is no new path (check with `report_timing -to */i_vmfpu/latency_problem_q*`).

## 2. Known issue (not changed): FP32 FMA results lose VRF bank arbitration

**Symptom.** At equal bytes, FP32 kernels that chain FMAs run slower than FP64: `log`
about 15 % and `cos` about 12 % more cycles, and `fconv2d` 7x7 reaches 74 % FPU
utilization in FP32 against 96 % in FP64 (4 lanes, verification sizes).

**Cause.** The FMA is PARALLEL in Ara2 (one fpnew slice per format), and
`LatFCompEW32 = 4` gives the FP32 slice one pipeline stage less than FP64
(`LatFCompEW64 = 5`). The FP32 result comes back one cycle earlier, and its
write-back lands on the VRF bank that the next dependent instruction is reading.
The round-robin arbiter gives the bank to the read, the result queue fills and the
FPU stalls. A VRF trace of `log` (lane 0) shows the same VRF work in both
precisions, but the FMA result write loses its bank 1888 times in FP32 against
1072 in FP64.

**Possible fix (not applied).** `LatFCompEW32 = 'd5`, the same as FP64: one more
register stage in the FP32 FMA slice, `LatFMax` unchanged. With it, the FP32/FP64
cycle ratio of `log`, `cos` and `exp` is about 1.00 and `fconv2d` 7x7 FP32 reaches
95.8 % (measured together with the other kernel changes).
