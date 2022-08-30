#!/bin/bash

# Python in use
PYTHON=python3

# Is this exectued by the CI?
if [ "$1" == "ci" ]
then
    ci=1
else
    ci=0
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

        if [ "$ci" == 0 ]; then
          # System with ideal dispatcher
          ENV_DEFINES="-DSIZE=$size -D${kernel^^}=1" \
                 make -C apps/ bin/benchmarks.ideal
          touch -a hardware/build
          make -C hardware/ -B simc app=benchmarks ideal_dispatcher=1 > $tempfile || exit
          # Extract the cycle count and calculate performance
	      cycles=$(cat $tempfile | grep "\[cycles\]" | cut -d: -f2)
          ./scripts/performance.py $kernel "$size" $cycles >> ${kernel}_${nr_lanes}_ideal.benchmark
        fi
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

            if [ "$ci" == 0 ]; then
              # System with ideal dispatcher
              ENV_DEFINES="-D${kernel^^}=1" \
                     make -C apps/ bin/benchmarks.ideal
              touch -a hardware/build
              make -C hardware/ -B simc app=benchmarks ideal_dispatcher=1 > $tempfile || exit
              # Extract the performance
	          cycles=$(cat $tempfile | grep "\[cycles\]" | cut -d: -f2)
              ./scripts/performance.py $kernel "$size $filter" $cycles >> ${kernel}_${nr_lanes}_ideal.benchmark
            fi
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

            if [ "$ci" == 0 ]; then
              # System with ideal dispatcher
              ENV_DEFINES="-D${kernel^^}=1" \
                     make -C apps/ bin/benchmarks.ideal
              touch -a hardware/build
              make -C hardware/ -B simc app=benchmarks ideal_dispatcher=1 > $tempfile || exit
              # Extract the performance
	          cycles=$(cat $tempfile | grep "\[cycles\]" | cut -d: -f2)
              ./scripts/performance.py $kernel "$size $filter" $cycles >> ${kernel}_${nr_lanes}_ideal.benchmark
            fi
        done
    done
done

##############
## Jacobi2d ##
##############

# Measure the runtime of the following kernels
for kernel in jacobi2d; do
    OnlyVec=1

    # Log the performance results
    > ${kernel}_${nr_lanes}.benchmark
    > ${kernel}_${nr_lanes}_ideal.benchmark

    for vsize_unpadded in 4 8 16 32 64 128 238; do
        vsize=$(($vsize_unpadded + 2))

        tempfile=`mktemp`

        # Clean, and then generate the correct matrix and filter
        make -C apps/ clean

        mkdir -p apps/benchmarks/data

        ${PYTHON} apps/$kernel/script/gen_data.py $vsize $vsize $OnlyVec > apps/benchmarks/data/data.S
        ENV_DEFINES="-D${kernel^^}=1" \
               make -C apps/ bin/benchmarks
        make -C hardware/ simv app=benchmarks > $tempfile || exit
        # Extract the performance
           cycles=$(cat $tempfile | grep "\[cycles\]" | cut -d: -f2)
        ./scripts/performance.py $kernel "$vsize" $cycles >> ${kernel}_${nr_lanes}.benchmark

        if [ "$ci" == 0 ]; then
          # System with ideal dispatcher
          ENV_DEFINES="-D${kernel^^}=1" \
                 make -C apps/ bin/benchmarks.ideal
          touch -a hardware/build
          make -C hardware/ -B simc app=benchmarks ideal_dispatcher=1 > $tempfile || exit
          # Extract the performance
             cycles=$(cat $tempfile | grep "\[cycles\]" | cut -d: -f2)
          ./scripts/performance.py $kernel "$vsize" $cycles >> ${kernel}_${nr_lanes}_ideal.benchmark
        fi
    done
done

#############
## DROPOUT ##
#############

