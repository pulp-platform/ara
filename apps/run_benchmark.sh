#!/bin/sh
set -e

app=$1
dtype=$2
nr_lanes=$3
vlen=$4
banks=$5
bytes_lane=$6
lat=$7

logdir=logs

make clean
mkdir -p ${logdir}/$app

#Build hw
cd ../
pwd

git apply patches/ara_${banks}banks.patch
cd hardware/
make clean && make compile config=${nr_lanes}_lanes mem_latency=${lat} vlen=${vlen}

cd ../apps/

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
make $app/data.S def_args_$app="$args_app" config=${nr_lanes}_lanes
cp $app/data.S benchmarks/

make bin/benchmarks ENV_DEFINES="-D$str_app -Ddtype=$dtype" config=${nr_lanes}_lanes old_data=1

# Simulate
appname=${app}_${nr_lanes}_${bytes_lane}_${vlen}_${banks}

cp bin/benchmarks bin/${appname}
cp bin/benchmarks.dump bin/${appname}.dump

cd ../hardware/

logfile=../apps/${logdir}/${app}/${nr_lanes}L_${bytes_lane}B__${vlen}vlen_${banks}banks_${lat}mem.log

make simc app=${appname} config=${nr_lanes}_lanes mem_latency=${lat} vlen=${vlen} | tee $logfile
# make sim app=${appname} config=${nr_lanes}_lanes mem_latency=${lat} vlen=${vlen} #> $logfile &

git restore include/ara_pkg.sv
cd ../apps
