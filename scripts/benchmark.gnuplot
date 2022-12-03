# Define roofline functions
roof_mem(x, beta, pi) = x <= (pi/(beta*1.0)) ? x*beta : 1/0;
roof_cpu(x, beta, pi) = x >  (pi/(beta*1.0)) ? pi     : 1/0;

# Increase the number of samples
set samples 20000

# Set logscales
set logscale x 2
set logscale y 2

# Set the grid
set grid x y

# Set the range
set xrange [1:256]
set yrange [0.5:35]

# Set axis labels
set xlabel 'Matrix size (#elements)'
set ylabel 'Performance (OP/cycle)'

# Legend on the bottom
set key bottom right

#############
## IMATMUL ##
#############

# Title
set title "imatmul performance (matrices of size #elements x #elements)"

# Output png
set term png
set out "imatmul.png"

# Plot the rooflines
plot roof_mem(x, 1,  4) w l lw 2 lc 1 notitle, roof_cpu(x, 1,  4) w l lw 2 lc 1 t  '2 Lanes', \
     'imatmul_2.benchmark'       w p lw 2 lc 1 pt 5 notitle,                                  \
     'imatmul_2_ideal.benchmark' w p lw 2 lc 1 pt 4 notitle,                                  \
     roof_mem(x, 2,  8) w l lw 2 lc 2 notitle, roof_cpu(x, 2,  8) w l lw 2 lc 2 t  '4 Lanes', \
     'imatmul_4.benchmark'       w p lw 2 lc 2 pt 5 notitle,                                  \
     'imatmul_4_ideal.benchmark' w p lw 2 lc 2 pt 4 notitle,                                  \
     roof_mem(x, 4, 16) w l lw 2 lc 3 notitle, roof_cpu(x, 4, 16) w l lw 2 lc 3 t  '8 Lanes', \
     'imatmul_8.benchmark'       w p lw 2 lc 3 pt 5 notitle,                                  \
     'imatmul_8_ideal.benchmark' w p lw 2 lc 3 pt 4 notitle,                                  \
     roof_mem(x, 8, 32) w l lw 2 lc 7 notitle, roof_cpu(x, 8, 32) w l lw 2 lc 7 t '16 Lanes', \
     'imatmul_16.benchmark'       w p lw 2 lc 7 pt 5 notitle,                                 \
     'imatmul_16_ideal.benchmark' w p lw 2 lc 7 pt 4 notitle

unset out

#############
## FMATMUL ##
#############

# Title
set title "fmatmul performance (matrices of size #elements x #elements)"

# Set axis labels
set xlabel 'Matrix size (#elements)'
set ylabel 'Performance (FLOP/cycle)'

# Output png
set term png
set out "fmatmul.png"

# Plot the rooflines
plot roof_mem(x, 1,  4) w l lw 2 lc 1 notitle, roof_cpu(x, 1,  4) w l lw 2 lc 1 t  '2 Lanes', \
     'fmatmul_2.benchmark'       w p lw 2 lc 1 pt 5 notitle,                                  \
     'fmatmul_2_ideal.benchmark' w p lw 2 lc 1 pt 4 notitle,                                  \
     roof_mem(x, 2,  8) w l lw 2 lc 2 notitle, roof_cpu(x, 2,  8) w l lw 2 lc 2 t  '4 Lanes', \
     'fmatmul_4.benchmark'       w p lw 2 lc 2 pt 5 notitle,                                  \
     'fmatmul_4_ideal.benchmark' w p lw 2 lc 2 pt 4 notitle,                                  \
     roof_mem(x, 4, 16) w l lw 2 lc 3 notitle, roof_cpu(x, 4, 16) w l lw 2 lc 3 t  '8 Lanes', \
     'fmatmul_8.benchmark'       w p lw 2 lc 3 pt 5 notitle,                                  \
     'fmatmul_8_ideal.benchmark' w p lw 2 lc 3 pt 4 notitle,                                  \
     roof_mem(x, 8, 32) w l lw 2 lc 7 notitle, roof_cpu(x, 8, 32) w l lw 2 lc 7 t '16 Lanes', \
     'fmatmul_16.benchmark'       w p lw 2 lc 7 pt 5 notitle,                                 \
     'fmatmul_16_ideal.benchmark' w p lw 2 lc 7 pt 4 notitle

#############
## ICONV2D ##
#############

# Title
set title "iconv2d performance, 3x3 filter (matrices of size #elements x #elements)"

# Set axis labels
set xlabel 'Matrix size (#elements)'
set ylabel 'Performance (OP/cycle)'

# Output png
set term png
set out "iconv2d.png"

