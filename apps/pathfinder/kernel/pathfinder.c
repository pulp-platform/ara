// Modified version of pathfinder from RODINIA and then RiVEC, adapted to Ara
// environment. Author: Matteo Perotti <mperotti@iis.ee.ethz.ch> Check LICENSE_0
// and LICENCE_1 for additional information

/*************************************************************************
 * RISC-V Vectorized Version
 * Author: Cristóbal Ramírez Lazo
 * email: cristobal.ramirez@bsc.es
 * Barcelona Supercomputing Center (2020)
 *************************************************************************/

#include "pathfinder.h"

int *run(int *wall, int *result_s, int *src, uint32_t cols, uint32_t rows,
         uint32_t num_runs) {
  int min;
  int *temp;
  int *dst;

  for (uint32_t j = 0; j < num_runs; j++) {
    for (uint32_t x = 0; x < cols; x++) {
      result_s[x] = wall[x];
    }

    dst = result_s;

    for (uint32_t t = 0; t < rows - 1; t++) {
      temp = src;
      src = dst;
      dst = temp;
      for (uint32_t n = 0; n < cols; n++) {
        min = src[n];
        if (n > 0)
          min = MIN(min, src[n - 1]);
        if (n < cols - 1)
          min = MIN(min, src[n + 1]);
        dst[n] = wall[(t + 1) * cols + n] + min;
      }
    }
    // Reset the pointer not to lose it
    src = temp;
  }
  return dst;
}

void run_vector(int *wall, int *result_v, uint32_t cols, uint32_t rows,
                uint32_t num_runs) {

  size_t gvl;

  vint32m1_t temp;
  vint32m1_t xSrc_slideup;
  vint32m1_t xSrc_slidedown;
  vint32m1_t xSrc;
  vint32m1_t xNextrow;

  int aux, aux2;
  int *dst;

  for (uint32_t j = 0; j < num_runs; j++) {
    for (uint32_t n = 0; n < cols; n += gvl) {
      gvl = vsetvl_e32m1(cols);
      temp = vle32_v_i32m1(&wall[n], gvl);
      vse32_v_i32m1(&result_v[n], temp, gvl);
    }
    dst = result_v;

    gvl = vsetvl_e32m1(cols);

    for (uint32_t t = 0; t < rows - 1; t++) {
      aux = dst[0];
      for (uint32_t n = 0; n < cols; n = n + gvl) {
        gvl = vsetvl_e32m1(cols - n);
        xNextrow = vle32_v_i32m1(&dst[n], gvl);

        xSrc = xNextrow;
        aux2 = (n + gvl >= cols) ? dst[n + gvl - 1] : dst[n + gvl];
        xSrc_slideup = vslide1up_vx_i32m1(xSrc, aux, gvl);
        xSrc_slidedown = vslide1down_vx_i32m1(xSrc, aux2, gvl);

        xSrc = vmin_vv_i32m1(xSrc, xSrc_slideup, gvl);
        xSrc = vmin_vv_i32m1(xSrc, xSrc_slidedown, gvl);

        xNextrow = vle32_v_i32m1(&wall[(t + 1) * cols + n], gvl);
        xNextrow = vadd_vv_i32m1(xNextrow, xSrc, gvl);

        aux = dst[n + gvl - 1];
        vse32_v_i32m1(&dst[n], xNextrow, gvl);
      }
    }
  }
}

