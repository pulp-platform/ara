#ifndef _FFTLIB_H
#define _FFTLIB_H

#include <riscv_vector.h>

typedef signed short v2s __attribute__((vector_size(4)));
typedef float v2f __attribute__((vector_size(8)));
typedef __fp16 v2sf __attribute__((vector_size(4)));

void fft_r2dif_vec(float *samples_re, float *samples_im,
                   const float *twiddles_re, const float *twiddles_im,
                   const uint8_t **mask_addr_vec, const uint32_t *index_ptr,
                   size_t n_fft);
static inline v2s cplxmuls(v2s x, v2s y);
static inline v2f cplxmuls_float(v2f x, v2f y);
static inline v2s cplxmulsdiv2(v2s x, v2s y);
void __attribute__((__noinline__)) SetupInput(signed short *In, int N, int Dyn);
void SetupR2SwapTable(short int *SwapTable, int Ni);
void SetupTwiddlesLUT(signed short *Twiddles, int Nfft, int Inverse);

void Radix4FFT_DIT_Scalar(signed short *__restrict__ Data,
                          signed short *__restrict__ Twiddles, int N_FFT4,
                          unsigned int Inverse);
void Radix4FFT_DIF_Scalar(signed short *__restrict__ Data,
                          signed short *__restrict__ Twiddles, int N_FFT4,
                          unsigned int Inverse);
void Radix2FFT_DIT_Scalar(signed short *__restrict__ Data,
                          signed short *__restrict__ Twiddles, int N_FFT2);
void Radix2FFT_DIF_Scalar(signed short *__restrict__ Data,
                          signed short *__restrict__ Twiddles, int N_FFT2);

void Radix4FFT_DIT(signed short *__restrict__ Data,
                   signed short *__restrict__ Twiddles, int N_FFT4,
                   unsigned int Inverse);
void Radix4FFT_DIF(signed short *__restrict__ Data,
                   signed short *__restrict__ Twiddles, int N_FFT4,
                   unsigned int Inverse);

void Radix2FFT_DIT(signed short *__restrict__ Data,
                   signed short *__restrict__ Twiddles, int N_FFT2);
void Radix2FFT_DIF(signed short *__restrict__ Data,
                   signed short *__restrict__ Twiddles, int N_FFT2);
void Radix2FFT_DIT_float(float *__restrict__ Data, float *__restrict__ Twiddles,
                         int N_FFT2);
void Radix2FFT_DIF_float(float *__restrict__ Data, float *__restrict__ Twiddles,
                         int N_FFT2, int n_break);

void SwapSamples(v2f *__restrict__ Data, short *__restrict__ SwapTable, int Ni);

float *cmplx2reim(v2f *cmplx, float *buf, size_t len);

#ifdef BUILD_LUT
void SetupTwiddlesLUT(signed short *Twiddles, int Nfft, int Inverse);
void SetupScalarTwiddlesLUT(signed short *Twiddles, int Nfft, int Inverse);

void SetupR2SwapTable(short int *SwapTable, int Ni);
#endif

#define FFT4_SAMPLE_DYN 12
#define FFT2_SAMPLE_DYN 13
#define FFT_TWIDDLE_DYN 15

#define FFT4_SCALEDOWN 2
#define FFT2_SCALEDOWN 1

#endif

vfloat32m1_t cmplx_mul_re_vf(vfloat32m1_t v0_re, vfloat32m1_t v0_im,
                             float f1_re, float f1_im, size_t vl);
vfloat32m1_t cmplx_mul_im_vf(vfloat32m1_t v0_re, vfloat32m1_t v0_im,
                             float f1_re, float f1_im, size_t vl);
vfloat32m1_t cmplx_mul_re_vv(vfloat32m1_t v0_re, vfloat32m1_t v0_im,
                             vfloat32m1_t f1_re, vfloat32m1_t f1_im, size_t vl);
vfloat32m1_t cmplx_mul_im_vv(vfloat32m1_t v0_re, vfloat32m1_t v0_im,
                             vfloat32m1_t f1_re, vfloat32m1_t f1_im, size_t vl);