# Measure the runtime of the following kernels
for kernel in dropout; do

    # Log the performance results
    > ${kernel}_${nr_lanes}.benchmark
    > ${kernel}_${nr_lanes}_ideal.benchmark

    for vsize in 4 8 16 32 64 128 256 512 1024 2048; do
        tempfile=`mktemp`

        # Clean, and then generate the correct matrix and filter
        make -C apps/ clean

        mkdir -p apps/benchmarks/data
        ${PYTHON} apps/$kernel/script/gen_data.py $vsize > apps/benchmarks/data/data.S

        # Standard System
        ENV_DEFINES="-D${kernel^^}=1" \
               make -C apps/ bin/benchmarks
        make -C hardware/ simv app=benchmarks > $tempfile || exit
        # Extract the performance
           cycles=$(cat $tempfile | grep "\[cycles\]" | cut -d: -f2)
        ./scripts/performance.py $kernel "$vsize" $cycles >> ${kernel}_${nr_lanes}.benchmark

        if [ "$ci" == 0 ]; then
          # System with ideal dispatcher
          ENV_DEFINES="-D${kernel^^}=1" \
                 make -C apps/ bin/benchmarks.ideal
          touch -a hardware/build
          make -C hardware/ -B simc app=benchmarks ideal_dispatcher=1 > $tempfile || exit
          # Extract the performance
             cycles=$(cat $tempfile | grep "\[cycles\]" | cut -d: -f2)
          ./scripts/performance.py $kernel "$vsize" $cycles >> ${kernel}_${nr_lanes}_ideal.benchmark
        fi
    done
done

#########
## FFT ##
#########

# Measure the runtime of the following kernels
for kernel in fft; do

    # Log the performance results
    > ${kernel}_${nr_lanes}.benchmark
    > ${kernel}_${nr_lanes}_ideal.benchmark

    dtype="float32"
    # Type should be in the format "floatXY"
    dbits=${dtype:5:2}

    # 2-lanes and vlen == 4096 cannot contain 256 float32 elements
    for vsize in 4 8 16 32 64 128 $(test $vlen -ge $(( 256 * ${dtype:5:2} )) && echo 256); do
        tempfile=`mktemp`

        # Clean, and then generate the correct matrix and filter
        make -C apps/ clean

        mkdir -p apps/benchmarks/data
        ${PYTHON} apps/$kernel/script/gen_data.py $vsize $dtype > apps/benchmarks/data/data.S
        ENV_DEFINES="-D${kernel^^}=1 -DFFT_SAMPLES=${vsize}" \
               make -C apps/ bin/benchmarks
        make -C hardware/ simv app=benchmarks > $tempfile || exit
        # Extract the performance
        cycles=$(cat $tempfile | grep "\[cycles\]" | cut -d: -f2)
        ./scripts/performance.py $kernel "$vsize" $cycles >> ${kernel}_${nr_lanes}.benchmark

        if [ "$ci" == 0 ]; then
          # System with ideal dispatcher
          ENV_DEFINES="-D${kernel^^}=1 -DFFT_SAMPLES=${vsize}" \
                 make -C apps/ bin/benchmarks.ideal
          touch -a hardware/build
          make -C hardware/ -B simc app=benchmarks ideal_dispatcher=1 > $tempfile || exit
          # Extract the performance
             cycles=$(cat $tempfile | grep "\[cycles\]" | cut -d: -f2)
          ./scripts/performance.py $kernel "$vsize" $cycles >> ${kernel}_${nr_lanes}_ideal.benchmark
        fi
    done
done

#########
## DWT ##
#########

# Measure the runtime of the following kernels
for kernel in dwt; do

    # Log the performance results
    > ${kernel}_${nr_lanes}.benchmark
    > ${kernel}_${nr_lanes}_ideal.benchmark

    for vsize in 4 8 16 32 64 128 256 512; do

        tempfile=`mktemp`

        # Clean
		make -C apps/ clean

        mkdir -p apps/benchmarks/data
        ${PYTHON} apps/$kernel/script/gen_data.py $vsize > apps/benchmarks/data/data.S
        ENV_DEFINES="-D${kernel^^}=1 -DSAMPLES=${vsize}" \
               make -C apps/ bin/benchmarks
        make -C hardware/ simv app=benchmarks > $tempfile || exit
        # Extract the performance
        cycles=$(cat $tempfile | grep "\[cycles\]" | cut -d: -f2)
        ./scripts/performance.py $kernel "$vsize" $cycles >> ${kernel}_${nr_lanes}.benchmark

        if [ "$ci" == 0 ]; then
          # System with ideal dispatcher
          ENV_DEFINES="-D${kernel^^}=1 -DSAMPLES=${vsize}" \
                 make -C apps/ bin/benchmarks.ideal
          touch -a hardware/build
          make -C hardware/ -B simc app=benchmarks ideal_dispatcher=1 > $tempfile || exit
          # Extract the performance
             cycles=$(cat $tempfile | grep "\[cycles\]" | cut -d: -f2)
          ./scripts/performance.py $kernel "$vsize" $cycles >> ${kernel}_${nr_lanes}_ideal.benchmark
        fi
    done
done
