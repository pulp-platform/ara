# Functionalities

This file specifies the functionalities of the RISC-V Vector Specification supported by Ara.

## Constant Parameters

- Maximum size of a single vector element in bits: ELEN = 64
- Striping distance, in bits: SLEN = 64

## Vector Loads and Stores

- Vector unit-strided loads: `vle<eew>, vl1r.v`
- Vector unit-strided stores: `vse<eew>`, `vs1r.v`
- Vector strided loads: `vlse<eew>`
- Vector strided stores: `vsse<eew>`
- Vector indexed loads: `vluxei<eew>`, `vloxei<eew>`
- Vector indexed stores: `vsuxei<eew>`, `vsoxei<eew>`

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
- Vector whole-register move instructions: `vmv<nr>r`

## Vector Floating-Point Instructions

- Vector single-width floating-point add/subtract instructions: `vfadd`, `vfsub`, `vfrsub`
- Vector widening floating-point add/subtract instructions: `vfwadd`, `vfwsub`, `vfwadd.w`, `vfwsub.w`
- Vector single-width floating-point multiply/divide instructions: `vfmul`
- Vector widening floating-point multiply/divide instructions: `vfwmul`
- Vector single-width floating-point fused multiply-add instructions: `vfmacc`, `vfnmacc`, `vfmsac`, `vfnmsac`, `vfmadd`, `vfnmadd`, `vfmsub`, `vfnmsub`
- Vector widening floating-point fused multiply-add instructions: `vfwmacc`, `vfwnmacc`, `vfwmsac`, `vfwnmsac`
- Vector floating-point min/max instructions: `vfmin`, `vfmax`
- Vector floating-point sign-injection instructions: `vfsgnj`, `vfsgnjn`, `vfsgnjx`
- Vector floating-point merge instruction: `vfmerge`
- Vector floating-point move instruction: `vfmv`
- Vector floating-point compare instructions: `vmfeq`, `vmfne`, `vmflt`, `vmfle`, `vmfgt`, `vmfge`
- Vector single-width floating-point/integer type-convert instructions:`vfcvt.xu.f`, `vfcvt.x.f`, `vfcvt.rtz.xu.f`, `vfcvt.rtz.x.f`, `vfcvt.f.xu`, `vfcvt.f.x`
- Vector widening floating-point/integer type-convert instructions: `vfwcvt.xu.f`, `vfwcvt.x.f`, `vfwcvt.rtz.xu.f`, `vfwcvt.rtz.x.f`, `vfwcvt.f.xu`, `vfwcvt.f.x`, `vfwcvt.f.f`
- Vector narrowing floating-point/integer type-convert instructions: `vfncvt.xu.f`, `vfncvt.x.f`, `vfncvt.rtz.xu.f`, `vfncvt.rtz.x.f`, `vfncvt.f.xu`, `vfncvt.f.x`, `vfncvt.f.f`

## Vector Reduction Operations

- Vector single-width integer reduction instructions: `vredsum`, `vredmaxu`, `vredmax`, `vredminu`, `vredmin`, `vredand`, `vredor`, `vredxor`
- Vector widening integer reductions: `vwredsumu`, `vwredsum`
- Vector single-width floating-point reduction instructions: `vfredusum`, `vfredosum`, `vfredmin`, `vfredmax`
- Vector widening floating-point reductions: `vfwredusum`, `vfwredosum`

## Vector mask instructions

- Vector mask-register logical instructions: `vmand`, `vmnand`, `vmandnot`, `vmxor`, `vmor`, `vmnor`, `vmornot`, `vmxnor`

## Vector permutation instructions

- Integer Scalar Move instructions: `vmv.x.s`, `vmv.s.x`
- Floating-Point Scalar Move instructions: `vfmv.f.s`, `vfmv.s.f`
- Vector slide instructions: `vslideup`, `vslidedown`, `vslide1up`, `vfslide1up`, `vslide1down`, `vfslide1down`