# Plot the rooflines
plot roof_mem(x, 1,  4) w l lw 2 lc 1 notitle, roof_cpu(x, 1,  4) w l lw 2 lc 1 t  '2 Lanes', \
     'iconv2d_2.benchmark'       w p lw 2 lc 1 pt 5 notitle,                                  \
     'iconv2d_2_ideal.benchmark' w p lw 2 lc 1 pt 4 notitle,                                  \
     roof_mem(x, 2,  8) w l lw 2 lc 2 notitle, roof_cpu(x, 2,  8) w l lw 2 lc 2 t  '4 Lanes', \
     'iconv2d_4.benchmark'       w p lw 2 lc 2 pt 5 notitle,                                  \
     'iconv2d_4_ideal.benchmark' w p lw 2 lc 2 pt 4 notitle,                                  \
     roof_mem(x, 4, 16) w l lw 2 lc 3 notitle, roof_cpu(x, 4, 16) w l lw 2 lc 3 t  '8 Lanes', \
     'iconv2d_8.benchmark'       w p lw 2 lc 3 pt 5 notitle,                                  \
     'iconv2d_8_ideal.benchmark' w p lw 2 lc 3 pt 4 notitle,                                  \
     roof_mem(x, 8, 32) w l lw 2 lc 7 notitle, roof_cpu(x, 8, 32) w l lw 2 lc 7 t '16 Lanes', \
     'iconv2d_16.benchmark'       w p lw 2 lc 7 pt 5 notitle,                                 \
     'iconv2d_16_ideal.benchmark' w p lw 2 lc 7 pt 4 notitle

#############
## FCONV2D ##
#############

# Title
set title "fconv2d performance, 3x3 filter, (matrices of size #elements x #elements)"

# Set axis labels
set xlabel 'Matrix size (#elements)'
set ylabel 'Performance (OP/cycle)'

# Output png
set term png
set out "fconv2d.png"

# Plot the rooflines
plot roof_mem(x, 1,  4) w l lw 2 lc 1 notitle, roof_cpu(x, 1,  4) w l lw 2 lc 1 t  '2 Lanes', \
     'fconv2d_2.benchmark'       w p lw 2 lc 1 pt 5 notitle,                                  \
     'fconv2d_2_ideal.benchmark' w p lw 2 lc 1 pt 4 notitle,                                  \
     roof_mem(x, 2,  8) w l lw 2 lc 2 notitle, roof_cpu(x, 2,  8) w l lw 2 lc 2 t  '4 Lanes', \
     'fconv2d_4.benchmark'       w p lw 2 lc 2 pt 5 notitle,                                  \
     'fconv2d_4_ideal.benchmark' w p lw 2 lc 2 pt 4 notitle,                                  \
     roof_mem(x, 4, 16) w l lw 2 lc 3 notitle, roof_cpu(x, 4, 16) w l lw 2 lc 3 t  '8 Lanes', \
     'fconv2d_8.benchmark'       w p lw 2 lc 3 pt 5 notitle,                                  \
     'fconv2d_8_ideal.benchmark' w p lw 2 lc 3 pt 4 notitle,                                  \
     roof_mem(x, 8, 32) w l lw 2 lc 7 notitle, roof_cpu(x, 8, 32) w l lw 2 lc 7 t '16 Lanes', \
     'fconv2d_16.benchmark'       w p lw 2 lc 7 pt 5 notitle,                                 \
     'fconv2d_16_ideal.benchmark' w p lw 2 lc 7 pt 4 notitle

#############
## FCONV3D ##
#############

# Title
set title "fconv3d performance, 7x7 filter, (matrices of size #elements x #elements x #filter_size)"

# Set axis labels
set xlabel 'Matrix size (#elements)'
set ylabel 'Performance (OP/cycle)'

# Output png
set term png
set out "fconv3d.png"

