#!/bin/sh

app=$1

# Fixed parameters
dtype=double
nr_lanes=4
lat=0

logdir=logs

mkdir -p ${logdir}/$app

cd ../

for banks in 8 16 32
do

if [[ $banks != 8 ]]; then
  git apply patches/ara_${banks}banks.patch
fi

for vlen in 4096 8192 16384
do

#Build hw

cd hardware/
make compile config=${nr_lanes}_lanes mem_latency=${lat} vlen=${vlen} -B

cd ../apps/

# small vl - 8 16 24 32 40 48 56 64 72 80 88 96 104 112 120 128
# medium vl - 136 144 152 160 168 176 184 192 200 208 216 224 232 240 248 256
# large vl - 512 1024
for bytes_lane in 8 16 24 32 40 48 56 64 72 80 88 96 104 112 120 128 136 144 152 160 168 176 184 192 200 208 216 224 232 240 248 256 264 272 512 520 528 1024
do

len=$((bytes_lane * nr_lanes/ 8))
echo "L=$nr_lanes LEN=$len"

# Benchmark parameters
if [[ $app == "fmatmul" ]]
then
  args_app="32 32 $len"
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
  args_app="16 $len"
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

# To run without gui
make simc app=${appname} config=${nr_lanes}_lanes mem_latency=${lat} vlen=${vlen} > $logfile

# To use gui
# make sim app=${appname} config=${nr_lanes}_lanes mem_latency=${lat} vlen=${vlen}

cd ../apps

done # bytes_lane

cd ../
done # vlen

if [[ $banks != 8 ]]; then
  git restore hardware/include/ara_pkg.sv
fi

done # banks
