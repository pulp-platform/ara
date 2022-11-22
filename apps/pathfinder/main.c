// Modified version of pathfinder from RODINIA and then RiVEC, adapted to Ara
// environment. Author: Matteo Perotti <mperotti@iis.ee.ethz.ch> Check LICENSE_0
// and LICENCE_1 for additional information

/*************************************************************************
 * RISC-V Vectorized Version
 * Author: Cristóbal Ramírez Lazo
 * email: cristobal.ramirez@bsc.es
 * Barcelona Supercomputing Center (2020)
 *************************************************************************/

#include <stdint.h>
#include <string.h>

#include "runtime.h"

#include "kernel/pathfinder.h"

#ifndef SPIKE
#include "printf.h"
#else
#include <stdio.h>
#endif

#define CHECK

extern int32_t num_runs;
extern int32_t rows;
extern int32_t cols;
extern int src[] __attribute__((aligned(4 * NR_LANES), section(".l2")));
extern int wall[] __attribute__((aligned(4 * NR_LANES), section(".l2")));
extern int result_v[] __attribute__((aligned(4 * NR_LANES), section(".l2")));
extern int result_s[] __attribute__((aligned(4 * NR_LANES), section(".l2")));

int verify_result(int *result_s, int *result_v, uint32_t cols) {
  // Check vector with scalar result
  for (uint32_t i = 0; i < cols; i++) {
    if (result_v[i] != result_s[i]) {
      printf("Error. result_v[%d]=%d != result_s[%d]=%d \n", i, result_v[i], i,
             result_s[i]);
      return 1;
    }
  }

  printf("Test result: PASS. No errors found.\n");

  return 0;
}

int main() {
  printf("\n");
  printf("================\n");
  printf("=  PATHFINDER  =\n");
  printf("================\n");
  printf("\n");
  printf("\n");

  int error;
  int *s_ptr;

  printf("Number of runs: %d\n", num_runs);

#ifdef CHECK
  start_timer();
  s_ptr = run(wall, result_s, src, cols, rows, num_runs);
  stop_timer();
  printf("Scalar code cycles: %d\n", get_timer());
#endif

  if (cols > NR_LANES * 128) {
    printf("Using the base algorithm.\n");
    start_timer();
    run_vector(wall, result_v, cols, rows, num_runs);
    stop_timer();
  } else {
    printf("Using the optimized algorithm.\n");
    int neutral_value = 0x7fffffff; // Max value for int datatype
    start_timer();
    run_vector_short_m4(wall, result_v, cols, rows, num_runs, neutral_value);
    stop_timer();
  }
  printf("Vector code cycles: %d\n", get_timer());

#ifdef CHECK
  error = verify_result(s_ptr, result_v, cols);
#else
  error = 0;
#endif

  return error;
}