# Plot the rooflines
plot roof_mem(x, 1,  4) w l lw 2 lc 1 notitle, roof_cpu(x, 1,  4) w l lw 2 lc 1 t  '2 Lanes', \
     'fconv3d_2.benchmark'       w p lw 2 lc 1 pt 5 notitle,                                  \
     'fconv3d_2_ideal.benchmark' w p lw 2 lc 1 pt 4 notitle,                                  \
     roof_mem(x, 2,  8) w l lw 2 lc 2 notitle, roof_cpu(x, 2,  8) w l lw 2 lc 2 t  '4 Lanes', \
     'fconv3d_4.benchmark'       w p lw 2 lc 2 pt 5 notitle,                                  \
     'fconv3d_4_ideal.benchmark' w p lw 2 lc 2 pt 4 notitle,                                  \
     roof_mem(x, 4, 16) w l lw 2 lc 3 notitle, roof_cpu(x, 4, 16) w l lw 2 lc 3 t  '8 Lanes', \
     'fconv3d_8.benchmark'       w p lw 2 lc 3 pt 5 notitle,                                  \
     'fconv3d_8_ideal.benchmark' w p lw 2 lc 3 pt 4 notitle,                                  \
     roof_mem(x, 8, 32) w l lw 2 lc 7 notitle, roof_cpu(x, 8, 32) w l lw 2 lc 7 t '16 Lanes', \
     'fconv3d_16.benchmark'       w p lw 2 lc 7 pt 5 notitle,                                 \
     'fconv3d_16_ideal.benchmark' w p lw 2 lc 7 pt 4 notitle

#############
## JACOBI2D ##
#############

# Title
set title "jacobi2d performance, (matrices of size #elements x #elements)"

# Set the range
set xrange [2:512]
set yrange [0.5:35]

# Set axis labels
set xlabel 'Matrix size (#elements)'
set ylabel 'Performance (DPFLOP/cycle)'

# Output png
set term png
set out "jacobi2d.png"

# Plot the rooflines for 64-bit double
# No VMACC, so maximum performance is halved
# Always performance bound under these hypotheses
plot roof_cpu(x, 2,  2) w l lw 2 lc 1 t  '2 Lanes',            \
     'jacobi2d_2.benchmark'       w p lw 2 lc 1 pt 5 notitle,  \
     'jacobi2d_2_ideal.benchmark' w p lw 2 lc 1 pt 4 notitle,  \
     roof_cpu(x, 4,  4) w l lw 2 lc 2 t  '4 Lanes',            \
     'jacobi2d_4.benchmark'       w p lw 2 lc 2 pt 5 notitle,  \
     'jacobi2d_4_ideal.benchmark' w p lw 2 lc 2 pt 4 notitle,  \
     roof_cpu(x, 8,  8) w l lw 2 lc 3 t  '8 Lanes',            \
     'jacobi2d_8.benchmark'       w p lw 2 lc 3 pt 5 notitle,  \
     'jacobi2d_8_ideal.benchmark' w p lw 2 lc 3 pt 4 notitle,  \
     roof_cpu(x, 16, 16) w l lw 2 lc 7 t '16 Lanes',           \
     'jacobi2d_16.benchmark'       w p lw 2 lc 7 pt 5 notitle, \
     'jacobi2d_16_ideal.benchmark' w p lw 2 lc 7 pt 4 notitle

#############
## DROPOUT ##
#############

# Title
set title "dropout performance, (32-bit float elements)"

# Set the range
set xrange [2:2050]
set yrange [0.125:8]

# Set axis labels
set xlabel 'Matrix size (#elements)'
set ylabel 'Performance (OP/cycle)'

# Output png
set term png
set out "dropout.png"

# Plot the rooflines
plot roof_cpu(x, 0.96,  0.96) w l lw 2 lc 1 t  '2 Lanes',\
     'dropout_2.benchmark' w p lw 2 lc 1 pt 5 notitle,   \
     'dropout_2_ideal.benchmark' w p lw 2 lc 1 pt 4 notitle,   \
     roof_cpu(x, 1.92,  1.92) w l lw 2 lc 2 t  '4 Lanes',\
     'dropout_4.benchmark' w p lw 2 lc 2 pt 5 notitle,   \
     'dropout_4_ideal.benchmark' w p lw 2 lc 2 pt 4 notitle,   \
     roof_cpu(x, 3.84, 3.84) w l lw 2 lc 3 t  '8 Lanes', \
     'dropout_8.benchmark' w p lw 2 lc 3 pt 5 notitle,   \
     'dropout_8_ideal.benchmark' w p lw 2 lc 3 pt 4 notitle,   \
     roof_cpu(x, 7.68, 7.68) w l lw 2 lc 7 t '16 Lanes', \
     'dropout_16.benchmark' w p lw 2 lc 7 pt 5 notitle,  \
     'dropout_16_ideal.benchmark' w p lw 2 lc 7 pt 4 notitle

#########
## FFT ##
#########

# Title
set title "fft performance (32-bit float data)"

# Set axis labels
set xlabel 'Vector size (#elements)'
set ylabel 'Performance (OP/cycle)'

# Set the range
set xrange [1:260]
set yrange [0.5:40]

# Output png
set term png
set out "fft.png"

