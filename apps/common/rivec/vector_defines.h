// Modified version of:
// vector_defines.h
// https://github.com/RALC88/riscv-vectorized-benchmark-suite/blob/rvv-1.0/common/vector_defines.h
// Find details on the original version below
// Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>

// RISC-V VECTOR intrinsics mapping by Cristóbal Ramírez Lazo, "Barcelona 2019"

#ifndef _RIVEC_VECTOR_DEFINES_H_
#define _RIVEC_VECTOR_DEFINES_H_

#include "riscv_vector.h"

#define _MM_ALIGN64 __attribute__((aligned(64)))

#define MUSTINLINE __attribute__((always_inline))

//---------------------------------------------------------------------------
// DATA TYPES

#define _MMR_f64 vfloat64m1_t
#define _MMR_f32 vfloat32m1_t

#define _MMR_i64 vint64m1_t
#define _MMR_i32 vint32m1_t

#define _MMR_i32mf2 vint32mf2_t

#define _MMR_u64 vuint64m1_t
#define _MMR_u32 vuint32m1_t

#define _MMR_MASK_i64 vbool64_t
#define _MMR_MASK_i32 vbool32_t
#define _MMR_MASK_i1 vbool1_t

// CONFIG INST

#define _MMR_VSETVL_E64M1 __riscv_vsetvl_e64m1
#define _MMR_VSETVL_E32M1 __riscv_vsetvl_e32m1

#define _MMR_VSETVLMAX_E64M1 __riscv_vsetvlmax_e64m1
#define _MMR_VSETVLMAX_E32M1 __riscv_vsetvlmax_e32m1

//---------------------------------------------------------------------------
// REINTERPRET VECTOR TYPE

// int to bool(mask)
#define _MM_CAST_i1_i64 __riscv_vreinterpret_v_i64m1_b64
#define _MM_CAST_i1_i32 __riscv_vreinterpret_v_i32m1_b32

// int to float
#define _MM_CAST_f64_i64 __riscv_vreinterpret_v_i64m1_f64m1
#define _MM_CAST_f32_i32 __riscv_vreinterpret_v_i32m1_f32m1

// float to int
#define _MM_CAST_i64_f64 __riscv_vreinterpret_v_f64m1_i64m1
#define _MM_CAST_i32_f32 __riscv_vreinterpret_v_f32m1_i32m1

// uint to int
#define _MM_CAST_i64_u64 __riscv_vreinterpret_v_u64m1_i64m1
#define _MM_CAST_i32_u32 __riscv_vreinterpret_v_u32m1_i32m1

// int to uint
#define _MM_CAST_u64_i64 __riscv_vreinterpret_v_i64m1_u64m1
#define _MM_CAST_u32_i32 __riscv_vreinterpret_v_i32m1_u32m1

// longint to int
#define _MM_CAST_i32_i64 __riscv_vreinterpret_v_i64m1_i32m1

// NOTE: It is possible to reinterpret data types, from integer to float, float
// to integer,
//       mask to integer, integer to mask .. etc.

//---------------------------------------------------------------------------
// INTEGER INTRINSICS

#define _MM_LOAD_i64 __riscv_vle64_v_i64m1
#define _MM_LOAD_i32 __riscv_vle32_v_i32m1

#define _MM_LOAD_u64 __riscv_vle64_v_u64m1
#define _MM_LOAD_u32 __riscv_vle32_v_u32m1

#define _MM_LOAD_i32mf2 __riscv_vle32_v_i32mf2

#define _MM_LOAD_INDEX_i64 __riscv_vloxei64_v_i64m1
#define _MM_LOAD_INDEX_i32 __riscv_vloxei32_v_i32m1

#define _MM_LOAD_STRIDE_i64 __riscv_vlse64_v_i64m1
#define _MM_LOAD_STRIDE_i32 __riscv_vlse32_v_i32m1

#define _MM_STORE_i64 __riscv_vse64_v_i64m1
#define _MM_STORE_i32 __riscv_vse32_v_i32m1
#define _MM_STORE_i16 __riscv_vse16_v_i16m1
#define _MM_STORE_i8 __riscv_vse8_v_i8m1

#define _MM_STORE_i32mf2 __riscv_vse32_v_i32mf2

#define _MM_STORE_INDEX_i64 __riscv_vsoxei64_v_i64m1
#define _MM_STORE_INDEX_i32 __riscv_vsoxei32_v_f32m1

#define _MM_STORE_STRIDE_i64 __riscv_vsse64_v_i64m1
#define _MM_STORE_STRIDE_i32 __riscv_vsse32_v_i32m1

