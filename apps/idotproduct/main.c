// Copyright 2020 ETH Zurich and University of Bologna.
//
// SPDX-License-Identifier: Apache-2.0
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>

#include <stdint.h>
#include <string.h>

#include "printf.h"
#include "runtime.h"

// Keep vector 512 B long, to fit a vreg when LMUL == 8
#define SIZE_8B 4096
#define SIZE_16B 2048
#define SIZE_32B 1024
#define SIZE_64B 512

#define SCALAR 1
#define CHECK 0

void dotp_64b(uint64_t avl, int64_t *v0, int64_t *v1, int64_t *result);
void dotp_64b_scalar(uint64_t avl, int64_t *v0, int64_t *v1, int64_t *result);
void dotp_32b(uint64_t avl, int32_t *v0, int32_t *v1, int32_t *result);
void dotp_32b_scalar(uint64_t avl, int32_t *v0, int32_t *v1, int32_t *result);
void dotp_16b(uint64_t avl, int16_t *v0, int16_t *v1, int16_t *result);
void dotp_16b_scalar(uint64_t avl, int16_t *v0, int16_t *v1, int16_t *result);
void dotp_8b(uint64_t avl, int8_t *v0, int8_t *v1, int8_t *result);
void dotp_8b_scalar(uint64_t avl, int8_t *v0, int8_t *v1, int8_t *result);

// Vectors for benchmarks
int64_t v64a[SIZE_64B] __attribute__((aligned(32 * NR_LANES), section(".l2")));
int64_t v64b[SIZE_64B] __attribute__((aligned(32 * NR_LANES), section(".l2")));
int32_t v32a[SIZE_32B] __attribute__((aligned(32 * NR_LANES), section(".l2")));
int32_t v32b[SIZE_32B] __attribute__((aligned(32 * NR_LANES), section(".l2")));
int16_t v16a[SIZE_16B] __attribute__((aligned(32 * NR_LANES), section(".l2")));
int16_t v16b[SIZE_16B] __attribute__((aligned(32 * NR_LANES), section(".l2")));
int8_t v8a[SIZE_8B] __attribute__((aligned(32 * NR_LANES), section(".l2")));
int8_t v8b[SIZE_8B] __attribute__((aligned(32 * NR_LANES), section(".l2")));

int64_t v_result64, s_result64;
int32_t v_result32, s_result32;
int16_t v_result16, s_result16;
int8_t v_result8, s_result8;

int main() {
  printf("\n");
  printf("==========\n");
  printf("=  DOTP  =\n");
  printf("==========\n");
  printf("\n");
  printf("\n");

  int64_t runtime_s, runtime_v;

  for (uint64_t avl = 8; avl <= SIZE_64B; avl *= 8) {
    // Dotp
    printf("Calulating 64b dotp with vectors with length = %lu\n", avl);
    dotp_64b(avl, v64a, v64b, &v_result64);
    runtime_v = get_timer();
    printf("Vector runtime: %ld\n", runtime_v);

    if (SCALAR) {
      dotp_64b_scalar(avl, v64a, v64b, &s_result64);
      runtime_s = get_timer();
      printf("Scalar runtime: %ld\n", runtime_s);

      if (CHECK) {
        if (v_result64 != s_result64)
          return -1;
      }
    }
  }

  for (uint64_t avl = 16; avl <= SIZE_32B; avl *= 8) {
    // Dotp
    printf("Calulating 32b dotp with vectors with length = %lu\n", avl);
    dotp_32b(avl, v32a, v32b, &v_result32);
    runtime_v = get_timer();
    printf("Vector runtime: %ld\n", runtime_v);

    if (SCALAR) {
      dotp_32b_scalar(avl, v32a, v32b, &s_result32);
      runtime_s = get_timer();
      printf("Scalar runtime: %ld\n", runtime_s);

      if (CHECK) {
        if (v_result32 != s_result32)
          return -1;
      }
    }
  }

  for (uint64_t avl = 32; avl <= SIZE_16B; avl *= 8) {
    // Dotp
    printf("Calulating 16b dotp with vectors with length = %lu\n", avl);
    dotp_16b(avl, v16a, v16b, &v_result16);
    runtime_v = get_timer();
    printf("Vector runtime: %ld\n", runtime_v);

    if (SCALAR) {
      dotp_16b_scalar(avl, v16a, v16b, &s_result16);
      runtime_s = get_timer();
      printf("Scalar runtime: %ld\n", runtime_s);

      if (CHECK) {
        if (v_result16 != s_result16)
          return -1;
      }
    }
  }

  for (uint64_t avl = 64; avl <= SIZE_8B; avl *= 8) {
    // Dotp
    printf("Calulating 8b dotp with vectors with length = %lu\n", avl);
    dotp_8b(avl, v8a, v8b, &v_result8);
    runtime_v = get_timer();
    printf("Vector runtime: %ld\n", runtime_v);

    if (SCALAR) {
      dotp_8b_scalar(avl, v8a, v8b, &s_result8);
      runtime_s = get_timer();
      printf("Scalar runtime: %ld\n", runtime_s);

      if (CHECK) {
        if (v_result8 != s_result8)
          return -1;
      }
    }
  }

  printf("SUCCESS.\n");

  return 0;
}