# Plot the rooflines
plot roof_cpu(x, 4.8,  4.8) w l lw 2 lc 1 t  '2 Lanes',   \
     'fft_2.benchmark'       w p lw 2 lc 1 pt 5 notitle,  \
     'fft_2_ideal.benchmark' w p lw 2 lc 1 pt 4 notitle,  \
     roof_cpu(x, 9.6,  9.6) w l lw 2 lc 2 t  '4 Lanes',   \
     'fft_4.benchmark'       w p lw 2 lc 2 pt 5 notitle,  \
     'fft_4_ideal.benchmark' w p lw 2 lc 2 pt 4 notitle,  \
     roof_cpu(x, 19.2, 19.2) w l lw 2 lc 3 t  '8 Lanes',  \
     'fft_8.benchmark'       w p lw 2 lc 3 pt 5 notitle,  \
     'fft_8_ideal.benchmark' w p lw 2 lc 3 pt 4 notitle,  \
     roof_cpu(x, 38.4, 38.4) w l lw 2 lc 7 t '16 Lanes',  \
     'fft_16.benchmark'       w p lw 2 lc 7 pt 5 notitle, \
     'fft_16_ideal.benchmark' w p lw 2 lc 7 pt 4 notitle

#########
## DWT ##
#########

# Set the range
set xrange [2:520]
set yrange [0.125:50]

# Title
set title "dwt performance, (vector of size #elements)"
set out "dwt.png"

# Plot the rooflines
# 32-bit float
# Max perf = 1.5 * Lanes * 2^(EW64-SEW) = 1.5 * Lanes * 2 = 3 * Lanes
# Arith intensity = 1/2^(SEW) = 0.25
# Real BW = (4*Lanes + 2^(SEW+1)) / 3 = (4*Lanes + 8) / 3
plot roof_cpu(x, 1.7, 1.7) w l lw 2 lc 1 t '2 Lanes',     \
     'dwt_2.benchmark'       w p lw 2 lc 1 pt 5 notitle,  \
     'dwt_2_ideal.benchmark' w p lw 2 lc 1 pt 4 notitle,  \
     roof_cpu(x, 3.0, 3.0) w l lw 2 lc 2 t '4 Lanes',     \
     'dwt_4.benchmark'       w p lw 2 lc 2 pt 5 notitle,  \
     'dwt_4_ideal.benchmark' w p lw 2 lc 2 pt 4 notitle,  \
     roof_cpu(x, 5.7, 5.7) w l lw 2 lc 3 t '8 Lanes',     \
     'dwt_8.benchmark'       w p lw 2 lc 3 pt 5 notitle,  \
     'dwt_8_ideal.benchmark' w p lw 2 lc 3 pt 4 notitle,  \
     roof_cpu(x, 11, 11) w l lw 2 lc 7 t '16 Lanes',      \
     'dwt_16.benchmark'       w p lw 2 lc 7 pt 5 notitle, \
     'dwt_16_ideal.benchmark' w p lw 2 lc 7 pt 4 notitle

#########
## EXP ##
#########

# Title
set title "exp performance, (Vector of size #elements)"

# Set axis labels
set xlabel 'Vector size (#elements)'
set ylabel 'Performance (OP/cycle)'

# Output png
set term png
set out "exp.png"

# Plot the rooflines for 64-bit data
plot roof_cpu(x, 1,  1.3*2) w l lw 2 lc 1 t  '2 Lanes',   \
     'exp_2.benchmark'       w p lw 2 lc 1 pt 5 notitle,  \
     'exp_2_ideal.benchmark' w p lw 2 lc 1 pt 4 notitle,  \
     roof_cpu(x, 2,  1.3*4) w l lw 2 lc 2 t  '4 Lanes',   \
     'exp_4.benchmark'       w p lw 2 lc 2 pt 5 notitle,  \
     'exp_4_ideal.benchmark' w p lw 2 lc 2 pt 4 notitle,  \
     roof_cpu(x, 4, 1.3*8) w l lw 2 lc 3 t  '8 Lanes',    \
     'exp_8.benchmark'       w p lw 2 lc 3 pt 5 notitle,  \
     'exp_8_ideal.benchmark' w p lw 2 lc 3 pt 4 notitle,  \
     roof_cpu(x, 8, 1.3*16) w l lw 2 lc 7 t '16 Lanes',   \
     'exp_16.benchmark'       w p lw 2 lc 7 pt 5 notitle, \
     'exp_16_ideal.benchmark' w p lw 2 lc 7 pt 4 notitle

#############
## SOFTMAX ##
#############

# Title
set title "softmax performance, (Vector of size #elements)"

# Set axis labels
set xlabel 'Vector size (#elements)'
set ylabel 'Performance (OP/cycle)'

