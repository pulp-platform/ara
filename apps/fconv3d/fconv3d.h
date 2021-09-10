#ifndef ICONV2D_H
#define ICONV2D_H

#include <stdint.h>
#include <stdio.h>

void fconv3d_3x7x7(double *o, double *i, double *f, int64_t M, int64_t N,
                     int64_t C, int64_t F);

#define FABS(x) ((x < 0) ? -x : x)

// Threshold for FP numbers comparison during the final check
#define THRESHOLD 0.000000000001
//#define THRESHOLD 0

#endif
