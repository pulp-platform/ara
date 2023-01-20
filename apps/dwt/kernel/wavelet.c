// Copyright 2022 ETH Zurich and University of Bologna.
//
// SPDX-License-Identifier: Apache-2.0
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>
//         Scalar version ispired by "Matteo Pesaresi 10/10/2017"

#include "wavelet.h"
#include <stdio.h>

extern int64_t event_trigger;

static inline void dwt_step(const gsl_wavelet *w, float *a, size_t n,
                            float *buf) {
  size_t i, ii;
  size_t jf;
  size_t k;
  size_t n1, ni, nh, nmod;
  float h, g;

  // Setup
  nmod = w->nc * n;
  nmod -= w->offset; // center support
  n1 = n - 1;
  nh = n >> 1;

  // Compute and downsample (factor 2)
  for (i = 0, ii = 0; i < n; i += 2, ++ii) {
    h = 0;
    g = 0;
    ni = i + nmod;
    for (k = 0; k < w->nc; k++) {
      // If offset == 0, then jf == (i + k)
      jf = n1 & (ni + k);
      h += w->h1[k] * a[jf];
      g += w->g1[k] * a[jf];
    }
    a[ii] = g;
    buf[ii] = h;
  }

  for (k = 0; k < n / 2; ++k) {
    a[k + nh] = buf[k];
  }
}

void gsl_wavelet_transform(float *data, size_t n, float *buf,
                           int first_iter_only) {

  gsl_wavelet haar;
  gsl_wavelet *w;
  size_t i;

  w = &haar;
  w->h1 = ch_2;
  w->g1 = cg_2;
  w->nc = 2;
  w->offset = 0;

  for (i = n; i >= 2; i >>= 1) {
    dwt_step(w, data, i, buf);
    if (first_iter_only)
      i = 0;
  }
}

// For now, compatible with order 2 filters
// For higher filter orders, pad the input sample vector first
// Then, use vslide1down selectively
static inline void dwt_step_vector(const gsl_wavelet *w, float *samples,
                                   size_t n, float *buf) {

  size_t avl = n;
  vfloat32m4_t sample_vec_0;
  vfloat32m4_t sample_vec_1;
  vfloat32m4_t g_vec;
  vfloat32m4_t h_vec;

  float *samples_r = samples;
  float *samples_w = samples;
  float *buf_r = buf;
  float *buf_w = buf;

  // Strip-Mining loop
  for (size_t vl = vsetvl_e32m4(avl); avl > 0; avl -= vl) {
    vl = vsetvl_e32m4(avl);
    // If we have enough samples, fill the vector registers!
    if (avl >= 2 * vl)
      vl *= 2;
#ifdef SEGMENT
    // Segment load the vectors. ToDo: check if vl/2 is correct
    vlseg2e32_v_f32m4(sample_vec_0, sample_vec_1, samples_r, vl / 2);
#else
    // Strided load (inefficient!)
    sample_vec_0 = vlse32_v_f32m4(samples_r, 2 * sizeof(*samples_r), vl / 2);
    sample_vec_1 =
        vlse32_v_f32m4(samples_r + 1, 2 * sizeof(*samples_r), vl / 2);
#endif

    // First implementation
    // nc == 2!

    // Generate the g vector and store it back
    // Generate the h vector and store it back
    g_vec = vfmul_vf_f32m4(sample_vec_0, w->g1[0], vl / 2);
    h_vec = vfmul_vf_f32m4(sample_vec_0, w->h1[0], vl / 2);

    g_vec = vfmacc_vf_f32m4(g_vec, w->g1[1], sample_vec_1, vl / 2);
    h_vec = vfmacc_vf_f32m4(h_vec, w->h1[1], sample_vec_1, vl / 2);

    vse32_v_f32m4(samples_w, g_vec, vl / 2);
    vse32_v_f32m4(buf_w, h_vec, vl / 2);

    // Bump pointers
    samples_r += vl;
    samples_w += vl / 2;
    buf_w += vl / 2;
  }

  // Memcpy h_vec to the samples vector
  avl = n / 2;
  for (size_t vl = vsetvl_e32m4(avl); avl > 0; avl -= vl) {
    h_vec = vle32_v_f32m4(buf_r, vl);
    vse32_v_f32m4(samples_w, h_vec, vl);
    buf_r += vl;
    samples_w += vl;
  }
}

// The signal should be already padded
void gsl_wavelet_transform_vector(float *data, size_t n, float *buf,
                                  int first_iter_only) {

  gsl_wavelet haar;
  gsl_wavelet *w;
  size_t i;

  w = &haar;
  w->h1 = ch_2;
  w->g1 = cg_2;
  w->nc = 2;
  w->offset = 0;

  for (i = n; i >= 2; i >>= 1) {
#ifdef VCD_DUMP
    // Start dumping VCD
    if (i == n)
      event_trigger = +1;
    // Stop dumping VCD
    if (i == (n >> 1))
      event_trigger = -1;
#endif
    dwt_step_vector(w, data, i, buf);
    if (first_iter_only)
      i = 0;
  }
}