void dotp_64b(uint64_t avl, int64_t *v0, int64_t *v1, int64_t *result) {
  uint64_t vl;
  volatile uint64_t tmp;

  uint64_t zero = 0;

  asm volatile("vsetvli %0, %1, e64, m8, ta, ma" : "=r"(tmp) : "r"(1));
  // Load the 0 scalar value for reduction, but also reshuffle all the regs
  asm volatile("vle64.v v0, (%0);" ::"r"(&zero));
  asm volatile("vle64.v v8, (%0);" ::"r"(&zero));
  asm volatile("vle64.v v16, (%0);" ::"r"(&zero));
  asm volatile("vle64.v v24, (%0);" ::"r"(&zero));
  asm volatile("vsetvli %0, %1, e64, m8, ta, ma" : "=r"(vl) : "r"(avl));
  asm volatile("vle64.v v8, (%0);" ::"r"(v0));
  asm volatile("vle64.v v0, (%0);" ::"r"(v1));

  // Force the load to be over
  *(&tmp) = 0;

  start_timer();
  asm volatile("vmul.vv v24, v8, v0");
  asm volatile("vredsum.vs v16, v24, v16");
  asm volatile("vsetvli %0, %1, e64, m8, ta, ma" : "=r"(tmp) : "r"(1));
  // Store the reduced value to have a memory barrier and read the actual
  // runtime
  asm volatile("vse64.v v16, (%0);" ::"r"(result));
  stop_timer();
}

void dotp_64b_scalar(uint64_t avl, int64_t *v0, int64_t *v1, int64_t *result) {
  int64_t acc0, acc1, acc2, acc3, acc4, acc5, acc6, acc7;

  acc0 = 0;
  acc1 = 0;
  acc2 = 0;
  acc3 = 0;
  acc4 = 0;
  acc5 = 0;
  acc6 = 0;
  acc7 = 0;
  // Start timer
  start_timer();
  for (uint64_t i = 0; i < avl; i += 8) {
    acc0 += v0[i + 0] * v1[i + 0];
    acc1 += v0[i + 1] * v1[i + 1];
    acc2 += v0[i + 2] * v1[i + 2];
    acc3 += v0[i + 3] * v1[i + 3];
    acc4 += v0[i + 4] * v1[i + 4];
    acc5 += v0[i + 5] * v1[i + 5];
    acc6 += v0[i + 6] * v1[i + 6];
    acc7 += v0[i + 7] * v1[i + 7];
  }

  acc0 += acc1;
  acc2 += acc3;
  acc4 += acc5;
  acc6 += acc7;

  acc0 += acc2;
  acc4 += acc6;

  acc0 += acc4;
  // Stop timer
  stop_timer();

  *result = acc0;
}

