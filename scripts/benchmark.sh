#!/bin/bash

# Python in use
PYTHON=python3

# Include Ara's configuration
if [ -z ${config} ]; then
    if [ -z ${ARA_CONFIGURATION} ]; then
        config=default
    else
        config=${ARA_CONFIGURATION}
    fi
fi

tmpscript=`mktemp`
sed "s/ ?= /=/g" config/${config}.mk > $tmpscript
source ${tmpscript}

##########
## AXPY ##
##########

## Measure the runtime of the following kernels
#for kernel in iaxpy, faxpy; do
#
#    # Log the performance results
#    > ${kernel}_${nr_lanes}.benchmark
#
#    # Measure the following matrix and filter sizes
#    # The input image is also padded, and the max vl is 128
#    # MAXVL_M2_64b - F_MAX + 1 = 128 - 7 + 1 = 122 is the max number of elements
#    # Actually 120, since it must be divible by 4
#    for vsize in 4 8 16 32 64 128; do
#        tempfile=`mktemp`
#
#        ENV_DEFINES="-D${kernel^^}=1" \
#               make -C apps/ bin/benchmarks
#        make -C hardware/ simv app=benchmarks > $tempfile
#
#        # Extract the performance
#        cat $tempfile | grep "\[performance\]" | cut -d: -f2 >> ${kernel}_${nr_lanes}.benchmark
#
#    done
#done

############
## MATMUL ##
############

# Measure the runtime of the following kernels
for kernel in imatmul fmatmul; do

    # Log the performance results
    > ${kernel}_${nr_lanes}.benchmark

    # Measure the following matrix sizes
    for size in 4 8 16 32 64 128; do

        tempfile=`mktemp`

        ENV_DEFINES="-DSIZE=$size -D${kernel^^}=1" \
               make -C apps/ bin/benchmarks
        make -C hardware/ simv app=benchmarks > $tempfile

        # Extract the performance
        cat $tempfile | grep "\[performance\]" | cut -d: -f2 >> ${kernel}_${nr_lanes}.benchmark

    done
done

################
## CONV2D 3x3 ##
################

# Measure the runtime of the following kernels
for kernel in iconv2d fconv2d; do

    # Log the performance results
    > ${kernel}_${nr_lanes}.benchmark

    # Measure the following matrix and filter sizes
    # The input image is also padded, and the max vl is 128
    # MAXVL_M2_64b - F_MAX + 1 = 128 - 7 + 1 = 122 is the max number of elements
    # Actually 120, since it must be divible by 4
    for msize in 4 8 16 32 64 112; do
        for fsize in 3; do
            tempfile=`mktemp`

            # Clean, and then generate the correct matrix and filter
            rm -f apps/benchmarks/data/*.S.o apps/benchmarks/kernels/*.S.o apps/benchmarks/kernels/*.c.o
			make -C apps/ clean

			mkdir -p apps/benchmarks/data
			${PYTHON} apps/$kernel/script/gen_data.py $msize $fsize > apps/benchmarks/data/data.S
            ENV_DEFINES="-D${kernel^^}=1" \
                   make -C apps/ bin/benchmarks
            make -C hardware/ simv app=benchmarks > $tempfile

            # Extract the performance
            cat $tempfile | grep "\[performance\]" | cut -d: -f2 >> ${kernel}_${nr_lanes}.benchmark

        done
    done
done

################
## CONV3D 7x7 ##
################

# Measure the runtime of the following kernels
for kernel in fconv3d; do

    # Log the performance results
    > ${kernel}_${nr_lanes}.benchmark

    # Measure the following matrix and filter sizes
    # The input image is also padded, and the max vl is 128
    # MAXVL_M2_64b - F_MAX + 1 = 128 - 7 + 1 = 122 is the max number of elements
    # Actually 120, since it must be divible by 4
    for msize in 4 8 16 32 64 112; do
        for fsize in 7; do
            tempfile=`mktemp`

            # Clean, and then generate the correct matrix and filter
            rm -f apps/benchmarks/data/*.S.o apps/benchmarks/kernels/*.S.o apps/benchmarks/kernels/*.c.o
			make -C apps/ clean

			mkdir -p apps/benchmarks/data
            ${PYTHON} apps/$kernel/script/gen_data.py $msize $fsize > apps/benchmarks/data/data.S
            ENV_DEFINES="-D${kernel^^}=1" \
                   make -C apps/ bin/benchmarks
            make -C hardware/ simv app=benchmarks > $tempfile

            # Extract the performance
            cat $tempfile | grep "\[performance\]" | cut -d: -f2 >> ${kernel}_${nr_lanes}.benchmark

        done
    done
done

##############
## JACOBI2D ##
##############

#############
## DROPOUT ##
#############

##############
## ROIALIGN ##
##############
