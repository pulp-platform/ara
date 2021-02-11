#include "matmul.h"

#define MIN(a,b) ((a)<(b)?(a):(b))

void matmul(int64_t *c, const int64_t *a, const int64_t *b, int64_t M, int64_t N, int64_t P) {
  // We work on 4 rows of the matrix at once
  int64_t block_size = 4;
  int64_t block_size_p;

  // Set the vector configuration
  asm volatile ("vsetvli %0, %1, e64, m4" : "=r" (block_size_p) : "r" (P));

  // Slice the matrix into a manageable number of columns p_
  for (int64_t p = 0; p < P; p += block_size_p) {
    // Set the vector length
    int64_t p_ = MIN(P - p, block_size_p);
    asm volatile ("vsetvli zero, %0, e64, m4" :: "r" (p_));

    // Find pointers to the submatrices
    const int64_t *b_ = b + p;
    int64_t *c_ = c + p;

    // Iterate over the rows
    for (int64_t m = 0; m < M; m += block_size) {
      // Find pointer to the submatrices
      const int64_t *a_ = a + m*N;
      int64_t *c__ = c_ + m*P;

      // Call the kernels
      matmul_vec_4x4_slice_init(c__, P);
      matmul_vec_4x4(c__, a_, b_, N, P);
    }
  }
}

void matmul_vec_4x4_slice_init(int64_t *c, int64_t P) {
  // Helper variables
  int64_t ldc = P << 3;

  asm volatile ("vle64.v v0,  (%0); add %0, %0, %1" : "+r" (c) : "r" (ldc));
  asm volatile ("vle64.v v4,  (%0); add %0, %0, %1" : "+r" (c) : "r" (ldc));
  asm volatile ("vle64.v v8,  (%0); add %0, %0, %1" : "+r" (c) : "r" (ldc));
  asm volatile ("vle64.v v12, (%0);"                : "+r" (c) : "r" (ldc));
}

void matmul_vec_4x4(int64_t *c, const int64_t *a, const int64_t *b, int64_t N, int64_t P) {
  // Helper variables
  int64_t lda = N << 3;
  int64_t ldb = P << 3;
  int64_t ldc = P << 3;

  // Temporary variables
  int64_t t0, t1, t2, t3;

  // Original pointer
  const int64_t *a_ = a;

  // Prefetch one row of matrix B
  asm volatile ("vle64.v v16, (%0); add %0, %0, %1" : "+r" (b) : "r" (ldb));

  // Prefetch one row of scalar floating point values
  asm volatile ("ld %1, (%0); add %0, %0, %2" : "+r" (a), "=r" (t0) : "r" (lda));
  asm volatile ("ld %1, (%0); add %0, %0, %2" : "+r" (a), "=r" (t1) : "r" (lda));
  asm volatile ("ld %1, (%0); add %0, %0, %2" : "+r" (a), "=r" (t2) : "r" (lda));
  asm volatile ("ld %1, (%0);"                : "+r" (a), "=r" (t3));

  // Compute the multiplication
  int64_t n = 0;

  while (n < N) {
    // Load one row of B
    asm volatile ("vle64.v v20, (%0); add %0, %0, %1" : "+r" (b) : "r" (ldb)); n++;

    // Calculate pointer to the matrix A
    a = a_ + n;

    asm volatile ("vmacc.vx v0, %0, v16" :: "r" (t0));
    asm volatile ("ld %1, (%0); add %0, %0, %2" : "+r" (a), "=r" (t0) : "r" (lda));
    asm volatile ("vmacc.vx v4, %0, v16" :: "r" (t1));
    asm volatile ("ld %1, (%0); add %0, %0, %2" : "+r" (a), "=r" (t1) : "r" (lda));
    asm volatile ("vmacc.vx v8, %0, v16" :: "r" (t2));
    asm volatile ("ld %1, (%0); add %0, %0, %2" : "+r" (a), "=r" (t2) : "r" (lda));
    asm volatile ("vmacc.vx v12, %0, v16" :: "r" (t3));
    asm volatile ("ld %1, (%0);"                : "+r" (a), "=r" (t3));

    if (n == N-1)
      break;

    // Load one row of B
    asm volatile ("vle64.v v16, (%0); add %0, %0, %1" : "+r" (b) : "r" (ldb)); n++;
    a = (const int64_t*) a_ + n;

    asm volatile ("vmacc.vx v0, %0, v20" :: "r" (t0));
    asm volatile ("ld %1, (%0); add %0, %0, %2" : "+r" (a), "=r" (t0) : "r" (lda));
    asm volatile ("vmacc.vx v4, %0, v20" :: "r" (t1));
    asm volatile ("ld %1, (%0); add %0, %0, %2" : "+r" (a), "=r" (t1) : "r" (lda));
    asm volatile ("vmacc.vx v8, %0, v20" :: "r" (t2));
    asm volatile ("ld %1, (%0); add %0, %0, %2" : "+r" (a), "=r" (t2) : "r" (lda));
    asm volatile ("vmacc.vx v12, %0, v20" :: "r" (t3));
    asm volatile ("ld %1, (%0);"                : "+r" (a), "=r" (t3));
  }

  // Last iteration: store results
  asm volatile ("vmacc.vx v0, %0, v20" :: "r" (t0));
  asm volatile ("vse64.v v0, (%0); add %0, %0, %1" : "+r" (c) : "r" (ldc));
  asm volatile ("vmacc.vx v4, %0, v20" :: "r" (t1));
  asm volatile ("vse64.v v4, (%0); add %0, %0, %1" : "+r" (c) : "r" (ldc));
  asm volatile ("vmacc.vx v8, %0, v20" :: "r" (t2));
  asm volatile ("vse64.v v8, (%0); add %0, %0, %1" : "+r" (c) : "r" (ldc));
  asm volatile ("vmacc.vx v12, %0, v20" :: "r" (t3));
  asm volatile ("vse64.v v12, (%0);"               : "+r" (c)            );
}