void dotp_32b(uint64_t avl, int32_t *v0, int32_t *v1, int32_t *result) {
  uint64_t vl;
  volatile uint64_t tmp;

  uint32_t zero = 0;

  asm volatile("vsetvli %0, %1, e32, m8, ta, ma" : "=r"(tmp) : "r"(1));
  asm volatile("vle32.v v0, (%0);" ::"r"(&zero));
  asm volatile("vle32.v v8, (%0);" ::"r"(&zero));
  asm volatile("vle32.v v16, (%0);" ::"r"(&zero));
  asm volatile("vle32.v v24, (%0);" ::"r"(&zero));
  asm volatile("vsetvli %0, %1, e32, m8, ta, ma" : "=r"(vl) : "r"(avl));
  asm volatile("vle32.v v8, (%0);" ::"r"(v0));
  asm volatile("vle32.v v0, (%0);" ::"r"(v1));

  // Force the load to be over
  *(&tmp) = 0;

  start_timer();
  asm volatile("vmul.vv v24, v8, v0");
  asm volatile("vredsum.vs v16, v24, v16");
  asm volatile("vsetvli %0, %1, e32, m8, ta, ma" : "=r"(tmp) : "r"(1));
  // Store the reduced value to have a memory barrier and read the actual
  // runtime
  asm volatile("vse32.v v16, (%0);" ::"r"(result));
  stop_timer();
}

void dotp_32b_scalar(uint64_t avl, int32_t *v0, int32_t *v1, int32_t *result) {
  int32_t acc0, acc1, acc2, acc3, acc4, acc5, acc6, acc7;

  acc0 = 0;
  acc1 = 0;
  acc2 = 0;
  acc3 = 0;
  acc4 = 0;
  acc5 = 0;
  acc6 = 0;
  acc7 = 0;
  // Start timer
  start_timer();
  for (uint64_t i = 0; i < avl; i += 8) {
    acc0 += v0[i + 0] * v1[i + 0];
    acc1 += v0[i + 1] * v1[i + 1];
    acc2 += v0[i + 2] * v1[i + 2];
    acc3 += v0[i + 3] * v1[i + 3];
    acc4 += v0[i + 4] * v1[i + 4];
    acc5 += v0[i + 5] * v1[i + 5];
    acc6 += v0[i + 6] * v1[i + 6];
    acc7 += v0[i + 7] * v1[i + 7];
  }

  acc0 += acc1;
  acc2 += acc3;
  acc4 += acc5;
  acc6 += acc7;

  acc0 += acc2;
  acc4 += acc6;

  acc0 += acc4;
  // Stop timer
  stop_timer();

  *result = acc0;
}

void dotp_16b(uint64_t avl, int16_t *v0, int16_t *v1, int16_t *result) {
  uint64_t vl;
  volatile uint64_t tmp;

  uint16_t zero = 0;

  asm volatile("vsetvli %0, %1, e16, m8, ta, ma" : "=r"(tmp) : "r"(1));
  asm volatile("vle16.v v0, (%0);" ::"r"(&zero));
  asm volatile("vle16.v v8, (%0);" ::"r"(&zero));
  asm volatile("vle16.v v16, (%0);" ::"r"(&zero));
  asm volatile("vle16.v v24, (%0);" ::"r"(&zero));
  asm volatile("vsetvli %0, %1, e16, m8, ta, ma" : "=r"(vl) : "r"(avl));
  asm volatile("vle16.v v8, (%0);" ::"r"(v0));
  asm volatile("vle16.v v0, (%0);" ::"r"(v1));

  // Force the load to be over
  *(&tmp) = 0;

  start_timer();
  asm volatile("vmul.vv v24, v8, v0");
  asm volatile("vredsum.vs v16, v24, v16");
  asm volatile("vsetvli %0, %1, e16, m8, ta, ma" : "=r"(tmp) : "r"(1));
  // Store the reduced value to have a memory barrier and read the actual
  // runtime
  asm volatile("vse16.v v16, (%0);" ::"r"(result));
  stop_timer();
}

