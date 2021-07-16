#!/bin/bash

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

# Measure the runtime of the following kernels
for kernel in imatmul fmatmul; do

    # Log the performance results
    > ${kernel}_${nr_lanes}.benchmark

    # Measure the following matrix sizes
    for size in 4 8 16 32 64 128; do

        tempfile=`mktemp`

        DEFINES="-DSIZE=$size -DKERNEL=$kernel" \
               make -C apps/ bin/benchmarks
        make -C hardware/ simv app=benchmarks > $tempfile

        # Extract the performance
        cat $tempfile | grep "\[performance\]" | cut -d: -f2 >> ${kernel}_${nr_lanes}.benchmark

    done
done
