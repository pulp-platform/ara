/*
    Original implementation taken from
    https://github.com/longcw/RoIAlign.pytorch No license found on the website.
    A question about the license was made here
   https://github.com/longcw/RoIAlign.pytorch/issues/48 Following the answer to
   this question, a correct header will be added also here Adaptation by: Matteo
   Perotti, ETH Zurich, <mperotti@iis.ee.ethz.ch>
*/

#include <math.h>
#include <stdint.h>
#include <string.h>

#include "printf.h"
#include "runtime.h"

#include "riscv_vector.h"

#define BATCH_SIZE 16
#define DEPTH 100
#define IMAGE_HEIGHT 64
#define IMAGE_WIDTH 64
#define N_BOXES 6
#define CROP_HEIGHT 3
#define CROP_WIDTH 3
#define EXTRAPOLATION_VALUE 0

const float image_data[BATCH_SIZE * DEPTH * IMAGE_HEIGHT * IMAGE_WIDTH];
const float boxes_data[4 * N_BOXES];
int box_index_data[N_BOXES];
float crops_data[BATCH_SIZE * DEPTH * CROP_HEIGHT * CROP_WIDTH];
float crops_data_vec[BATCH_SIZE * DEPTH * CROP_HEIGHT * CROP_WIDTH];

int64_t CropAndResizePerBox(const float *image_data, const int batch_size,
                            const int depth, const int image_height,
                            const int image_width,

                            const float *boxes_data, const int *box_index_data,
                            const int start_box, const int limit_box,

                            float *crops_data, const int crop_height,
                            const int crop_width,
                            const float extrapolation_value) {
  // Measure performance of the kernel
  int64_t runtime = 0;

  const int image_channel_elements = image_height * image_width;
  const int image_elements = depth * image_channel_elements;

  const int channel_elements = crop_height * crop_width;
  const int crop_elements = depth * channel_elements;

  int b;
#pragma omp parallel for
  for (b = start_box; b < limit_box; ++b) {
    const float *box = boxes_data + b * 4;
    const float y1 = box[0];
    const float x1 = box[1];
    const float y2 = box[2];
    const float x2 = box[3];

    const int b_in = box_index_data[b];
    if (b_in < 0 || b_in >= batch_size) {
      printf("Error: batch_index %d out of range [0, %d)\n", b_in, batch_size);
      return -1;
    }

    const float height_scale =
        (crop_height > 1) ? (y2 - y1) * (image_height - 1) / (crop_height - 1)
                          : 0;
    const float width_scale =
        (crop_width > 1) ? (x2 - x1) * (image_width - 1) / (crop_width - 1) : 0;

    for (int y = 0; y < crop_height; ++y) {
      const float in_y = (crop_height > 1)
                             ? y1 * (image_height - 1) + y * height_scale
                             : 0.5 * (y1 + y2) * (image_height - 1);

      if (in_y < 0 || in_y > image_height - 1) {
        for (int x = 0; x < crop_width; ++x) {
          for (int d = 0; d < depth; ++d) {
            // crops(b, y, x, d) = extrapolation_value;
            crops_data[crop_elements * b + channel_elements * d +
                       y * crop_width + x] = extrapolation_value;
          }
        }
        continue;
      }

      const int top_y_index = floorf(in_y);
      const int bottom_y_index = ceilf(in_y);
      const float y_lerp = in_y - top_y_index;

      for (int x = 0; x < crop_width; ++x) {
        const float in_x = (crop_width > 1)
                               ? x1 * (image_width - 1) + x * width_scale
                               : 0.5 * (x1 + x2) * (image_width - 1);
        if (in_x < 0 || in_x > image_width - 1) {
          for (int d = 0; d < depth; ++d) {
            crops_data[crop_elements * b + channel_elements * d +
                       y * crop_width + x] = extrapolation_value;
          }
          continue;
        }

        const int left_x_index = floorf(in_x);
        const int right_x_index = ceilf(in_x);
        const float x_lerp = in_x - left_x_index;

        for (int d = 0; d < depth; ++d) {
          const float *pimage =
              image_data + b_in * image_elements + d * image_channel_elements;

          const float top_left =
              pimage[top_y_index * image_width + left_x_index];
          const float top_right =
              pimage[top_y_index * image_width + right_x_index];
          const float bottom_left =
              pimage[bottom_y_index * image_width + left_x_index];
          const float bottom_right =
              pimage[bottom_y_index * image_width + right_x_index];

          const float top = top_left + (top_right - top_left) * x_lerp;
          const float bottom =
              bottom_left + (bottom_right - bottom_left) * x_lerp;

          crops_data[crop_elements * b + channel_elements * d + y * crop_width +
                     x] = top + (bottom - top) * y_lerp;
        }
      } // end for x
    }   // end for y
  }     // end for b
  return 0;
}

