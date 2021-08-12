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
     'imatmul_2.benchmark' w p lw 2 lc 1 pt 2 notitle,                                        \
     roof_mem(x, 2,  8) w l lw 2 lc 2 notitle, roof_cpu(x, 2,  8) w l lw 2 lc 2 t  '4 Lanes', \
     'imatmul_4.benchmark' w p lw 2 lc 2 pt 2 notitle,                                        \
     roof_mem(x, 4, 16) w l lw 2 lc 3 notitle, roof_cpu(x, 4, 16) w l lw 2 lc 3 t  '8 Lanes', \
     'imatmul_8.benchmark' w p lw 2 lc 3 pt 2 notitle,                                        \
     roof_mem(x, 8, 32) w l lw 2 lc 7 notitle, roof_cpu(x, 8, 32) w l lw 2 lc 7 t '16 Lanes', \
     'imatmul_16.benchmark' w p lw 2 lc 7 pt 2 notitle
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
     'fmatmul_2.benchmark' w p lw 2 lc 1 pt 2 notitle,                                        \
     roof_mem(x, 2,  8) w l lw 2 lc 2 notitle, roof_cpu(x, 2,  8) w l lw 2 lc 2 t  '4 Lanes', \
     'fmatmul_4.benchmark' w p lw 2 lc 2 pt 2 notitle,                                        \
     roof_mem(x, 4, 16) w l lw 2 lc 3 notitle, roof_cpu(x, 4, 16) w l lw 2 lc 3 t  '8 Lanes', \
     'fmatmul_8.benchmark' w p lw 2 lc 3 pt 2 notitle,                                        \
     roof_mem(x, 8, 32) w l lw 2 lc 7 notitle, roof_cpu(x, 8, 32) w l lw 2 lc 7 t '16 Lanes', \
     'fmatmul_16.benchmark' w p lw 2 lc 7 pt 2 notitle

#############
## ICONV2D ##
#############

# Title
set title "iconv2d performance (matrices of size #elements x #elements)"

# Set axis labels
set xlabel 'Matrix size (#elements)'
set ylabel 'Performance (OP/cycle)'

# Output png
set term png
set out "iconv2d.png"

# Plot the rooflines
plot roof_mem(x, 1,  4) w l lw 2 lc 1 notitle, roof_cpu(x, 1,  4) w l lw 2 lc 1 t  '2 Lanes', \
     'iconv2d_2.benchmark' w p lw 2 lc 1 pt 2 notitle,                                        \
     roof_mem(x, 2,  8) w l lw 2 lc 2 notitle, roof_cpu(x, 2,  8) w l lw 2 lc 2 t  '4 Lanes', \
     'iconv2d_4.benchmark' w p lw 2 lc 2 pt 2 notitle,                                        \
     roof_mem(x, 4, 16) w l lw 2 lc 3 notitle, roof_cpu(x, 4, 16) w l lw 2 lc 3 t  '8 Lanes', \
     'iconv2d_8.benchmark' w p lw 2 lc 3 pt 2 notitle,                                        \
     roof_mem(x, 8, 32) w l lw 2 lc 7 notitle, roof_cpu(x, 8, 32) w l lw 2 lc 7 t '16 Lanes', \
     'iconv2d_16.benchmark' w p lw 2 lc 7 pt 2 notitle
