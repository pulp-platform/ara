# Default app parameters

# Matrix sizes
def_args_imatmul     ?= "128 128 128"
def_args_fmatmul     ?= "128 128 128"
def_args_dtype-matmul?= "float64 128 128 128"
def_args_fmatmul-loop?= "128 128 128"
# Matrix size, filter size
def_args_iconv2d     ?= "112 7"
def_args_fconv2d     ?= "112 7"
def_args_fconv3d     ?= "112 7"
def_args_dtype-conv3d?= "112 7 float64"
# Vector size
def_args_fdotproduct ?= "512"
# Vector size
def_args_dotproduct  ?= "512"
# Matrix padded size 0, matrix padded size 1, onlyvec
def_args_jacobi2d    ?= "130 130"
# Vector size
def_args_dropout     ?= "1024"
# Vector size, data-type
def_args_fft         ?= "64 float32"
# Vector size
def_args_dwt         ?= "512"
# Vector size
def_args_exp         ?= "128"
def_args_cos         ?= "512"
def_args_log         ?= "512"
# Channels and Inner size
def_args_softmax     ?= "3 256"
# Number of steps and width of the vector
def_args_pathfinder  ?= "1 1024 64"
# Batch_size, depth, height, width, n_boxes (in total), crop_h, crop_w
def_args_roi_align   ?= "1 32 4 4 4 2 2"
# SpMV configuration: row, col, density
def_args_spmv        ?= "128 128 0.6"
# Conjugate gradient size and steps
def_args_conjugate_gradient	?= "128 0 0.5"
# box1d, particles_per_box, alpha, maxelm
def_args_lavamd      ?= "2 32 0.5 128"
