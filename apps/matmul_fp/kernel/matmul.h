#ifndef MATMUL_H
#define MATMUL_H

#include <stdint.h>

void matmul(double *c, const double *a, const double *b, int64_t m, int64_t n, int64_t p);

void matmul_vec_4x4_slice_init(double *c, int64_t N);
void matmul_vec_4x4(double *c, const double *a, const double *b, int64_t N, int64_t P);

#endif
