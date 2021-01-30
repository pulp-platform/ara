#ifndef MATMUL_H
#define MATMUL_H

#include <stdint.h>

void matmul(int64_t *c, const int64_t *a, const int64_t *b, int64_t m, int64_t n, int64_t p);

void matmul_vec_4x4_slice_init(int64_t *c, int64_t N);
void matmul_vec_4x4(int64_t *c, const int64_t *a, const int64_t *b, int64_t N, int64_t P);

#endif