int64_t CropAndResizePerBox_vec(const float *image_data, const int batch_size,
                                const int depth, const int image_height,
                                const int image_width,

                                const float *boxes_data,
                                const int *box_index_data, const int start_box,
                                const int limit_box,

                                float *crops_data, const int crop_height,
                                const int crop_width,
                                const float extrapolation_value) {
  // Measure performance of the kernel
  int64_t runtime = 0;

  const int image_channel_elements = image_height * image_width;
  const int image_elements = depth * image_channel_elements;

  const int channel_elements = crop_height * crop_width;
  const int crop_elements = depth * channel_elements;

  int b;
#pragma omp parallel for
  for (b = start_box; b < limit_box; ++b) {
    const float *box = boxes_data + b * 4;
    const float y1 = box[0];
    const float x1 = box[1];
    const float y2 = box[2];
    const float x2 = box[3];

    const int b_in = box_index_data[b];
    if (b_in < 0 || b_in >= batch_size) {
      printf("Error: batch_index %d out of range [0, %d)\n", b_in, batch_size);
      return -1;
    }

    const float height_scale =
        (crop_height > 1) ? (y2 - y1) * (image_height - 1) / (crop_height - 1)
                          : 0;
    const float width_scale =
        (crop_width > 1) ? (x2 - x1) * (image_width - 1) / (crop_width - 1) : 0;

    for (int y = 0; y < crop_height; ++y) {
      const float in_y = (crop_height > 1)
                             ? y1 * (image_height - 1) + y * height_scale
                             : 0.5 * (y1 + y2) * (image_height - 1);

      if (in_y < 0 || in_y > image_height - 1) {
        for (int x = 0; x < crop_width; ++x) {
          for (int d = 0; d < depth; ++d) {
            // crops(b, y, x, d) = extrapolation_value;
            crops_data[crop_elements * b + channel_elements * d +
                       y * crop_width + x] = extrapolation_value;
          }
        }
        continue;
      }

      const int top_y_index = floorf(in_y);
      const int bottom_y_index = ceilf(in_y);
      const float y_lerp = in_y - top_y_index;

      for (int x = 0; x < crop_width; ++x) {
        const float in_x = (crop_width > 1)
                               ? x1 * (image_width - 1) + x * width_scale
                               : 0.5 * (x1 + x2) * (image_width - 1);
        if (in_x < 0 || in_x > image_width - 1) {
          for (int d = 0; d < depth; ++d) {
            crops_data[crop_elements * b + channel_elements * d +
                       y * crop_width + x] = extrapolation_value;
          }
          continue;
        }

        const int left_x_index = floorf(in_x);
        const int right_x_index = ceilf(in_x);
        const float x_lerp = in_x - left_x_index;

        // Load the elements that belong to the same channel
        vfloat32m1_t top_left, top_right, bottom_left, bottom_right, top,
            bottom, result;
        const float *pimage = image_data + b_in * image_elements;
        ptrdiff_t cstride_pimage = image_channel_elements * sizeof(pimage[0]);
        ptrdiff_t cstride_crops = channel_elements * sizeof(crops_data[0]);
        size_t avl, vl;

        for (avl = depth; (vl = vsetvl_e32m1(avl)) > 0; avl -= vl) {
          top_left =
              vlse32_v_f32m1(&pimage[top_y_index * image_width + left_x_index],
                             cstride_pimage, vl);
          top_right =
              vlse32_v_f32m1(&pimage[top_y_index * image_width + right_x_index],
                             cstride_pimage, vl);
          bottom_left = vlse32_v_f32m1(
              &pimage[bottom_y_index * image_width + left_x_index],
              cstride_pimage, vl);
          bottom_right = vlse32_v_f32m1(
              &pimage[bottom_y_index * image_width + right_x_index],
              cstride_pimage, vl);

          top = vfsub_vv_f32m1(top_right, top_left, vl);
          top = vfmadd_vf_f32m1(top, x_lerp, top_left, vl);

          bottom = vfsub_vv_f32m1(bottom_right, bottom_left, vl);
          bottom = vfmadd_vf_f32m1(bottom, x_lerp, bottom_left, vl);

          result = vfsub_vv_f32m1(bottom, top, vl);
          result = vfmadd_vf_f32m1(result, y_lerp, top, vl);

          vsse32_v_f32m1(&crops_data[crop_elements * b + y * crop_width + x],
                         cstride_crops, result, vl);

          // Bump pointers
          pimage += vl;
          crops_data += vl;
        }
      } // end for x
    }   // end for y
  }     // end for b
  return 0;
}