#define _MM_ADD_i64 __riscv_vadd_vv_i64m1
#define _MM_ADD_i32 __riscv_vadd_vv_i32m1

#define _MM_ADD_VX_i64 __riscv_vadd_vx_i64m1
#define _MM_ADD_VX_i32 __riscv_vadd_vx_i32m1

#define _MM_ADD_i32mf2 __riscv_vadd_vv_i32mf2

#define _MM_SUB_i64 __riscv_vsub_vv_i64m1
#define _MM_SUB_i32 __riscv_vsub_vv_i32m1

#define _MM_SUB_VX_i64 __riscv_vsub_vx_i64m1
#define _MM_SUB_VX_i32 __riscv_vsub_vx_i32m1

#define _MM_ADD_i64_MASK __riscv_vadd_vv_i64m1_m
#define _MM_ADD_i32_MASK __riscv_vadd_vv_i32m1_m

#define _MM_MUL_i64 __riscv_vmul_vv_i64m1
#define _MM_MUL_i32 __riscv_vmul_vv_i32m1
#define _MM_MUL_i16 __riscv_vmul_vv_i16m1
#define _MM_MUL_i8 __riscv_vmul_vv_i8m1

#define _MM_MUL_i32mf2 __riscv_vmul_vv_i32mf2

#define _MM_DIV_i64 __riscv_vdiv_vv_i64m1
#define _MM_DIV_i32 __riscv_vdiv_vv_i32m1

#define _MM_REM_i64 __riscv_vrem_vv_i64m1
#define _MM_REM_i32 __riscv_vrem_vv_i32m1

#define _MM_REM_i32mf2 __riscv_vrem_vv_i32mf2

#define _MM_SET_i64 __riscv_vmv_v_x_i64m1
#define _MM_SET_i32 __riscv_vmv_v_x_i32m1

#define _MM_SET_u64 __riscv_vmv_v_x_u64m1
#define _MM_SET_u32 __riscv_vmv_v_x_u32m1

#define _MM_SET_i32mf2 __riscv_vmv_v_x_i32mf2

#define _MM_MIN_i64 __riscv_vmin_vv_i64m1
#define _MM_MIN_i32 __riscv_vmin_vv_i32m1

#define _MM_MAX_i64 __riscv_vmax_vv_i64m1
#define _MM_MAX_i32 __riscv_vmax_vv_i32m1

#define _MM_SLL_i64 __riscv_vsll_vv_i64m1
#define _MM_SLL_i32 __riscv_vsll_vv_i32m1

#define _MM_SLL_u64 __riscv_vsll_vv_u64m1
#define _MM_SLL_u32 __riscv_vsll_vv_u32m1

#define _MM_SLL_VX_i64 __riscv_vsll_vx_i64m1
#define _MM_SLL_VX_i32 __riscv_vsll_vx_i32m1

#define _MM_SLL_VX_u64 __riscv_vsll_vx_u64m1
#define _MM_SLL_VX_u32 __riscv_vsll_vx_u32m1

#define _MM_SRL_i64 __riscv_vsrl_vv_u64m1
#define _MM_SRL_i32 __riscv_vsrl_vv_u32m1

#define _MM_AND_i64 __riscv_vand_vv_i64m1
#define _MM_AND_i32 __riscv_vand_vv_i32m1

#define _MM_AND_VX_i64 __riscv_vand_vx_i64m1
#define _MM_AND_VX_i32 __riscv_vand_vx_i32m1

#define _MM_OR_i64 __riscv_vor_vv_i64m1
#define _MM_OR_i32 __riscv_vor_vv_i32m1

#define _MM_OR_VX_i64 __riscv_vor_vx_i64m1
#define _MM_OR_VX_i32 __riscv_vor_vx_i32m1

#define _MM_XOR_i64 __riscv_vxor_vv_i64m1
#define _MM_XOR_i32 __riscv_vxor_vv_i32m1

#define _MM_XOR_VX_i64 __riscv_vxor_vx_i64m1
#define _MM_XOR_VX_i32 __riscv_vxor_vx_i32m1

#define _MM_NOT_i64(x) _MM_XOR_i64((x), (x), gvl)
#define _MM_NOT_i32(x) _MM_XOR_i32((x), (x), gvl)

#define _MM_MERGE_i64 __riscv_vmerge_vvm_i64m1
#define _MM_MERGE_i32 __riscv_vmerge_vvm_i32m1

#define _MM_MERGE_VX_i64 __riscv_vmerge_vxm_i64m1
#define _MM_MERGE_VX_i32 __riscv_vmerge_vxm_i32m1

