#!/usr/bin/env bash
#
# Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>
#
# When this script is called, CLANG_PATH should point to the
# clang directory used to verilate the design
# Moreover, ${kernel} should be initialized

# Useful dirs
script=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
root=${script}/..
hardware=$root/hardware

timestamp=$(date +%Y%m%d%k%M%S)
tmp=$root/benchmark_all_tmp
result=$root/benchmark-runs/$timestamp
files="*.benchmark *.png"
python=python3

# Move to root directory
cd $root

# Backup already-present files
rm -rf $tmp
mkdir -p $tmp
mv $files $tmp

# Benchmark and create results
mkdir -p $result
for n in 2 4 8 16
do
  config=${n}_lanes CLANG_PATH=${CLANG_PATH} make -B -C $hardware verilate
  config=${n}_lanes $script/benchmark.sh $kernel
done

# Call the correct plot script
if [ "$kernel" -eq "*dotproduct" ]; then
  > ${kernel}.benchmark
  > ${kernel}_ideal.benchmark
  for nr_lanes in 2 4 8 16
  do
    cat ${kernel}_${nr_lanes}.benchmark >> ${kernel}.benchmark
    cat ${kernel}_${nr_lanes}_ideal.benchmark >> ${kernel}_ideal.benchmark
  done
  ${python} ./scripts/process_dotp.py ${kernel} ${kernel}.benchmark       ${kernel}
  ${python} ./scripts/process_dotp.py ${kernel} ${kernel}_ideal.benchmark ${kernel}_ideal
else
  gnuplot $script/benchmark.gnuplot
fi

# Save results
mv *.benchmark *.png $result/

# Take the files back
mv $tmp/$files $root
rm -rf $tmp