// Compare the vector and scalar implementation.
// Return 0 if no error is found
// Return -1 if we have an error on the first element
// A positive return value indicates the index of the faulty element
int verify_result(float *s_crops_data, float *v_crops_data, size_t size) {
  int ret;

  for (int i = 0; i < size; ++i) {
    if (s_crops_data[i] != v_crops_data[i]) {
      ret = (!i) ? -1 : i;
      return ret;
    }
  }

  return 0;
}

// Normalized image
void init_image(float *vec, size_t size) {
  for (int i = 0; i < size; ++i)
    vec[i] = (float)((i + 5) % size) / size;
}

// Boxes must have meaningful coordinates
void init_boxes(float *vec, size_t size) {
  // 4 coordinates per box: y1 x1 y2 x2
  for (int i = 0; i < size; i += 4) {
    vec[i] = 3;      // y1
    vec[i + 1] = 7;  // x1
    vec[i + 2] = 35; // y2
    vec[i + 3] = 39; // x2
  }
}

// Each box can belong to one of the #BATCH_SIZE images
void init_boxes_idx(int *vec, size_t size) {
  for (int i = 0; i < size; ++i)
    vec[i] = i % BATCH_SIZE;
}

// Crops initialized to zero
void init_crops(float *vec, size_t size) {
  for (int i = 0; i < size; ++i)
    vec[i] = 0;
}

int main() {
  printf("\n");
  printf("===============\n");
  printf("=  RoI Align  =\n");
  printf("===============\n");
  printf("\n");
  printf("\n");

  int64_t err;
  int64_t runtime;

  // Initialize Matrices
  printf("Initializing matrices...\n");
  init_image(image_data, BATCH_SIZE * DEPTH * IMAGE_HEIGHT * IMAGE_WIDTH);
  init_boxes(boxes_data, 4 * N_BOXES);
  init_boxes_idx(box_index_data, N_BOXES);
  init_crops(crops_data, BATCH_SIZE * DEPTH * CROP_HEIGHT * CROP_WIDTH);
  init_crops(crops_data_vec, BATCH_SIZE * DEPTH * CROP_HEIGHT * CROP_WIDTH);

  // Scalar benchmark
  printf("Starting scalar benchmark...\n");
  runtime = CropAndResizePerBox(image_data, BATCH_SIZE, DEPTH, IMAGE_HEIGHT,
                                IMAGE_WIDTH, boxes_data, box_index_data, 0,
                                N_BOXES, crops_data, CROP_HEIGHT, CROP_WIDTH,
                                EXTRAPOLATION_VALUE);
  if (runtime == -1)
    return runtime;
  printf("Scalar benchmark complete.\n");
  printf("Cycles: %d\n", runtime);

  // Vector benchmark
  printf("Starting vector benchmark...\n");
  runtime = CropAndResizePerBox_vec(image_data, BATCH_SIZE, DEPTH, IMAGE_HEIGHT,
                                    IMAGE_WIDTH, boxes_data, box_index_data, 0,
                                    N_BOXES, crops_data_vec, CROP_HEIGHT,
                                    CROP_WIDTH, EXTRAPOLATION_VALUE);
  if (runtime == -1)
    return runtime;
  printf("Vector benchmark complete.\n");

  float performance = 9.0 * DEPTH / runtime;
  float utilization = 100 * performance / (2.0 * NR_LANES);
  printf("The execution took %d cycles.\n", runtime);
  printf("The performance is %f FLOP/cycle (%f%% utilization).\n", performance,
         utilization);

  // Check for errors
  err = verify_result(crops_data, crops_data_vec,
                      BATCH_SIZE * DEPTH * CROP_HEIGHT * CROP_WIDTH);
  if (err != 0) {
    // Fix return code to match the index of the faulty element
    err = (err == -1) ? 0 : err;
    printf("Failed. Index %d: %d != %d\n", err, crops_data[err],
           crops_data_vec[err]);
  } else {
    printf("Passed.\n");
  }

  return err;
}
