/*
    Original implementation taken from
    https://github.com/longcw/RoIAlign.pytorch No license found on the website.
    A question about the license was made here
    https://github.com/longcw/RoIAlign.pytorch/issues/48 Following the answer to
    this question, a correct header will be added also here
    Adaptation by: Matteo Perotti, ETH Zurich, <mperotti@iis.ee.ethz.ch>
*/

#include "roi_align.h"

void printf_fx(float num) { printf("%x\n", *((uint32_t *)&num)); }

int64_t CropAndResizePerBox(const float *image_data, const int batch_size,
                            const int depth, const int image_height,
                            const int image_width,

                            const float *boxes_data, const int *box_index_data,
                            const int start_box, const int limit_box,

                            float *crops_data, const int crop_height,
                            const int crop_width,
                            const float extrapolation_value) {

  const int image_channel_elements = image_height * image_width;
  const int image_elements = depth * image_channel_elements;

  const int channel_elements = crop_height * crop_width;
  const int crop_elements = depth * channel_elements;

  int b;
  // #pragma omp parallel for

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
#ifdef PRINTF
    printf("box = %d; y1, x1, y2, x2 --------------------------:\n", b);
    printf_fx(y1);
    printf_fx(x1);
    printf_fx(y2);
    printf_fx(y2);
#endif

    const float height_scale =
        (crop_height > 1) ? (y2 - y1) * (image_height - 1) / (crop_height - 1)
                          : 0;
    const float width_scale =
        (crop_width > 1) ? (x2 - x1) * (image_width - 1) / (crop_width - 1) : 0;

#ifdef PRINTF
    printf("h_scale, w_scale:\n");
    printf_fx(height_scale);
    printf_fx(width_scale);
#endif
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

#ifdef PRINTF
      printf("in_y, top_y_idx, bottom_y_idx, y_lerp\n");
      printf_fx(in_y);
      printf("%d\n", top_y_index);
      printf("%d\n", bottom_y_index);
      printf_fx(y_lerp);
#endif

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

#ifdef PRINTF
        printf("in_x, left_x_idx, right_x_idx, x_lerp\n");
        printf_fx(in_x);
        printf("%d\n", left_x_index);
        printf("%d\n", right_x_index);
        printf_fx(x_lerp);
#endif
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
#ifdef PRINTF
  printf("End of the scalar function\n");
#endif
  return 0;
}

