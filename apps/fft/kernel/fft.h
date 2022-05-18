#ifndef _FFTLIB_H
#define _FFTLIB_H

#include <riscv_vector.h>

typedef signed short v2s __attribute__((vector_size (4)));
typedef float v2f __attribute__((vector_size (8)));
typedef __fp16 v2sf __attribute__((vector_size (4)));

// Default data type
#ifndef dtype
#define dtype float
#define vdtype vfloat32m1_t
#define cmplxtype v2f
#endif

void fft_r2dif_vec(float* samples_re, float* samples_im,
                   const float* twiddles_re, const float* twiddles_im,
                   const uint8_t** mask_addr_vec, const uint32_t* index_ptr, size_t n_fft);
static inline v2s cplxmuls(v2s x, v2s y);
static inline cmplxtype cplxmuls_float(cmplxtype x, cmplxtype y);
static inline v2s cplxmulsdiv2(v2s x, v2s y);
void  __attribute__ ((__noinline__)) SetupInput(signed short *In, int N, int Dyn);
void SetupR2SwapTable (short int *SwapTable, int Ni);
void SetupTwiddlesLUT(signed short *Twiddles, int Nfft, int Inverse);

void Radix4FFT_DIT_Scalar(signed short *__restrict__ Data, signed short *__restrict__ Twiddles, int N_FFT4, unsigned int Inverse);
void Radix4FFT_DIF_Scalar(signed short *__restrict__ Data, signed short *__restrict__ Twiddles, int N_FFT4, unsigned int Inverse);
void Radix2FFT_DIT_Scalar(signed short *__restrict__ Data, signed short *__restrict__ Twiddles, int N_FFT2);
void Radix2FFT_DIF_Scalar(signed short *__restrict__ Data, signed short *__restrict__ Twiddles, int N_FFT2);

void Radix4FFT_DIT(signed short *__restrict__ Data, signed short *__restrict__ Twiddles, int N_FFT4, unsigned int Inverse);
void Radix4FFT_DIF(signed short *__restrict__ Data, signed short *__restrict__ Twiddles, int N_FFT4, unsigned int Inverse);

void Radix2FFT_DIT(signed short *__restrict__ Data, signed short *__restrict__ Twiddles, int N_FFT2);
void Radix2FFT_DIF(signed short *__restrict__ Data, signed short *__restrict__ Twiddles, int N_FFT2);
void Radix2FFT_DIT_float(dtype *__restrict__ Data, dtype *__restrict__ Twiddles, int N_FFT2);
void Radix2FFT_DIF_float(dtype *__restrict__ Data, dtype *__restrict__ Twiddles, int N_FFT2, int n_break);

void SwapSamples (cmplxtype *__restrict__ Data, short *__restrict__ SwapTable, int Ni);

float* cmplx2reim(cmplxtype* cmplx, dtype* buf, size_t len);

#ifdef BUILD_LUT
void SetupTwiddlesLUT(signed short *Twiddles, int Nfft, int Inverse);
void SetupScalarTwiddlesLUT(signed short *Twiddles, int Nfft, int Inverse);

void SetupR2SwapTable (short int *SwapTable, int Ni);
#endif

#define FFT4_SAMPLE_DYN 12
#define FFT2_SAMPLE_DYN 13
#define FFT_TWIDDLE_DYN 15

#define FFT4_SCALEDOWN 2
#define FFT2_SCALEDOWN 1

#endif

vdtype cmplx_mul_re_vf(vdtype v0_re, vdtype v0_im, dtype f1_re, dtype f1_im, size_t vl);
vdtype cmplx_mul_im_vf(vdtype v0_re, vdtype v0_im, dtype f1_re, dtype f1_im, size_t vl);
vdtype cmplx_mul_re_vv(vdtype v0_re, vdtype v0_im, vdtype f1_re, vdtype f1_im, size_t vl);
vdtype cmplx_mul_im_vv(vdtype v0_re, vdtype v0_im, vdtype f1_re, vdtype f1_im, size_t vl);