//---------------------------------------------------------------------------
// FLOATING POINT INTRINSICS

#define _MM_LOAD_f64 __riscv_vle64_v_f64m1
#define _MM_LOAD_f32 __riscv_vle32_v_f32m1

#define _MM_LOAD_INDEX_f64 __riscv_vloxei64_v_f64m1
#define _MM_LOAD_INDEX_f32 __riscv_vloxei32_v_f32m1

#define _MM_LOAD_U_INDEX_f64 __riscv_vluxei64_v_f64m1
#define _MM_LOAD_U_INDEX_f32 __riscv_vluxei32_v_f32m1

#define _MM_LOAD_STRIDE_f64 __riscv_vlse64_v_f64m1
#define _MM_LOAD_STRIDE_f32 __riscv_vlse32_v_f32m1

#define _MM_STORE_f64 __riscv_vse64_v_f64m1
#define _MM_STORE_f32 __riscv_vse32_v_f32m1

#define _MM_STORE_INDEX_f64 __riscv_vsoxei64_v_f64m1
#define _MM_STORE_INDEX_f32 __riscv_vsoxei32_v_f32m1

#define _MM_STORE_STRIDE_f64 __riscv_vsse64_v_f64m1
#define _MM_STORE_STRIDE_f32 __riscv_vsse32_v_f32m1

#define _MM_MUL_f64 __riscv_vfmul_vv_f64m1
#define _MM_MUL_f32 __riscv_vfmul_vv_f32m1

#define _MM_MUL_VF_f64 __riscv_vfmul_vf_f64m1
#define _MM_MUL_VF_f32 __riscv_vfmul_vf_f32m1

#define _MM_ADD_f64 __riscv_vfadd_vv_f64m1
#define _MM_ADD_f32 __riscv_vfadd_vv_f32m1

#define _MM_ADD_VF_f64 __riscv_vfadd_vf_f64m1
#define _MM_ADD_VF_f32 __riscv_vfadd_vf_f32m1

#define _MM_SUB_f64 __riscv_vfsub_vv_f64m1
#define _MM_SUB_f32 __riscv_vfsub_vv_f32m1

#define _MM_SUB_VF_f64 __riscv_vfsub_vf_f64m1
#define _MM_SUB_VF_f32 __riscv_vfsub_vf_f32m1

#define _MM_SUB_f64_MASK __riscv_vfsub_vv_f64m1_m
#define _MM_SUB_f32_MASK __riscv_vfsub_vv_f32m1_m

#define _MM_ADD_f64_MASK __riscv_vfadd_vv_f64m1_m
#define _MM_ADD_f32_MASK __riscv_vfadd_vv_f32m1_m

#define _MM_DIV_f64 __riscv_vfdiv_vv_f64m1
#define _MM_DIV_f32 __riscv_vfdiv_vv_f32m1

#define _MM_SQRT_f64 __riscv_vfsqrt_v_f64m1
#define _MM_SQRT_f32 __riscv_vfsqrt_v_f32m1

#define _MM_SET_f64 __riscv_vfmv_v_f_f64m1
#define _MM_SET_f32 __riscv_vfmv_v_f_f32m1

#define _MM_MIN_f64 __riscv_vfmin_vv_f64m1
#define _MM_MIN_f32 __riscv_vfmin_vv_f32m1

#define _MM_MIN_VF_f64 __riscv_vfmin_vf_f64m1
#define _MM_MIN_VF_f32 __riscv_vfmin_vf_f32m1

#define _MM_MAX_f64 __riscv_vfmax_vv_f64m1
#define _MM_MAX_f32 __riscv_vfmax_vv_f32m1

#define _MM_MAX_VF_f64 __riscv_vfmax_vf_f64m1
#define _MM_MAX_VF_f32 __riscv_vfmax_vf_f32m1

#define _MM_VFSGNJ_f64 __riscv_vfsgnj_vv_f64m1
#define _MM_VFSGNJ_f32 __riscv_vfsgnj_vv_f32m1

#define _MM_VFSGNJN_f64 __riscv_vfsgnjn_vv_f64m1
#define _MM_VFSGNJN_f32 __riscv_vfsgnjn_vv_f32m1

#define _MM_VFSGNJX_f64 __riscv_vfsgnjx_vv_f64m1
#define _MM_VFSGNJX_f32 __riscv_vfsgnjx_vv_f32m1

#define _MM_MERGE_f64 __riscv_vmerge_vvm_f64m1
#define _MM_MERGE_f32 __riscv_vmerge_vvm_f32m1

