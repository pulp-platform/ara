#!/bin/bash

# Python in use
PYTHON=python3

# Command to compile ideal dispatcher system
# If questa is not installed, the ideal dispatcher
# metrics will be the copy of the default system
if [ "$1" == "questa" ]
then
    ID_SIMULATOR=simc
else
    ID_SIMULATOR=simv
fi

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

############
## MATMUL ##
############

# Measure the runtime of the following kernels
for kernel in imatmul fmatmul; do

    # Log the performance results
    > ${kernel}_${nr_lanes}.benchmark
    > ${kernel}_${nr_lanes}_ideal.benchmark

    # Measure the following matrix sizes
    for size in 4 8 16 32 64 128; do

        tempfile=`mktemp`

        # Clean, and then generate the correct matrix and filter
		make -C apps/ clean

        # Standard system
        ENV_DEFINES="-DSIZE=$size -D${kernel^^}=1" \
               make -C apps/ bin/benchmarks
        make -C hardware/ simv app=benchmarks > $tempfile || exit
        # Extract the cycle count and calculate performance
	    cycles=$(cat $tempfile | grep "\[cycles\]" | cut -d: -f2)
        ./scripts/performance.py $kernel "$size" $cycles >> ${kernel}_${nr_lanes}.benchmark

        # System with ideal dispatcher
        ENV_DEFINES="-DSIZE=$size -D${kernel^^}=1" \
               make -C apps/ bin/benchmarks.ideal
        touch -a hardware/build
        make -C hardware/ -B $ID_SIMULATOR app=benchmarks ideal_dispatcher=1 > $tempfile || exit
        # Extract the cycle count and calculate performance
	    cycles=$(cat $tempfile | grep "\[cycles\]" | cut -d: -f2)
        ./scripts/performance.py $kernel "$size" $cycles >> ${kernel}_${nr_lanes}_ideal.benchmark
    done
done

################
## CONV2D 3x3 ##
################

# Measure the runtime of the following kernels
for kernel in iconv2d fconv2d; do

    # Log the performance results
    > ${kernel}_${nr_lanes}.benchmark
    > ${kernel}_${nr_lanes}_ideal.benchmark

    # Measure the following matrix and filter sizes
    # The input image is also padded, and the max vl is 128
    # MAXVL_M2_64b - F_MAX + 1 = 128 - 7 + 1 = 122 is the max number of elements
    # Actually 120, since it must be divible by 4
    for msize in 4 8 16 32 64 112; do
        for fsize in 3; do
            tempfile=`mktemp`

            # Clean, and then generate the correct matrix and filter
			make -C apps/ clean

			mkdir -p apps/benchmarks/data
			${PYTHON} apps/$kernel/script/gen_data.py $msize $fsize > apps/benchmarks/data/data.S

            # Standard System
            ENV_DEFINES="-D${kernel^^}=1" \
                   make -C apps/ bin/benchmarks
            make -C hardware/ simv app=benchmarks > $tempfile || exit
            # Extract the performance
	        cycles=$(cat $tempfile | grep "\[cycles\]" | cut -d: -f2)
            ./scripts/performance.py $kernel "$size $filter" $cycles >> ${kernel}_${nr_lanes}.benchmark

            # System with ideal dispatcher
            ENV_DEFINES="-D${kernel^^}=1" \
                   make -C apps/ bin/benchmarks.ideal
            touch -a hardware/build
            make -C hardware/ -B $ID_SIMULATOR app=benchmarks ideal_dispatcher=1 > $tempfile || exit
            # Extract the performance
	        cycles=$(cat $tempfile | grep "\[cycles\]" | cut -d: -f2)
            ./scripts/performance.py $kernel "$size $filter" $cycles >> ${kernel}_${nr_lanes}_ideal.benchmark
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
    > ${kernel}_${nr_lanes}_ideal.benchmark

    # Measure the following matrix and filter sizes
    # The input image is also padded, and the max vl is 128
    # MAXVL_M2_64b - F_MAX + 1 = 128 - 7 + 1 = 122 is the max number of elements
    # Actually 120, since it must be divible by 4
    for msize in 4 8 16 32 64 112; do
        for fsize in 7; do
            tempfile=`mktemp`

            # Clean, and then generate the correct matrix and filter
			make -C apps/ clean

			mkdir -p apps/benchmarks/data
            ${PYTHON} apps/$kernel/script/gen_data.py $msize $fsize > apps/benchmarks/data/data.S

            # Standard System
            ENV_DEFINES="-D${kernel^^}=1" \
                   make -C apps/ bin/benchmarks
            make -C hardware/ simv app=benchmarks > $tempfile || exit
            # Extract the performance
	        cycles=$(cat $tempfile | grep "\[cycles\]" | cut -d: -f2)
            ./scripts/performance.py $kernel "$size $filter" $cycles >> ${kernel}_${nr_lanes}.benchmark

            # System with ideal dispatcher
            ENV_DEFINES="-D${kernel^^}=1" \
                   make -C apps/ bin/benchmarks.ideal
            touch -a hardware/build
            make -C hardware/ -B $ID_SIMULATOR app=benchmarks ideal_dispatcher=1 > $tempfile || exit
            # Extract the performance
	        cycles=$(cat $tempfile | grep "\[cycles\]" | cut -d: -f2)
            ./scripts/performance.py $kernel "$size $filter" $cycles >> ${kernel}_${nr_lanes}_ideal.benchmark
        done
    done
done
