#!/bin/sh
set -e

app=$1

# Fixed parameters
dtype=double
nr_lanes=4
lat=0

logdir=logs

mkdir -p ${logdir}/$app

for banks in 8
do
for vlen in 4096
do

#Build hw
cd ../
pwd

if [[ $banks != 8 ]]; then
  git apply patches/ara_${banks}banks.patch
fi

cd hardware/
make compile config=${nr_lanes}_lanes mem_latency=${lat} vlen=${vlen} -B

cd ../apps/

for bytes_lane in 16 32 64
do

len=$((bytes_lane * nr_lanes/ 8))
echo "L=$nr_lanes LEN=$len"

# Benchmark parameters
if [[ $app == "fmatmul" ]]
then
  args_app="64 64 $len"
  str_app=FMATMUL
elif [[ $app == "fconv2d" ]]
then
  args_app="32 $len 7"
  str_app=FCONV2D
elif [[ $app == "fdotproduct" ]]
then
  args_app="$len"
  str_app=FDOTPRODUCT
elif [[ $app == "jacobi2d" ]]
then
  r=$((len+2))
  args_app="64 $r"
  str_app=JACOBI2D
elif [[ $app == "softmax" ]]
then
  args_app="64 $len"
  str_app=SOFTMAX
elif [[ $app == "exp" ]]
then
  args_app="$len"
  str_app=EXP
else
  echo "SPECIFY app and dtype as 2 arguments to script!"
fi

# Build app
echo "$app"
make $app/data.S def_args_$app="$args_app" config=${nr_lanes}_lanes -B
cp $app/data.S benchmarks/

make bin/benchmarks ENV_DEFINES="-D$str_app -Ddtype=$dtype" config=${nr_lanes}_lanes old_data=1 -B

# Simulate
appname=${app}_${nr_lanes}_${bytes_lane}_${vlen}_${banks}

cp bin/benchmarks bin/${appname}
cp bin/benchmarks.dump bin/${appname}.dump

cd ../hardware/

logfile=../apps/${logdir}/${app}/${nr_lanes}L_${bytes_lane}B__${vlen}vlen_${banks}banks_${lat}mem.log

# make simc app=${appname} config=${nr_lanes}_lanes mem_latency=${lat} vlen=${vlen} > $logfile &
make sim app=${appname} config=${nr_lanes}_lanes mem_latency=${lat} vlen=${vlen}

if [[ $banks != 8 ]]; then
  git restore include/ara_pkg.sv
fi
cd ../apps

done
done
done
