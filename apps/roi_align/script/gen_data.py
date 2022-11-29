#!/usr/bin/env python3
# Copyright 2021 ETH Zurich and University of Bologna.
#
# SPDX-License-Identifier: Apache-2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# arg1: image size, arg2: filter size

import numpy as np
import sys

# Batch * Depth * Height * Width
def rand_matrix(dims):
        mtx = np.random.rand(*dims).astype(dtype=np.float32)
        return mtx

def emit(name, array, alignment='8'):
        print(".global %s" % name)
        print(".balign " + alignment)
        print("%s:" % name)
        bs = array.tobytes()
        for i in range(0, len(bs), 4):
                s = ""
                for n in range(4):
                        s += "%02x" % bs[i+3-n]
                print("    .word 0x%s" % s)

# Define the filter size and the matrix dimension (max, for now, is 128 64-bit elements)
if len(sys.argv) > 1:
        batch_size = int(sys.argv[1])
        depth      = int(sys.argv[2])
        height     = int(sys.argv[3])
        width      = int(sys.argv[4])
        n_boxes    = int(sys.argv[5])
        crop_h     = int(sys.argv[6])
        crop_w     = int(sys.argv[7])
else:
        print("Give me 7 arguments. Batch_size, depth, height, width, n_boxes (in total), crop_h, crop_w.")
        sys.exit(-1
)

# Generate a random batch of feature maps
image_data = np.random.rand(batch_size, depth, height, width).astype(np.float32)

# Generate random coordinates for the boxes
xs = np.random.uniform(0, width, size=(n_boxes, 2))
ys = np.random.uniform(0, height, size=(n_boxes, 2))

xs /= (height - 1)
ys /= (width - 1)

xs.sort(axis=1)
ys.sort(axis=1)

boxes_data = np.stack((ys[:, 0], xs[:, 0], ys[:, 1], xs[:, 1]), axis=-1).astype(np.float32)

# Generate box indexes
box_index_data = np.random.randint(0, batch_size, size=n_boxes, dtype=np.int32)

# Generate mem space for output crops
# Randomize to enhance verification
dims           = (n_boxes, depth, crop_h, crop_w)
crops_data     = rand_matrix(dims)
crops_data_vec = rand_matrix(dims)

# Print information on file
print(".section .data,\"aw\",@progbits")
emit("BATCH_SIZE", np.array(batch_size, dtype=np.uint64))
emit("DEPTH", np.array(depth, dtype=np.uint64))
emit("IMAGE_HEIGHT", np.array(height, dtype=np.uint64))
emit("IMAGE_WIDTH", np.array(width, dtype=np.uint64))
emit("N_BOXES", np.array(n_boxes, dtype=np.uint64))
emit("CROP_HEIGHT", np.array(crop_h, dtype=np.uint64))
emit("CROP_WIDTH", np.array(crop_w, dtype=np.uint64))
emit("image_data", np.concatenate(image_data), 'NR_LANES*4')
emit("boxes_data", boxes_data, 'NR_LANES*4')
emit("box_index_data", box_index_data, 'NR_LANES*4')
emit("crops_data", np.concatenate(crops_data), 'NR_LANES*4')
emit("crops_data_vec", np.concatenate(crops_data_vec), 'NR_LANES*4')
