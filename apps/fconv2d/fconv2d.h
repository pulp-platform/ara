#ifndef ICONV2D_H
#define ICONV2D_H

#include <stdint.h>
#include <stdio.h>

void fconv2d_3x3(double *o, double *i, double *f, int64_t R, int64_t C,
                 int64_t F);
void fconv2d_vec_4xC_slice_init_3x3(double *o, int64_t C);
void fconv2d_vec_4xC_slice_preload_3x3(double *i, int64_t C, int64_t F);
void fconv2d_vec_4xC_slice_move_3x3(int64_t C, int64_t F);
void fconv2d_vec_4xC_3x3(double *o, double *i, double *f, int64_t C, int64_t F);
void fconv2d_vec_4xC_3x3_full(double *o, double *i, double *f, int64_t C,
                              int64_t F);

void fconv2d_7x7_opt(double *o, double *i, double *f, int64_t R, int64_t C,
                     int64_t F);

#define FABS(x) ((x < 0) ? -x : x)

// Threshold for FP numbers comparison during the final check
#define THRESHOLD 0.000000000001
//#define THRESHOLD 0

#endif