#define _MM_MERGE_VF_f64 __riscv_vfmerge_vfm_f64m1
#define _MM_MERGE_VF_f32 __riscv_vfmerge_vfm_f32m1

#define _MM_REDSUM_f64 __riscv_vfredusum_vs_f64m1_f64m1
#define _MM_REDSUM_f32 __riscv_vfredusum_vs_f32m1_f32m1

#define _MM_REDSUM_f64_MASK __riscv_vfredusum_vs_f64m1_f64m1_m
#define _MM_REDSUM_f32_MASK __riscv_vfredusum_vs_f32m1_f32m1_m

#define _MM_REDMIN_f64 __riscv_vfredmin_vs_f64m1_f64m1
#define _MM_REDMIN_f32 __riscv_vfredmin_vs_f32m1_f32m1

#define _MM_MACC_f64 __riscv_vfmacc_vv_f64m1
#define _MM_MACC_f32 __riscv_vfmacc_vv_f32m1

#define _MM_MACC_VF_f64 __riscv_vfmacc_vf_f64m1
#define _MM_MACC_VF_f32 __riscv_vfmacc_vf_f32m1

#define _MM_MADD_f64 __riscv_vfmadd_vv_f64m1
#define _MM_MADD_f32 __riscv_vfmadd_vv_f32m1

#define _MM_MADD_VF_f64 __riscv_vfmadd_vf_f64m1
#define _MM_MADD_VF_f32 __riscv_vfmadd_vf_f32m1

//---------------------------------------------------------------------------
// CONVERSION INTRINSICS

#define _MM_VFCVT_F_X_f64 __riscv_vfcvt_f_x_v_f64m1
#define _MM_VFCVT_F_X_f32 __riscv_vfcvt_f_x_v_f32m1

#define _MM_VFCVT_F_X_f32mf2 __riscv_vfcvt_f_x_v_f32mf2

#define _MM_VFCVT_X_F_i64 __riscv_vfcvt_x_f_v_i64m1
#define _MM_VFCVT_X_F_i32 __riscv_vfcvt_x_f_v_i32m1

#define _MM_VFWCVT_F_F_f64m1 __riscv_vfwcvt_f_f_v_f64m1
#define _MM_VFNCVT_F_F_f32m1 __riscv_vfncvt_f_f_w_f32m1

#define _MM_VFWCVT_F_X_f64m1 __riscv_vfwcvt_f_x_v_f64m1
#define _MM_VFNCVT_F_X_f32m1 __riscv_vfncvt_f_x_w_f32m1

//---------------------------------------------------------------------------
// VECTOR ELEMENT MANIPULATION

#define _MM_VSLIDEUP_i32 __riscv_vslideup_vx_i32m1
#define _MM_VSLIDEUP_i64 __riscv_vslideup_vx_i64m1

#define _MM_VSLIDE1UP_i32 __riscv_vslide1up_vx_i32m1
#define _MM_VSLIDE1UP_i64 __riscv_vslide1up_vx_i64m1

#define _MM_VSLIDEUP_i32_MASK __riscv_vslideup_vx_i32m1_m
#define _MM_VSLIDEUP_i64_MASK __riscv_vslideup_vx_i64m1_m

#define _MM_VSLIDEDOWN_i32 __riscv_vslidedown_vx_i32m1
#define _MM_VSLIDEDOWN_i64 __riscv_vslidedown_vx_i64m1

#define _MM_VSLIDE1DOWN_i32 __riscv_vslide1down_vx_i32m1
#define _MM_VSLIDE1DOWN_i64 __riscv_vslide1down_vx_i64m1

#define _MM_VSLIDEDOWN_i32_MASK __riscv_vslidedown_vx_i32m1_m
#define _MM_VSLIDEDOWN_i64_MASK __riscv_vslidedown_vx_i64m1_m

// fp

#define _MM_VGETFIRST_f32 __riscv_vfmv_f_s_f32m1_f32
#define _MM_VGETFIRST_f64 __riscv_vfmv_f_s_f64m1_f64

#define _MM_VSLIDEUP_f32 __riscv_vslideup_vx_f32m1
#define _MM_VSLIDEUP_f64 __riscv_vslideup_vx_f64m1

#define _MM_VSLIDE1UP_f32 __riscv_vfslide1up_vf_f32m1
#define _MM_VSLIDE1UP_f64 __riscv_vfslide1up_vf_f64m1

#define _MM_VSLIDEUP_f32_MASK __riscv_vslideup_vx_f32m1_m
#define _MM_VSLIDEUP_f64_MASK __riscv_vslideup_vx_f64m1_m