// This function is optimized for program sizes that satisfy:
// cols < (m * L * 128) / (2**sew)
// With m4, int32_t, 8 lanes -> cols < (4 * 8 * 128) / (4) -> cols <= 1024
// With m4, int32_t, 4 lanes -> cols < (4 * 4 * 128) / (4) -> cols <= 512
// Introduced preloading to boost performance
void run_vector_short_m4(int *wall, int *result_v, uint32_t cols, uint32_t rows,
                         uint32_t num_runs, int neutral_value) {

  size_t gvl;

  vint32m4_t temp;
  vint32m4_t xSrc_slideup;
  vint32m4_t xSrc_slidedown;
  vint32m4_t xSrc;
  vint32m4_t xNextrow, xNextNextrow;

  int aux, aux2;
  aux = neutral_value;
  aux2 = neutral_value;

  gvl = vsetvl_e32m4(cols);

  for (uint32_t j = 0; j < num_runs; j++) {

    asm volatile("vle32.v v16, (%0)" ::"r"(wall)); // xNextNextrow

    uint32_t t;
    for (t = 0; t < rows - 1; t += 3) {
      // Iteration 1
      asm volatile("vslide1up.vx v12, v16, %0" ::"r"(
          aux)); // xSrc_slideup   <- xNextNextrow
      asm volatile("vslide1down.vx v24, v16, %0" ::"r"(
          aux2)); // xSrc_slidedown <- xNextNextrow

      // Preload for iteration 2
      asm volatile("vle32.v v0, (%0)" ::"r"(&wall[(t + 1) * cols])); // xNextrow

      asm volatile(
          "vmin.vv v28, v16, v12"); // acc <- xNextNextrow, xSrc_slideup
      asm volatile("vmin.vv v28, v28, v24"); // acc <- acc, xSrc_slidedown

      // Preload for iteration 3
      if (t + 1 < rows - 1)
        asm volatile(
            "vle32.v v4, (%0)" ::"r"(&wall[(t + 2) * cols])); // xNextNextrow

      asm volatile("vadd.vv v0, v0, v28"); // xNextNextrow

      // Iteration 2
      if (t + 1 < rows - 1) {
        asm volatile("vslide1up.vx v8, v0, %0" ::"r"(
            aux)); // xSrc_slideup   <- xNextNextrow
        asm volatile("vslide1down.vx v12, v0, %0" ::"r"(
            aux2)); // xSrc_slidedown <- xNextNextrow

        // Preload for iteration 1
        if (t + 2 < rows - 1)
          asm volatile(
              "vle32.v v16, (%0)" ::"r"(&wall[(t + 3) * cols])); // xNextNextrow

        asm volatile("vmin.vv v28, v0, v8");   // acc <- xNextrow, xSrc_slideup
        asm volatile("vmin.vv v28, v28, v12"); // acc <- acc, xSrc_slidedown

        asm volatile("vadd.vv v4, v4, v28"); // xNextNextrow

        // Iteration 3
        if (t + 2 < rows - 1) {
          asm volatile("vslide1up.vx v20, v4, %0" ::"r"(
              aux)); // xSrc_slideup   <- xNextNextrow
          asm volatile("vslide1down.vx v8, v4, %0" ::"r"(
              aux2)); // xSrc_slidedown <- xNextNextrow

          asm volatile("vmin.vv v28, v4, v20"); // acc <- xNextrow, xSrc_slideup
          asm volatile("vmin.vv v28, v28, v8"); // acc <- acc, xSrc_slidedown

          asm volatile("vadd.vv v16, v16, v28"); // xNextNextrow
        }
      }
      if (t - 2 >= rows - 1)
        asm volatile("vse32.v v0, (%0)" ::"r"(result_v)); // xNextNextrow
      else if (t - 1 < rows - 1)
        asm volatile("vse32.v v16, (%0)" ::"r"(result_v)); // xNextNextrow
      else
        asm volatile("vse32.v v4, (%0)" ::"r"(result_v)); // xNextNextrow
    }
  }
}

/*
// This function is optimized for program sizes that satisfy:
// cols < (m * L * 128) / (2**sew)
// With m4, int32_t, 8 lanes -> cols < (4 * 8 * 128) / (4) -> cols <= 1024
// With m4, int32_t, 4 lanes -> cols < (4 * 4 * 128) / (4) -> cols <= 512
void run_vector_short_m4(int *wall, int *result_v, uint32_t cols, uint32_t rows,
                         uint32_t num_runs, int neutral_value) {

  size_t gvl;

  vint32m4_t temp;
  vint32m4_t xSrc_slideup;
  vint32m4_t xSrc_slidedown;
  vint32m4_t xSrc;
  vint32m4_t xNextrow;

  int aux, aux2;

  gvl = vsetvl_e32m4(cols);

  for (uint32_t j = 0; j < num_runs; j++) {

    xNextrow = vle32_v_i32m4(wall, gvl);

    for (uint32_t t = 0; t < rows - 1; t++) {
      aux = neutral_value;

      xSrc = xNextrow;
      aux2 = neutral_value;
      xSrc_slideup = vslide1up_vx_i32m4(xSrc, aux, gvl);
      xSrc_slidedown = vslide1down_vx_i32m4(xSrc, aux2, gvl);

      xSrc = vmin_vv_i32m4(xSrc, xSrc_slideup, gvl);
      xSrc = vmin_vv_i32m4(xSrc, xSrc_slidedown, gvl);

      xNextrow = vle32_v_i32m4(&wall[(t + 1) * cols], gvl);
      xNextrow = vadd_vv_i32m4(xNextrow, xSrc, gvl);
    }
    // Write the result
    vse32_v_i32m4(result_v, xNextrow, gvl);
  }
}
*/
