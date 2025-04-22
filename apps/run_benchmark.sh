#!/bin/sh
set -e

app=$1
dtype=$2
nr_lanes=$3
vlen=$4

logdir=logs

make clean
mkdir -p ${logdir}/$app

#Build hw
cd ../hardware/
make clean && make compile config=${nr_lanes}_lanes vlen=${vlen}
cd ../apps/

# Benchmark parameters
if [[ $app == "fmatmul" ]]
then
  lmul=4
elif [[ $app == "fconv2d" ]]
then
  lmul=2
elif [[ $app == "fdotproduct" ]]
then
  lmul=8
elif [[ $app == "jacobi2d" ]]
then
  lmul=2
elif [[ $app == "softmax" ]]
then
  lmul=1
else
  echo "SPECIFY app and dtype as 2 arguments to script!"
fi

len=$((vlen * lmul / 8))
echo "##Lanes=$nr_lanes ##vl=$len ##lmul=$lmul"

# Benchmark parameters
if [[ $app == "fmatmul" ]]
then
  args_app="32 32 $len"
  str_app=FMATMUL
elif [[ $app == "fconv2d" ]]
then
  args_app="256 $len 7"
  str_app=FCONV2D
elif [[ $app == "fdotproduct" ]]
then
  args_app="$len"
  str_app=FDOTPRODUCT
elif [[ $app == "jacobi2d" ]]
then
  r=$((len+2))
  args_app="256 $r"
  str_app=JACOBI2D
elif [[ $app == "softmax" ]]
then
  args_app="64 $len"
  str_app=SOFTMAX
else
  echo "SPECIFY app and dtype as 2 arguments to script!"
fi

# Build app
warm_cache=0
echo "$app"
make $app/data.S def_args_$app="$args_app" config=${nr_lanes}_lanes
cp $app/data.S benchmarks/
make bin/benchmarks ENV_DEFINES="-D$str_app -Ddtype=$dtype -DWARM_CACHES_ITER=$warm_cache" config=${nr_lanes}_lanes old_data=1

# Simulate
appname=${app}_${nr_lanes}_${vlen}
cp bin/benchmarks bin/${appname}
cp bin/benchmarks.dump bin/${appname}.dump

cd ../hardware/
logfile=../apps/${logdir}/${app}/${nr_lanes}L_${vlen}b.log
make sim app=${appname} config=${nr_lanes}_lanes vlen=${vlen} >> $logfile &
cd ../apps
