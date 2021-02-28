#ifndef MATMUL_H
#define MATMUL_H

#include <stdint.h>

void matmul(double *c, const double *a, const double *b, int64_t m, int64_t n, int64_t p);

void matmul_4x4(double *c, const double *a, const double *b, int64_t m, int64_t n, int64_t p);
void matmul_vec_4x4_slice_init();
void matmul_vec_4x4(double *c, const double *a, const double *b, int64_t n, int64_t p);

void matmul_8x8(double *c, const double *a, const double *b, int64_t m, int64_t n, int64_t p);
void matmul_vec_8x8_slice_init();
void matmul_vec_8x8(double *c, const double *a, const double *b, int64_t n, int64_t p);

void matmul_16x16(double *c, const double *a, const double *b, int64_t m, int64_t n, int64_t p);
void matmul_vec_16x16_slice_init();
void matmul_vec_16x16(double *c, const double *a, const double *b, int64_t n, int64_t p);

#endif
