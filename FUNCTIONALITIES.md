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

## Vector mask instructions

- Vector mask-register logical instructions: `vmand`, `vmnand`, `vmandnot`, `vmxor`, `vmor`, `vmnor`, `vmornot`, `vmxnor`
