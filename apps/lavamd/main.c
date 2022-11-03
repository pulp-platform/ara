
#include "kernel/lavamd.h"
#include "runtime.h"
#include "util.h"

#ifndef SPIKE
#include "printf.h"
#else
#include <stdio.h>
#endif

extern fp alpha;
extern uint64_t n_boxes;
extern uint64_t NUMBER_PAR_PER_BOX;

extern box_str box_cpu_mem[]
    __attribute__((aligned(4 * NR_LANES), section(".l2")));
extern FOUR_VECTOR rv_cpu_mem[]
    __attribute__((aligned(4 * NR_LANES), section(".l2")));
extern fp qv_cpu_mem[] __attribute__((aligned(4 * NR_LANES), section(".l2")));
extern FOUR_VECTOR fv_s_cpu_mem[]
    __attribute__((aligned(4 * NR_LANES), section(".l2")));
extern FOUR_VECTOR fv_v_cpu_mem[]
    __attribute__((aligned(4 * NR_LANES), section(".l2")));
extern nei_str nn_mem[] __attribute__((aligned(4 * NR_LANES), section(".l2")));

int main() {

  printf("\n");
  printf("=============\n");
  printf("=  LAVA-MD  =\n");
  printf("=============\n");
  printf("\n");
  printf("\n");

  int err = 0;

  printf("n_boxes = %u, NUMBER_PAR_PER_BOX = %u\n", n_boxes,
         NUMBER_PAR_PER_BOX);

  printf("sizeof(box_cpu_mem[0]) = %u\n", sizeof(box_cpu_mem[0]));

  for (uint64_t i = 0; i < n_boxes; i++) {
    printf("box_cpu_mem[%d].offset = %u, while .number == %u\n", i,
           box_cpu_mem[i].offset, box_cpu_mem[i].number);
  }

  printf("Running the scalar benchmark.\n");
  kernel(alpha, n_boxes, box_cpu_mem, rv_cpu_mem, qv_cpu_mem, fv_s_cpu_mem,
         NUMBER_PAR_PER_BOX);

  printf("Pre vec kernel s == %x,  v == %x\n",
         *((uint32_t *)&(fv_s_cpu_mem[0].v)),
         *((uint32_t *)&(fv_v_cpu_mem[0].v)));

  printf("Running the vector benchmark.\n");
  kernel_vec(alpha, n_boxes, box_cpu_mem, rv_cpu_mem, qv_cpu_mem, fv_v_cpu_mem,
             NUMBER_PAR_PER_BOX);

  printf("s == %x,  v == %x\n", *((uint32_t *)&(fv_s_cpu_mem[0].v)),
         *((uint32_t *)&(fv_v_cpu_mem[0].v)));

  // Check
  for (uint64_t i = 0; i < n_boxes; ++i) {
    if (!similarity_check_32b(fv_s_cpu_mem[i].v, fv_v_cpu_mem[i].v,
                              THRESHOLD) ||
        !similarity_check_32b(fv_s_cpu_mem[i].x, fv_v_cpu_mem[i].x,
                              THRESHOLD) ||
        !similarity_check_32b(fv_s_cpu_mem[i].y, fv_v_cpu_mem[i].y,
                              THRESHOLD) ||
        !similarity_check_32b(fv_s_cpu_mem[i].z, fv_v_cpu_mem[i].z,
                              THRESHOLD)) {
      printf("Error at index %lu. s: %f != v: %f \n", i, fv_s_cpu_mem[i],
             fv_v_cpu_mem[i]);
      err = i ? i : -1;
    }
  }
  if (!err)
    printf("Test passed. No errors found.\n");

  return err;
}