# Output png
set term png
set out "softmax.png"

# Plot the rooflines for 64-bit data
plot roof_cpu(x, 1, 64 * 2 / 25) w l lw 2 lc 1 t  '2 Lanes',   \
     'softmax_2.benchmark'       w p lw 2 lc 1 pt 5 notitle,  \
     'softmax_2_ideal.benchmark' w p lw 2 lc 1 pt 4 notitle,  \
     roof_cpu(x, 2, 64 * 4 / 25) w l lw 2 lc 2 t  '4 Lanes',   \
     'softmax_4.benchmark'       w p lw 2 lc 2 pt 5 notitle,  \
     'softmax_4_ideal.benchmark' w p lw 2 lc 2 pt 4 notitle,  \
     roof_cpu(x, 4, 64 * 8 / 25) w l lw 2 lc 3 t  '8 Lanes',    \
     'softmax_8.benchmark'       w p lw 2 lc 3 pt 5 notitle,  \
     'softmax_8_ideal.benchmark' w p lw 2 lc 3 pt 4 notitle,  \
     roof_cpu(x, 8, 64 * 16 / 25) w l lw 2 lc 7 t '16 Lanes',   \
     'softmax_16.benchmark'       w p lw 2 lc 7 pt 5 notitle, \
     'softmax_16_ideal.benchmark' w p lw 2 lc 7 pt 4 notitle

################
## PATHFINDER ##
################

# Title
set title "pathfinder performance, (Vector of size #elements)"

# Set the range
set xrange [64:2048]

# Set axis labels
set xlabel 'Vector size (#elements)'
set ylabel 'Performance (OP/cycle)'

# Output png
set term png
set out "pathfinder.png"

# Plot the rooflines for 64-bit data
plot roof_cpu(x, 1, 4) w l lw 2 lc 1 t  '2 Lanes',   \
     'pathfinder_2.benchmark'       w p lw 2 lc 1 pt 5 notitle,  \
     'pathfinder_2_ideal.benchmark' w p lw 2 lc 1 pt 4 notitle,  \
     roof_cpu(x, 2, 8) w l lw 2 lc 2 t  '4 Lanes',   \
     'pathfinder_4.benchmark'       w p lw 2 lc 2 pt 5 notitle,  \
     'pathfinder_4_ideal.benchmark' w p lw 2 lc 2 pt 4 notitle,  \
     roof_cpu(x, 4, 16) w l lw 2 lc 3 t  '8 Lanes',    \
     'pathfinder_8.benchmark'       w p lw 2 lc 3 pt 5 notitle,  \
     'pathfinder_8_ideal.benchmark' w p lw 2 lc 3 pt 4 notitle,  \
     roof_cpu(x, 8, 32) w l lw 2 lc 7 t '16 Lanes',   \
     'pathfinder_16.benchmark'       w p lw 2 lc 7 pt 5 notitle, \
     'pathfinder_16_ideal.benchmark' w p lw 2 lc 7 pt 4 notitle

###############
## ROI_ALIGN ##
###############

# Title
set title "roi_align performance, (depth: #elements)"

# Set the range
set xrange [32:1024]

# Set axis labels
set xlabel 'Depth: (#elements)'
set ylabel 'Performance (OP/cycle)'

# Output png
set term png
set out "roi_align.png"

# Plot the rooflines for 32-bit data
plot roof_cpu(x, 1, 2.4) w l lw 2 lc 1 t  '2 Lanes',   \
     'roi_align_2.benchmark'       w p lw 2 lc 1 pt 5 notitle,  \
     'roi_align_2_ideal.benchmark' w p lw 2 lc 1 pt 4 notitle,  \
     roof_cpu(x, 2, 4.8) w l lw 2 lc 2 t  '4 Lanes',   \
     'roi_align_4.benchmark'       w p lw 2 lc 2 pt 5 notitle,  \
     'roi_align_4_ideal.benchmark' w p lw 2 lc 2 pt 4 notitle,  \
     roof_cpu(x, 4, 9.6) w l lw 2 lc 3 t  '8 Lanes',    \
     'roi_align_8.benchmark'       w p lw 2 lc 3 pt 5 notitle,  \
     'roi_align_8_ideal.benchmark' w p lw 2 lc 3 pt 4 notitle,  \
     roof_cpu(x, 8, 19.2) w l lw 2 lc 7 t '16 Lanes',   \
     'roi_align_16.benchmark'       w p lw 2 lc 7 pt 5 notitle, \
     'roi_align_16_ideal.benchmark' w p lw 2 lc 7 pt 4 notitle
