/*
    Original implementation taken from
    https://github.com/longcw/RoIAlign.pytorch No license found on the website.
    A question about the license was made here
    https://github.com/longcw/RoIAlign.pytorch/issues/48 Following the answer to
    this question, a correct header will be added also here
    Adaptation by: Matteo Perotti, ETH Zurich, <mperotti@iis.ee.ethz.ch>
*/

#ifndef _ROI_ALIGN_H_
#define _ROI_ALIGN_H_

#include <math.h>

#include "riscv_vector.h"
#include "util.h"

#ifndef SPIKE
#include "printf.h"
#else
#include <stdio.h>
#endif

#define DELTA 0.0001

void printf_fx(float num);

int64_t CropAndResizePerBox(const float *image_data, const int batch_size,
                            const int depth, const int image_height,
                            const int image_width,

                            const float *boxes_data, const int *box_index_data,
                            const int start_box, const int limit_box,

                            float *crops_data, const int crop_height,
                            const int crop_width,
                            const float extrapolation_value);

int64_t CropAndResizePerBox_BCHW_vec(
    const float *image_data, const int batch_size, const int depth,
    const int image_height, const int image_width,

    const float *boxes_data, const int *box_index_data, const int start_box,
    const int limit_box,

    float *crops_data, const int crop_height, const int crop_width,
    const float extrapolation_value);

int64_t CropAndResizePerBox_BHWC_vec(
    const float *image_data, const int batch_size, const int depth,
    const int image_height, const int image_width,

    const float *boxes_data, const int *box_index_data, const int start_box,
    const int limit_box,

    float *crops_data, const int crop_height, const int crop_width,
    const float extrapolation_value);

// Normalized image
void init_image(float *vec, size_t size);

// Boxes must have meaningful coordinates
void init_boxes(float *vec, size_t size);

// Each box can belong to one of the #BATCH_SIZE images
void init_boxes_idx(int *vec, size_t size, uint64_t batch_size);

// Crops initialized to zero
void init_crops(float *vec, size_t size);

#endif
