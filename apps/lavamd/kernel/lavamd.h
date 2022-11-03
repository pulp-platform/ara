// See LICENSE and LICENSE_1 for licensing terms of the original
// and vectorized version, respectively.

/*************************************************************************
 * RISC-V Vectorized Version
 * Author: Cristóbal Ramírez Lazo
 * email: cristobal.ramirez@bsc.es
 * Barcelona Supercomputing Center (2020)
 *************************************************************************/

// Modifications + Fixes to the vectorized version by:
// Matteo Perotti <mperotti@iis.ee.ethz.ch>

#ifndef _LAVAMD_H_
#define _LAVAMD_H_

#include "../lib/exp.h"
#include "rivec/vector_defines.h"
#include <math.h>
#include <stdint.h>

#define fp float

#define DOT(A, B) ((A.x) * (B.x) + (A.y) * (B.y) + (A.z) * (B.z))

typedef struct __attribute__((__packed__)) {

  fp x, y, z;

} THREE_VECTOR;

typedef struct __attribute__((__packed__)) {

  fp v, x, y, z;

} FOUR_VECTOR;

typedef struct __attribute__((__packed__)) nei_str {

  // neighbor box
  int x, y, z;
  int number;
  long offset;

} nei_str;

typedef struct __attribute__((__packed__)) box_str {

  // home box
  int x, y, z;
  int number;
  long offset;
  // neighbor boxes
  int nn;
  nei_str nei[26];
} box_str;

void kernel(fp alpha, uint64_t n_boxes, box_str *box, FOUR_VECTOR *rv, fp *qv,
            FOUR_VECTOR *fv, uint64_t NUMBER_PAR_PER_BOX);
void kernel_vec(fp alpha, uint64_t n_boxes, box_str *box, FOUR_VECTOR *rv,
                fp *qv, FOUR_VECTOR *fv, uint64_t NUMBER_PAR_PER_BOX);

#define THRESHOLD 0.001

#endif
