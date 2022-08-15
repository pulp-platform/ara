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

#include "awb.h"

// uint8_t clip function from float
uint8_t clip_u8_f32_s(float f32) {
  uint32_t u32;

  // Explicit conversion to unsigned int
  asm volatile ("fcvt.wu.s %0, %1" : "=r" (u32) : "f" (f32));

  // Explicit convert
  if (u32 < (uint8_t) 0xff)
    return (uint8_t) u32;
  else
    return 0xff;
}

// Unoptimized average
float avg_8b_s(const uint8_t *i, size_t len) {
  uint32_t acc = 0;

  for (uint64_t k = 0; k < len; ++k) {
    acc += (uint32_t) i[k];
  }

  return (float) acc / len;
}

// This implementation is fixed to 3 channels
void gw_awb_s(const uint8_t *i, uint64_t ch_size) {

  // Non-const pointer
  uint8_t *_i = (uint8_t *)i;

  // Averages and gains
  float avg_r, avg_g, avg_b;
  float gain_b, gain_r;

  // Average
  avg_r = avg_8b_s(i + 0*ch_size, ch_size);
  avg_g = avg_8b_s(i + 1*ch_size, ch_size);
  avg_b = avg_8b_s(i + 2*ch_size, ch_size);

  // Gain
  gain_r = avg_g / avg_r;
  gain_b = avg_g / avg_b;

  for (uint64_t k = 0; k < ch_size; ++k) {
    _i[k] = clip_u8_f32_s((float) _i[k] * gain_r);
  }

  _i += 2*ch_size;

  for (uint64_t k = 0; k < ch_size; ++k) {
    _i[k] = clip_u8_f32_s((float) _i[k] * gain_b);
  }
}

// Greyworld-HP awb
void gw_awb_v(const uint8_t *i, uint64_t ch_size) {

  // This implementation is fixed to 3 channels
  const uint64_t channels = 3;

  // Non-const pointer
  uint8_t *_i = (uint8_t *)i;

  // Averages are calculated using 32-bit integers for the accumulation
  // In the worst case, we can sum up to 2^(24) == 16777216 int8_t values
  // If the image has w == h, w == h can be max 2^(12) == 4096 pixels
  // To handle bigger images, use int64_t instead and add one level of
  // conversions and add a conversion level
  uint32_t redsum_ch[3];
  float avg_r, avg_g, avg_b;
  float gain[2];

  //////////////////////////////////////
  // Find the average of each channel //
  //////////////////////////////////////

  size_t avl;
  avl = ch_size;

  size_t vl = vsetvl_e8m4(avl);

  vuint8m4_t buf0, buf1;
  vuint16m8_t acc;
  vuint32m1_t red;

  // This algorithm works if undisturbed policy is respected
  // Stripmine each channel
  for (uint64_t ch = 0; ch < channels; ++ch) {
    avl = ch_size;
    for (; avl > 0; avl -= vl) {
      // Initialize the accumulator during first iteration
      if (avl == ch_size) {
        buf1 = vle8_v_u8m4(_i, vl);
        acc = vwaddu_vx_u16m8(buf1, 0, vl);
        _i  += vl;
        avl -= vl;
        // Break if we are over with the accumulation
        if (!avl) break;
      }
      // Stripmine
      vl = vsetvl_e8m4(avl);
      // Load the next chunk
      buf0 = vle8_v_u8m4(_i, vl);
      _i += vl;
      // Accumulate on 16-bit
      acc = vwaddu_wv_u16m8(acc, buf0, vl);
    }
    // Initialize red scalar
    red = vmv_s_x_u32m1(red, 0, vl);
    // Reduce to 32-bit
    red = vwredsumu_vs_u16m8_u32m1(red, acc, red, vl);
    // Return the value
    redsum_ch[ch] = vmv_x_s_u32m1_u32(red);
  }

  // Average
  avg_r = (float) redsum_ch[0] / ch_size;
  avg_g = (float) redsum_ch[1] / ch_size;
  avg_b = (float) redsum_ch[2] / ch_size;

  // Gains
  gain[0] = avg_g / avg_r; // gain_r
  gain[1] = avg_g / avg_b; // gain_b

  vuint8m2_t  buf8;
  vuint16m4_t buf16;
  vuint32m8_t buf32u;
  vfloat32m8_t buf32f;

  // Rescale pixels
  avl = ch_size;
  vl = vsetvl_e8m4(avl);
  _i = (uint8_t*) i;
  // Rescale r and b channels
  for (uint64_t ch = 0; ch < channels-1; ++ch) {
    for (; avl > 0; avl -= vl) {
      // Stripmine
      vl = vsetvl_e8m4(avl);
      // Load pixels
      buf8 = vle8_v_u8m2(_i, vl);
      // Scale them to 16-bit
      buf16 = vwaddu_vx_u16m4(buf8, 0, vl);
      // Scale them to 32-bit
      buf32u = vwaddu_vx_u32m8(buf16, 0, vl);
      // Convert to float
      buf32f = vfcvt_f_xu_v_f32m8(buf32u, vl);
      // Rescale
      buf32f = vfmul_vf_f32m8(buf32f, gain[ch], vl);
      // Convert to 32-bit
      buf32u = vfcvt_xu_f_v_u32m8(buf32f, vl);
      // Convert to 16-bit
      buf16 = vnclipu_wx_u16m4(buf32u, 0, vl);
      // Convert to 8-bit
      buf8 = vnclipu_wx_u8m2(buf16, 0, vl);
      // Store back
      vse8_v_u8m2(_i, buf8, vl);
      // Bump pointers
      _i += vl;
    }
    avl = ch_size;
    _i += ch_size;
  }
}
