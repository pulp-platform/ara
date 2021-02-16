#ifndef MATMUL_H
#define MATMUL_H

#include <stdint.h>

void matmul(int64_t *c, const int64_t *a, const int64_t *b, int64_t m, int64_t n, int64_t p);

void matmul_4x4(int64_t *c, const int64_t *a, const int64_t *b, int64_t m, int64_t n, int64_t p);
void matmul_vec_4x4_slice_init();
void matmul_vec_4x4(int64_t *c, const int64_t *a, const int64_t *b, int64_t n, int64_t p);

void matmul_8x8(int64_t *c, const int64_t *a, const int64_t *b, int64_t m, int64_t n, int64_t p);
void matmul_vec_8x8_slice_init();
void matmul_vec_8x8(int64_t *c, const int64_t *a, const int64_t *b, int64_t n, int64_t p);

#endif