int64_t CropAndResizePerBox_BCHW_vec(
    const float *image_data, const int batch_size, const int depth,
    const int image_height, const int image_width,

    const float *boxes_data, const int *box_index_data, const int start_box,
    const int limit_box,

    float *crops_data, const int crop_height, const int crop_width,
    const float extrapolation_value) {

  const int image_channel_elements = image_height * image_width;
  const int image_elements = depth * image_channel_elements;

  const int channel_elements = crop_height * crop_width;
  const int crop_elements = depth * channel_elements;

  float *prev_pimage;
  float *prev_crops_data = crops_data;

  int b;
  // #pragma omp parallel for
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
    const float *pimage = image_data + b_in * image_elements;
    float *prev_pimage = pimage;

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
        ptrdiff_t cstride_pimage = image_channel_elements * sizeof(pimage[0]);
        ptrdiff_t cstride_crops = channel_elements * sizeof(crops_data[0]);
        size_t avl, vl;

        avl = depth;
#ifdef INTRINSICS
        vl = vsetvl_e32m1(avl);

        for (avl = depth; avl > 0; avl -= vl) {
          vl = vsetvl_e32m1(avl);
          top_left =
              vlse32_v_f32m1(&pimage[top_y_index * image_width + left_x_index],
                             cstride_pimage, vl);
          top_right =
              vlse32_v_f32m1(&pimage[top_y_index * image_width + right_x_index],
                             cstride_pimage, vl);

          top = vfsub_vv_f32m1(top_right, top_left, vl);
          top = vfmadd_vf_f32m1(top, x_lerp, top_left, vl);

          bottom_left = vlse32_v_f32m1(
              &pimage[bottom_y_index * image_width + left_x_index],
              cstride_pimage, vl);
          bottom_right = vlse32_v_f32m1(
              &pimage[bottom_y_index * image_width + right_x_index],
              cstride_pimage, vl);

          bottom = vfsub_vv_f32m1(bottom_right, bottom_left, vl);
          bottom = vfmadd_vf_f32m1(bottom, x_lerp, bottom_left, vl);

          result = vfsub_vv_f32m1(bottom, top, vl);
          result = vfmadd_vf_f32m1(result, y_lerp, top, vl);

          vsse32_v_f32m1(&crops_data[crop_elements * b + y * crop_width + x],
                         cstride_crops, result, vl);

          // Bump pointers
          pimage += vl * image_channel_elements;
          crops_data += vl * channel_elements;
        }
#else
        asm volatile("vsetvli %0, %1, e32, m1, ta, ma" : "=r"(vl) : "r"(avl));

        for (avl = depth; avl > 0; avl -= vl) {
          asm volatile("vsetvli %0, %1, e32, m1, ta, ma" : "=r"(vl) : "r"(avl));
          asm volatile("vlse32.v v0, (%0), %1" ::"r"(
                           &pimage[top_y_index * image_width + left_x_index]),
                       "r"(cstride_pimage)
                       : "v0"); // top left
          asm volatile("vlse32.v v1, (%0), %1" ::"r"(
                           &pimage[top_y_index * image_width + right_x_index]),
                       "r"(cstride_pimage)
                       : "v1"); // top right

          asm volatile("vfsub.vv v2, v1, v0");                // top
          asm volatile("vfmadd.vf v2, %0, v0" ::"f"(x_lerp)); // top

          asm volatile(
              "vlse32.v v3, (%0), %1" ::"r"(
                  &pimage[bottom_y_index * image_width + left_x_index]),
              "r"(cstride_pimage)
              : "v3"); // bottom left
          asm volatile(
              "vlse32.v v4, (%0), %1" ::"r"(
                  &pimage[bottom_y_index * image_width + right_x_index]),
              "r"(cstride_pimage)
              : "v4"); // bottom right

          asm volatile("vfsub.vv v5, v4, v3");                // bottom
          asm volatile("vfmadd.vf v5, %0, v3" ::"f"(x_lerp)); // bottom

          asm volatile("vfsub.vv v6, v5, v2");                // bottom
          asm volatile("vfmadd.vf v6, %0, v2" ::"f"(y_lerp)); // bottom

          asm volatile("vsse32.v v6, (%0), %1" ::"r"(
                           &crops_data[crop_elements * b + y * crop_width + x]),
                       "r"(cstride_crops));

          // Bump pointers
          pimage += vl * image_channel_elements;
          crops_data += vl * channel_elements;
        }
#endif
        pimage = prev_pimage;

        crops_data = prev_crops_data;
      } // end for x
    }   // end for y
  }     // end for b
  return 0;
}

int64_t CropAndResizePerBox_BHWC_vec(
    const float *image_data, const int batch_size, const int depth,
    const int image_height, const int image_width,

    const float *boxes_data, const int *box_index_data, const int start_box,
    const int limit_box,

    float *crops_data, const int crop_height, const int crop_width,
    const float extrapolation_value) {

  const int image_channel_elements = image_height * image_width;
  const int image_elements = depth * image_channel_elements;

  const int channel_elements = crop_height * crop_width;
  const int crop_elements = depth * channel_elements;

  float *prev_pimage;
  float *prev_crops_data = crops_data;

  int b;
  // #pragma omp parallel for
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
    const float *pimage = image_data + b_in * image_elements;
    float *prev_pimage = pimage;

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
            crops_data[crop_elements * b + y * crop_width * depth + x * depth +
                       d] = extrapolation_value;
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
            crops_data[crop_elements * b + y * crop_width * depth + x * depth +
                       d] = extrapolation_value;
          }
          continue;
        }

        const int left_x_index = floorf(in_x);
        const int right_x_index = ceilf(in_x);
        const float x_lerp = in_x - left_x_index;

        // Load the elements that belong to the same channel
        vfloat32m1_t top_left, top_right, bottom_left, bottom_right, top,
            bottom, result;
        size_t avl, vl;

        avl = depth;

