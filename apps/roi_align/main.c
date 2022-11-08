/*
    Original implementation taken from
    https://github.com/longcw/RoIAlign.pytorch No license found on the website.
    A question about the license was made here
    https://github.com/longcw/RoIAlign.pytorch/issues/48 Following the answer to
    this question, a correct header will be added also here
    Adaptation by: Matteo Perotti, ETH Zurich, <mperotti@iis.ee.ethz.ch>
*/

#include <stdint.h>
#include <string.h>

#include "runtime.h"

#include "kernel/roi_align.h"

#ifndef SPIKE
#include "printf.h"
#else
#include <stdio.h>
#endif

#define EXTRAPOLATION_VALUE 0

extern uint64_t BATCH_SIZE;
extern uint64_t DEPTH;
extern uint64_t IMAGE_HEIGHT;
extern uint64_t IMAGE_WIDTH;
extern uint64_t N_BOXES;
extern uint64_t CROP_HEIGHT;
extern uint64_t CROP_WIDTH;

extern float image_data[];
extern float boxes_data[];
extern int box_index_data[];
extern float crops_data[];
extern float crops_data_vec[];

// Compare the vector and scalar implementation.
// Return 0 if no error is found
// Return -1 if we have an error on the first element
// A positive return value indicates the index of the faulty element
int verify_result(float *s_crops_data, float *v_crops_data, size_t size,
                  float delta) {
  int ret;

  for (unsigned long int i = 0; i < size; ++i) {
    if (!similarity_check_32b(s_crops_data[i], v_crops_data[i], delta)) {
      ret = (!i) ? -1 : i;
      return ret;
    }
  }

  return 0;
}

int main() {
  printf("\n");
  printf("===============\n");
  printf("=  RoI Align  =\n");
  printf("===============\n");
  printf("\n");
  printf("\n");

  int64_t err;
  int64_t runtime_s, runtime_v;
  uint64_t result_size = N_BOXES * DEPTH * CROP_HEIGHT * CROP_WIDTH;

  /*
    Initialize Matrices
    printf("Initializing matrices...\n");
    init_image(image_data, BATCH_SIZE * DEPTH * IMAGE_HEIGHT * IMAGE_WIDTH);
    init_boxes(boxes_data, 4 * N_BOXES);
    init_boxes_idx(box_index_data, N_BOXES, BATCH_SIZE);
    Crops are already at zero
    init_crops(crops_data, BATCH_SIZE * DEPTH * CROP_HEIGHT * CROP_WIDTH);
    init_crops(crops_data_vec, BATCH_SIZE * DEPTH * CROP_HEIGHT * CROP_WIDTH);
  */

  // Parameters
  printf("BATCH_SIZE = %ld\nDEPTH = %ld\nIMAGE_HEIGHT = %ld\nIMAGE_WIDTH = "
         "%ld\nN_BOXES = %ld\nCROP_HEIGHT = %ld\nCROP_WIDTH = "
         "%ld\nEXTRAPOLATION_VALUE = %ld\n",
         BATCH_SIZE, DEPTH, IMAGE_HEIGHT, IMAGE_WIDTH, N_BOXES, CROP_HEIGHT,
         CROP_WIDTH, EXTRAPOLATION_VALUE);

  // Scalar benchmark
  printf("Starting scalar benchmark...\n");
  start_timer();
  CropAndResizePerBox(image_data, BATCH_SIZE, DEPTH, IMAGE_HEIGHT, IMAGE_WIDTH,
                      boxes_data, box_index_data, 0, N_BOXES, crops_data,
                      CROP_HEIGHT, CROP_WIDTH, EXTRAPOLATION_VALUE);
  stop_timer();
  runtime_s = get_timer();
  printf("Scalar benchmark complete.\n");
  printf("Cycles: %d\n", runtime_s);

  // Vector benchmark
  printf("Starting vector benchmark...\n");
  start_timer();
  CropAndResizePerBox_BCHW_vec(image_data, BATCH_SIZE, DEPTH, IMAGE_HEIGHT,
                               IMAGE_WIDTH, boxes_data, box_index_data, 0,
                               N_BOXES, crops_data_vec, CROP_HEIGHT, CROP_WIDTH,
                               EXTRAPOLATION_VALUE);
  stop_timer();
  runtime_v = get_timer();
  printf("Vector benchmark complete.\n");

  printf("The execution took %d cycles.\n", runtime_v);
  printf("Vector speedup is %f times over the scalar implementation.\n",
         (float)runtime_s / runtime_v);

  // Check for errors
  err = verify_result(crops_data, crops_data_vec, result_size, DELTA);

  if (err != 0) {
    // Fix return code to match the index of the faulty element
    err = (err == -1) ? 0 : err;
    printf("Failed. Index %d: %x != %x\n", err, *((uint32_t *)&crops_data[err]),
           *((uint32_t *)&crops_data_vec[err]));
    return err;
  } else {
    printf("Passed.\n");
  }

  return 0;
}
