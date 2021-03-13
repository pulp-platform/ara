# Functionalities

This file specifies the functionalities of the RISC-V Vector Specification supported by Ara.

## Constant Parameters

- Maximum size of a single vector element in bits: ELEN = 64
- Striping distance, in bits: SLEN = 64

## Vector Loads and Stores

- Vector unit-strided loads: `vle<eew>, vl1r.v`
- Vector unit-strided stores: `vse<eew>`, `vs1r.v`

## Vector Integer Arithmetic Instructions

- Vector single-width integer add and subtract instructions: `vadd`, `vsub`, `vrsub`
- Vector widening integer add and subtract instructions: `vwaddu`, `vwsubu`, `vwadd`, `vwsub`
- Vector integer extension instructions: `vzext`, `vsext`
- Vector integer add-with-carry/subtract-with-borrow instructions: `vadc`, `vmadc`, `vsbc`, `vmsbc`
- Vector bitwise logical instructions: `vand`, `vor`, `vxor`
- Vector single-width bit shift instructions: `vsll`, `vsrl`, `vsra`
- Vector narrowing integer right shift instructions: `vnsrl`, `vnsra`
- Vector integer comparison instructions: `vmseq`, `vmsne`, `vmsltu`, `vmslt`, `vmsleu`, `vmsle`, `vmsgtu`, `vmsgt`
- Vector integer min/max instructions: `vminu`, `vmin`, `vmaxu`, `vmax`
- Vector single-width integer multiply instructions: `vmul`, `vmulh`, `vmulhu`, `vmulhsu`
- Vector integer divide instructions: `vdivu`, `vdiv`, `vremu`, `vrem`
- Vector widening integer multiply instructions: `vwmul`, `vwmulu`, `vwmulsu`
- Vector single-width integer multiply-add instructions: `vmacc`, `vnmsac`, `vmadd`, `vnmsub`
- Vector widening integer multiply-add instructions: `vwmaccu`, `vwmacc`, `vwmaccsu`, `vwmaccus`
- Vector integer merge instructions: `vmerge`
- Vector integer move instructions: `vmv`

## Vector Floating-Point Instructions

- Vector single-width floating-point add/subtract instructions: `vfadd`, `vfsub`, `vfrsub`
- Vector single-width floating-point multiply/divide instructions: `vfmul`
- Vector single-width floating-point fused multiply-add instructions: `vfmacc`, `vfnmacc`, `vfmsac`, `vfnmsac`, `vfmadd`, `vfnmadd`, `vfmsub`, `vfnmsub`
- Vector floating-point min/max instructions: `vfmin`, `vfmax`
- Vector floating-point sign-injection instructions: `vfsgnj`, `vfsgnjn`, `vfsgnjx`

## Vector mask instructions

- Vector mask-register logical instructions: `vmand`, `vmnand`, `vmandnot`, `vmxor`, `vmor`, `vmnor`, `vmornot`, `vmxnor`