#ifdef INTRINSICS
        vl = vsetvl_e32m1(avl);

        for (avl = depth; avl > 0; avl -= vl) {
          vl = vsetvl_e32m1(avl);
          top_left = vle32_v_f32m1(
              &pimage[depth * (top_y_index * image_width + left_x_index)], vl);
          top_right = vle32_v_f32m1(
              &pimage[depth * (top_y_index * image_width + right_x_index)], vl);

          top = vfsub_vv_f32m1(top_right, top_left, vl);
          top = vfmadd_vf_f32m1(top, x_lerp, top_left, vl);

          bottom_left = vle32_v_f32m1(
              &pimage[depth * (bottom_y_index * image_width + left_x_index)],
              vl);
          bottom_right = vle32_v_f32m1(
              &pimage[depth * (bottom_y_index * image_width + right_x_index)],
              vl);

          bottom = vfsub_vv_f32m1(bottom_right, bottom_left, vl);
          bottom = vfmadd_vf_f32m1(bottom, x_lerp, bottom_left, vl);

          result = vfsub_vv_f32m1(bottom, top, vl);
          result = vfmadd_vf_f32m1(result, y_lerp, top, vl);

          vse32_v_f32m1(&crops_data[crop_elements * b + y * crop_width * depth +
                                    x * depth],
                        result, vl);

          // Bump pointers
          pimage += vl;
          crops_data += vl;
        }
#else
        asm volatile("vsetvli %0, %1, e32, m1, ta, ma" : "=r"(vl) : "r"(avl));

        for (avl = depth; avl > 0; avl -= vl) {
          asm volatile("vsetvli %0, %1, e32, m1, ta, ma" : "=r"(vl) : "r"(avl));
          asm volatile("vle32.v v0, (%0)" ::"r"(
                           &pimage[top_y_index * image_width + left_x_index])
                       : "v0"); // top left
          asm volatile("vle32.v v1, (%0)" ::"r"(
                           &pimage[top_y_index * image_width + right_x_index])
                       : "v1"); // top right

          asm volatile("vfsub.vv v2, v1, v0");                // top
          asm volatile("vfmadd.vf v2, %0, v0" ::"f"(x_lerp)); // top

          asm volatile("vle32.v v3, (%0)" ::"r"(
                           &pimage[bottom_y_index * image_width + left_x_index])
                       : "v3"); // bottom left
          asm volatile(
              "vle32.v v4, (%0)" ::"r"(
                  &pimage[bottom_y_index * image_width + right_x_index])
              : "v4"); // bottom right

          asm volatile("vfsub.vv v5, v4, v3");                // bottom
          asm volatile("vfmadd.vf v5, %0, v3" ::"f"(x_lerp)); // bottom

          asm volatile("vfsub.vv v6, v5, v2");                // bottom
          asm volatile("vfmadd.vf v6, %0, v2" ::"f"(y_lerp)); // bottom

          asm volatile("vse32.v v6, (%0)" ::"r"(
              &crops_data[crop_elements * b + y * crop_width + x]));

          // Bump pointers
          pimage += vl * image_channel_elements;
          crops_data += vl * channel_elements;
        }
#endif
        pimage = prev_pimage;

        crops_data = prev_crops_data;
      } // end for x
    }   // end for y
  }     // end for b
  return 0;
}

// Normalized image
void init_image(float *vec, size_t size) {
  for (unsigned long int i = 0; i < size; ++i)
    vec[i] = (float)((i + 5) % size) / size;
}

// Boxes must have meaningful coordinates
void init_boxes(float *vec, size_t size) {
  // 4 coordinates per box: y1 x1 y2 x2
  for (unsigned long int i = 0; i < size; i += 4) {
    vec[i] = 3;      // y1
    vec[i + 1] = 7;  // x1
    vec[i + 2] = 35; // y2
    vec[i + 3] = 39; // x2
  }
}

// Each box can belong to one of the #BATCH_SIZE images
void init_boxes_idx(int *vec, size_t size, uint64_t batch_size) {
  for (unsigned long int i = 0; i < size; ++i)
    vec[i] = i % batch_size;
}

// Crops initialized to zero
void init_crops(float *vec, size_t size) {
  for (unsigned long int i = 0; i < size; ++i)
    vec[i] = 0;
}