void dotp_16b_scalar(uint64_t avl, int16_t *v0, int16_t *v1, int16_t *result) {
  int16_t acc0, acc1, acc2, acc3, acc4, acc5, acc6, acc7;

  acc0 = 0;
  acc1 = 0;
  acc2 = 0;
  acc3 = 0;
  acc4 = 0;
  acc5 = 0;
  acc6 = 0;
  acc7 = 0;
  // Start timer
  start_timer();
  for (uint64_t i = 0; i < avl; i += 8) {
    acc0 += v0[i + 0] * v1[i + 0];
    acc1 += v0[i + 1] * v1[i + 1];
    acc2 += v0[i + 2] * v1[i + 2];
    acc3 += v0[i + 3] * v1[i + 3];
    acc4 += v0[i + 4] * v1[i + 4];
    acc5 += v0[i + 5] * v1[i + 5];
    acc6 += v0[i + 6] * v1[i + 6];
    acc7 += v0[i + 7] * v1[i + 7];
  }

  acc0 += acc1;
  acc2 += acc3;
  acc4 += acc5;
  acc6 += acc7;

  acc0 += acc2;
  acc4 += acc6;

  acc0 += acc4;
  // Stop timer
  stop_timer();

  *result = acc0;
}

void dotp_8b(uint64_t avl, int8_t *v0, int8_t *v1, int8_t *result) {
  uint64_t vl;
  volatile uint64_t tmp;

  uint8_t zero = 0;

  asm volatile("vsetvli %0, %1, e8, m8, ta, ma" : "=r"(tmp) : "r"(1));
  asm volatile("vle8.v v0, (%0);" ::"r"(&zero));
  asm volatile("vle8.v v8, (%0);" ::"r"(&zero));
  asm volatile("vle8.v v16, (%0);" ::"r"(&zero));
  asm volatile("vle8.v v24, (%0);" ::"r"(&zero));
  asm volatile("vsetvli %0, %1, e8, m8, ta, ma" : "=r"(vl) : "r"(avl));
  asm volatile("vle8.v v8, (%0);" ::"r"(v0));
  asm volatile("vle8.v v0, (%0);" ::"r"(v1));

  // Force the load to be over
  *(&tmp) = 0;

  start_timer();
  asm volatile("vmul.vv v24, v8, v0");
  asm volatile("vredsum.vs v8, v24, v8");
  asm volatile("vsetvli %0, %1, e8, m8, ta, ma" : "=r"(tmp) : "r"(1));
  // Store the reduced value to have a memory barrier and read the actual
  // runtime
  asm volatile("vse8.v v8, (%0);" ::"r"(result));
  stop_timer();
}

void dotp_8b_scalar(uint64_t avl, int8_t *v0, int8_t *v1, int8_t *result) {
  int8_t acc0, acc1, acc2, acc3, acc4, acc5, acc6, acc7;

  acc0 = 0;
  acc1 = 0;
  acc2 = 0;
  acc3 = 0;
  acc4 = 0;
  acc5 = 0;
  acc6 = 0;
  acc7 = 0;
  // Start timer
  start_timer();
  for (uint64_t i = 0; i < avl; i += 8) {
    acc0 += v0[i + 0] * v1[i + 0];
    acc1 += v0[i + 1] * v1[i + 1];
    acc2 += v0[i + 2] * v1[i + 2];
    acc3 += v0[i + 3] * v1[i + 3];
    acc4 += v0[i + 4] * v1[i + 4];
    acc5 += v0[i + 5] * v1[i + 5];
    acc6 += v0[i + 6] * v1[i + 6];
    acc7 += v0[i + 7] * v1[i + 7];
  }

  acc0 += acc1;
  acc2 += acc3;
  acc4 += acc5;
  acc6 += acc7;

  acc0 += acc2;
  acc4 += acc6;

  acc0 += acc4;
  // Stop timer
  stop_timer();

  *result = acc0;
}