#define _MM_VSLIDEDOWN_f32 __riscv_vslidedown_vx_f32m1
#define _MM_VSLIDEDOWN_f64 __riscv_vslidedown_vx_f64m1

#define _MM_VSLIDE1DOWN_f32 __riscv_vfslide1down_vf_f32m1
#define _MM_VSLIDE1DOWN_f64 __riscv_vfslide1down_vf_f64m1

#define _MM_VSLIDEDOWN_f32_MASK __riscv_vslidedown_vx_f32m1_m
#define _MM_VSLIDEDOWN_f64_MASK __riscv_vslidedown_vx_f64m1_m
//---------------------------------------------------------------------------

// OPERATIONS WITH MASKS

#define _MM_VMFIRST_i64 __riscv_vfirst_m_b64
#define _MM_VMFIRST_i32 __riscv_vfirst_m_b32

#define _MM_VMPOPC_i64 __riscv_vcpop_m_b64
#define _MM_VMPOPC_i32 __riscv_vcpop_m_b32

#define _MM_VMAND_i64 __riscv_vmand_mm_b64
#define _MM_VMAND_i32 __riscv_vmand_mm_b32

#define _MM_VMNOR_i64 __riscv_vmnor_mm_b64
#define _MM_VMNOR_i32 __riscv_vmnor_mm_b32

#define _MM_VMOR_i64 __riscv_vmor_mm_b64
#define _MM_VMOR_i32 __riscv_vmor_mm_b32

#define _MM_VMXOR_i64 __riscv_vmxor_mm_b64
#define _MM_VMXOR_i32 __riscv_vmxor_mm_b32

// OPERATIONS TO CREATE A MASK

// Int

#define _MM_VMSLT_i64 __riscv_vmslt_vv_i64m1_b64
#define _MM_VMSLT_i32 __riscv_vmslt_vv_i32m1_b32

#define _MM_VMSEQ_i64 __riscv_vmseq_vv_i64m1_b64
#define _MM_VMSEQ_i32 __riscv_vmseq_vv_i32m1_b32

#define _MM_VMSEQ_VX_i64 __riscv_vmseq_vx_i64m1_b64
#define _MM_VMSEQ_VX_i32 __riscv_vmseq_vx_i32m1_b32

// Fp
#define _MM_VFEQ_f64 __riscv_vmfeq_vv_f64m1_b64
#define _MM_VFEQ_f32 __riscv_vmfeq_vv_f32m1_b32

#define _MM_VFGT_f64 __riscv_vmfgt_vv_f64m1_b64
#define _MM_VFGT_f32 __riscv_vmfgt_vv_f32m1_b32

#define _MM_VFGT_VF_f64 __riscv_vmfgt_vf_f64m1_b64
#define _MM_VFGT_VF_f32 __riscv_vmfgt_vf_f32m1_b32

#define _MM_VFGE_f64 __riscv_vmfge_vv_f64m1_b64
#define _MM_VFGE_f32 __riscv_vmfge_vv_f32m1_b32

#define _MM_VFGE_VF_f64 __riscv_vmfge_vf_f64m1_b64
#define _MM_VFGE_VF_f32 __riscv_vmfge_vf_f32m1_b32

#define _MM_VFLT_f64 __riscv_vmflt_vv_f64m1_b64
#define _MM_VFLT_f32 __riscv_vmflt_vv_f32m1_b32

#define _MM_VFLT_VF_f64 __riscv_vmflt_vf_f64m1_b64
#define _MM_VFLT_VF_f32 __riscv_vmflt_vf_f32m1_b32

#define _MM_VFLE_f64 __riscv_vmfle_vv_f64m1_b64
#define _MM_VFLE_f32 __riscv_vmfle_vv_f32m1_b32

#define _MM_VFLE_VF_f64 __riscv_vmfle_vf_f64m1_b64
#define _MM_VFLE_VF_f32 __riscv_vmfle_vf_f32m1_b32

//---------------------------------------------------------------------------
// ADVANCE RISC-V MATH LIBRARY

#ifndef _MM_LOG
#define _MM_LOG
#define _MM_LOG_f64 __log_1xf64
#define _MM_LOG_f32 __log_2xf32
#endif

#ifndef _MM_EXP
#define _MM_EXP
#define _MM_EXP_f64 __exp_1xf64
#define _MM_EXP_f32 __exp_2xf32
#endif

#ifndef _MM_COS
#define _MM_COS
#define _MM_COS_f64 __cos_1xf64
#define _MM_COS_f32 __cos_1xf32
#endif

#define FENCE() asm volatile("fence");

#endif
