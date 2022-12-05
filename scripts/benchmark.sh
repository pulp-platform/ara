#!/bin/bash
# benchmark.sh [ci] [$app]
# Pass the option "ci" if there is no QuestaSim installed
# Pass the name of the app to benchmark
# If no app is passed, all the apps are benchmarked

###########
## Setup ##
###########

# Python in use
python=python3

# Is this exectued by the CI?
if [ "$1" == "ci" ]
then
    ci=1
    sim=simv
    shift
else
    ci=0
    sim=simc
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

# Initialize the error report
timestamp=$(date +%Y%m%d%H%M%S)
error_rpt=./benchmark_errors_${timestamp}.rpt
> ${error_rpt}

#############
## Helpers ##
#############

clean_and_gen_data() {
  # Kernel name
  kernel=$1
  # Args for gen_data.py
  args=$2

  echo "Cleaning apps folder"
  make -C apps/ clean
  echo "Creating new data directory"
  mkdir -p apps/benchmarks/data
  echo "Generating new data for $kernel:"
  echo "$python ./apps/$kernel/script/gen_data.py $args > apps/benchmarks/data/data.S"
  $python ./apps/$kernel/script/gen_data.py $args > apps/benchmarks/data/data.S || exit
}

compile_and_run() {
  kernel=$1
  defines=$2
  tempfile=$3
  id=$4

  # Check for ideal dispatcher run
  if [[ $id == 1 ]]; then
    id_suffix=".ideal"
    id_opt="ideal_dispatcher=1"
  else
    id_suffix=""
    id_opt=""
  fi

  echo "Compiling ${kernel}${id_suffix} benchmark:"
  config=${config} ENV_DEFINES="-D${kernel^^}=1 $defines" \
         make -C apps/ bin/benchmarks${id_suffix} || exit
  echo "Simulating ${kernel}${id_suffix}:"
  config=${config} make -C hardware/ -B $sim app=benchmarks ${id_opt} > $tempfile || exit
}

extract_performance() {
  kernel=$1
  args=$2
  tempfile=$3
  outfile=$4

  echo "Extracting cycle count measure"
  hw_cycles=$(cat $tempfile | grep "\[hw-cycles\]" | tr -s " " | cut -d: -f 2)
  # If we have a SW-cycle count, check that the HW one for improved reliability
  if [[ ! $outfile =~ "ideal" ]]; then
    sw_cycles=$(cat $tempfile | grep "\[sw-cycles\]" | tr -s " " | cut -d: -f 2)
    echo "Checking hw and sw cycles. $python ./scripts/check_cycles.py $kernel $hw_cycles $sw_cycles"
    $python ./scripts/check_cycles.py $kernel $hw_cycles $sw_cycles || exit
  fi
  echo "Extracting performance from cycle count"
  $python ./scripts/performance.py $kernel "$args" $hw_cycles >> $outfile || exit
}

extract_performance_dotp() {
  kernel=$1
  args=$2
  sew=$3
  tempfile=$4
  outfile=$5

  info_0="[${kernel}]: ${nr_lanes} ${args} ${sew}"
  info_1=$(cat $tempfile | grep "\[hw-cycles\]" | tr -s " " | cut -d: -f 2)
  info="$info_0 $info_1"
  echo $info >> $outfile
}

# The two simulations can produce different results whenever they use
# unordered floating-point sum reductions. This is because bank conflicts
# do not guarantee ordered and cycle-invariant accesses to the VRF.
# FP-reductions use different accumulators also within each lane,
# and the incoming operands can be added (subtracted) to different partial
# accumulators, i.e. the order of the reduction operations can be different
# also among simulations with the same source data whenever the system or
# program are different.
verify_id_results() {
  threshold=$1
  sew=$2

  id_results=hardware/id_results.txt
  gold_results=hardware/gold_results.txt

  echo "Summary of the first 10 lines for ID results:"
  head -n 10 ${id_results}
  echo "Summary of the first 10 lines for default-system results:"
  head -n 10 ${gold_results}
  echo "Verifying ideal_dispatcher results:"
  if [ $threshold -gt 0 ]; then
    i=0
    while IFS= read -r l0 && IFS= read -r l1 <&3; do
      # Find the last byte of a floating-point word
      i=$(($i + 1))
      if [ $(($i % ($sew / 8))) -eq 0 ]; then
        # abs(x-y)
        diff=$((16#${l0} - 16#${l1}))
        diff=${diff#-}
        # More than threshold?
        if [[ $diff -gt $threshold ]]; then
          echo "Error. Test failed."
          return -1
        fi
      fi
    done < ${id_results} 3< ${gold_results}
  else
    diff ${id_results} ${gold_results}
    if [ $? -ne 0 ]; then
      echo "Error. Test failed."
    fi
    return $?
  fi
}

sew_from_dtype() {
  case $1 in
    "double" | "int64_t" | "uint64_t")
    echo '64'
    ;;

    "float" | "int32_t" | "uint32_t")
    echo '32'
    ;;

    "_Float16" | "int16_t" | "uint16_t")
    echo '16'
    ;;

    "_Float8" | "int8_t" | "uint8_t")
    echo '8'
    ;;

    *)
    echo '-'
    ;;
  esac
}

#############
## Kernels ##
#############

############
## MATMUL ##
############

matmul() {

  kernel=$1
  defines=""

  tempfile=`mktemp`

  # Log the performance results
  > ${kernel}_${nr_lanes}.benchmark
  > ${kernel}_${nr_lanes}_ideal.benchmark

  # Measure the following matrix sizes
  for size in 4 8 16 32 64 128; do

    args="$size $size $size"

    # Clean
    clean_and_gen_data $kernel "$args" || exit

    # Default System
    compile_and_run $kernel "$defines" $tempfile 0                                || exit
    extract_performance $kernel "$args" $tempfile ${kernel}_${nr_lanes}.benchmark || exit

    # Ideal Dispatcher System, if QuestaSim is available
    if [ "$ci" == 0 ]; then
      compile_and_run $kernel "$defines" $tempfile 1                                      || exit
      extract_performance $kernel "$args" $tempfile ${kernel}_${nr_lanes}_ideal.benchmark || exit
      # Verify ID results is non-blocking! Check the report afterwards
      verify_id_results 0 | tee -a ${error_rpt}
    fi
  done
}

################
## CONV2D 3x3 ##
################

conv2d() {

  kernel=$1
  defines=""

  tempfile=`mktemp`

  # Log the performance results
  > ${kernel}_${nr_lanes}.benchmark
  > ${kernel}_${nr_lanes}_ideal.benchmark

  # Measure the following matrix and filter sizes
  # The input image is also padded, and the max vl is 128
  # MAXVL_M2_64b - F_MAX + 1 = 128 - 7 + 1 = 122 is the max number of elements
  # Actually 120, since it must be divible by 4
  for msize in 4 8 16 32 64 112; do
    for fsize in 3; do

      args="$msize $fsize"

      clean_and_gen_data $kernel "$args" || exit

      # Default System
      compile_and_run $kernel "$defines" $tempfile 0                                || exit
      extract_performance $kernel "$args" $tempfile ${kernel}_${nr_lanes}.benchmark || exit

      # Ideal Dispatcher System, if QuestaSim is available
      if [ "$ci" == 0 ]; then
        compile_and_run $kernel "$defines" $tempfile 1                                      || exit
        extract_performance $kernel "$args" $tempfile ${kernel}_${nr_lanes}_ideal.benchmark || exit
        # Verify ID results is non-blocking! Check the report afterwards
        verify_id_results 0 | tee -a ${error_rpt}
      fi
    done
  done
}

################
## CONV3D 7x7 ##
################

fconv3d() {

  kernel=fconv3d
  defines=""

  tempfile=`mktemp`

  # Log the performance results
  > ${kernel}_${nr_lanes}.benchmark
  > ${kernel}_${nr_lanes}_ideal.benchmark

  # Measure the following matrix and filter sizes
  # The input image is also padded, and the max vl is 128
  # MAXVL_M2_64b - F_MAX + 1 = 128 - 7 + 1 = 122 is the max number of elements
  # Actually 120, since it must be divible by 4
  for msize in 4 8 16 32 64 112; do
    for fsize in 7; do

      args="$msize $fsize"

      clean_and_gen_data $kernel "$args" || exit

      # Default System
      compile_and_run $kernel "$defines" $tempfile 0                                || exit
      extract_performance $kernel "$args" $tempfile ${kernel}_${nr_lanes}.benchmark || exit

      # Ideal Dispatcher System, if QuestaSim is available
      if [ "$ci" == 0 ]; then
        compile_and_run $kernel "$defines" $tempfile 1                                      || exit
        extract_performance $kernel "$args" $tempfile ${kernel}_${nr_lanes}_ideal.benchmark || exit
        # Verify ID results is non-blocking! Check the report afterwards
        verify_id_results 0 | tee -a ${error_rpt}
      fi
    done
  done
}

##############
## Jacobi2d ##
##############

jacobi2d() {

  kernel=jacobi2d
  defines=""

  tempfile=`mktemp`

  # Log the performance results
  > ${kernel}_${nr_lanes}.benchmark
  > ${kernel}_${nr_lanes}_ideal.benchmark

  for vsize_unpadded in 4 8 16 32 64 128; do
    vsize=$(($vsize_unpadded + 2))

    args="$vsize $vsize"

    clean_and_gen_data $kernel "$args" || exit

    # Default System
    compile_and_run $kernel "$defines" $tempfile 0                                || exit
    extract_performance $kernel "$args" $tempfile ${kernel}_${nr_lanes}.benchmark || exit

    # Ideal Dispatcher System, if QuestaSim is available
    if [ "$ci" == 0 ]; then
      compile_and_run $kernel "$defines" $tempfile 1                                      || exit
      extract_performance $kernel "$args" $tempfile ${kernel}_${nr_lanes}_ideal.benchmark || exit
      # Verify ID results is non-blocking! Check the report afterwards
      verify_id_results 0 | tee -a ${error_rpt}
    fi
  done
}

#############
## DROPOUT ##
#############

dropout() {

  kernel=dropout
  defines=""

  tempfile=`mktemp`

  # Log the performance results
  > ${kernel}_${nr_lanes}.benchmark
  > ${kernel}_${nr_lanes}_ideal.benchmark

  for vsize in 4 8 16 32 64 128 256 512 1024 2048; do

    args="$vsize"

    clean_and_gen_data $kernel "$args" || exit

    # Default System
    compile_and_run $kernel "$defines" $tempfile 0                                || exit
    extract_performance $kernel "$args" $tempfile ${kernel}_${nr_lanes}.benchmark || exit

    # Ideal Dispatcher System, if QuestaSim is available
    if [ "$ci" == 0 ]; then
      compile_and_run $kernel "$defines" $tempfile 1                                      || exit
      extract_performance $kernel "$args" $tempfile ${kernel}_${nr_lanes}_ideal.benchmark || exit
      # Verify ID results is non-blocking! Check the report afterwards
      verify_id_results 0 | tee -a ${error_rpt}
    fi
  done
}

#########
## FFT ##
#########

fft() {

  kernel=fft

  tempfile=`mktemp`

  # Log the performance results
  > ${kernel}_${nr_lanes}.benchmark
  > ${kernel}_${nr_lanes}_ideal.benchmark

  # Type should be in the format "floatXY"
  dtype="float32"
  dbits=${dtype:5:2}

  # 2-lanes and vlen == 4096 cannot contain 256 float32 elements
  for vsize in 4 8 16 32 64 128 $(test $vlen -ge $(( 256 * ${dtype:5:2} )) && echo 256); do

    args="$vsize $dtype"
    defines="-DFFT_SAMPLES=${vsize}"

    clean_and_gen_data $kernel "$args" || exit

    # Default System
    compile_and_run $kernel "$defines" $tempfile 0                                || exit
    extract_performance $kernel "$args" $tempfile ${kernel}_${nr_lanes}.benchmark || exit

    # Ideal Dispatcher System, if QuestaSim is available
    if [ "$ci" == 0 ]; then
      compile_and_run $kernel "$defines" $tempfile 1                                      || exit
      extract_performance $kernel "$args" $tempfile ${kernel}_${nr_lanes}_ideal.benchmark || exit
      # Verify ID results is non-blocking! Check the report afterwards
      verify_id_results 0 | tee -a ${error_rpt}
    fi
  done
}

#########
## DWT ##
#########

dwt() {

  kernel=dwt
  defines=""

  tempfile=`mktemp`

  # Log the performance results
  > ${kernel}_${nr_lanes}.benchmark
  > ${kernel}_${nr_lanes}_ideal.benchmark

  for vsize in 4 8 16 32 64 128 256 512; do

    args="$vsize"

    clean_and_gen_data $kernel "$args" || exit

    # Default System
    compile_and_run $kernel "$defines" $tempfile 0                                || exit
    extract_performance $kernel "$args" $tempfile ${kernel}_${nr_lanes}.benchmark || exit

    # Ideal Dispatcher System, if QuestaSim is available
    if [ "$ci" == 0 ]; then
      compile_and_run $kernel "$defines" $tempfile 1                                      || exit
      extract_performance $kernel "$args" $tempfile ${kernel}_${nr_lanes}_ideal.benchmark || exit
      # Verify ID results is non-blocking! Check the report afterwards
      verify_id_results 0 | tee -a ${error_rpt}
    fi
  done
}

#########
## EXP ##
#########

exp() {

  kernel=exp
  defines=""

  tempfile=`mktemp`

  # Log the performance results
  > ${kernel}_${nr_lanes}.benchmark
  > ${kernel}_${nr_lanes}_ideal.benchmark

  for vsize in 4 8 16 32 64 128 256 512; do

    args="$vsize"

    clean_and_gen_data $kernel "$args" || exit

    # Default System
    compile_and_run $kernel "$defines" $tempfile 0                                || exit
    extract_performance $kernel "$args" $tempfile ${kernel}_${nr_lanes}.benchmark || exit

    # Ideal Dispatcher System, if QuestaSim is available
    if [ "$ci" == 0 ]; then
      compile_and_run $kernel "$defines" $tempfile 1                                      || exit
      extract_performance $kernel "$args" $tempfile ${kernel}_${nr_lanes}_ideal.benchmark || exit
      # Verify ID results is non-blocking! Check the report afterwards
      verify_id_results 0 | tee -a ${error_rpt}
    fi
  done
}

#############
## SOFTMAX ##
#############

softmax() {

  kernel=softmax
  defines=""

  chsize=32

  tempfile=`mktemp`

  # Log the performance results
  > ${kernel}_${nr_lanes}.benchmark
  > ${kernel}_${nr_lanes}_ideal.benchmark

  for insize in 4 8 16 32 64 128 256 512; do

    args="$chsize $insize"

    clean_and_gen_data $kernel "$args" || exit

    # Default System
    compile_and_run $kernel "$defines" $tempfile 0                                || exit
    extract_performance $kernel "$args" $tempfile ${kernel}_${nr_lanes}.benchmark || exit

    # Ideal Dispatcher System, if QuestaSim is available
    if [ "$ci" == 0 ]; then
      compile_and_run $kernel "$defines" $tempfile 1                                      || exit
      extract_performance $kernel "$args" $tempfile ${kernel}_${nr_lanes}_ideal.benchmark || exit
      # Verify ID results is non-blocking! Check the report afterwards
      verify_id_results 0 | tee -a ${error_rpt}
    fi
  done
}

#################
## FDOTPRODUCT ##
#################

fdotproduct() {
  kernel=fdotproduct

  tempfile=`mktemp`

  # Log the performance results
  > ${kernel}_${nr_lanes}.benchmark
  > ${kernel}_${nr_lanes}_ideal.benchmark

  for dtype in double float _Float16; do
    for bsize in 16 32 64 128 256 512 1024 2048 4096; do

      sew=$(sew_from_dtype $dtype)

      args="$bsize"
      defines="-Ddtype=${dtype}"

      clean_and_gen_data $kernel "$args" || exit

      # Default System
      compile_and_run $kernel "$defines" $tempfile 0                                           || exit
      extract_performance_dotp $kernel "$args" $sew $tempfile ${kernel}_${nr_lanes}.benchmark  || exit

      # Ideal Dispatcher System, if QuestaSim is available
      if [ "$ci" == 0 ]; then
        compile_and_run $kernel "$defines" $tempfile 1                                                || exit
        extract_performance_dotp $kernel "$args" $sew $tempfile ${kernel}_${nr_lanes}_ideal.benchmark || exit
        # Verify ID results is non-blocking! Check the report afterwards
        verify_id_results 0 | tee -a ${error_rpt}
      fi
    done
  done
}

################
## DOTPRODUCT ##
################

dotproduct() {

  kernel=dotproduct

  tempfile=`mktemp`

  # Log the performance results
  > ${kernel}_${nr_lanes}.benchmark
  > ${kernel}_${nr_lanes}_ideal.benchmark

  for dtype in int64_t int32_t int16_t int8_t; do
    for bsize in 16 32 64 128 256 512 1024 2048 4096; do

      sew=$(sew_from_dtype $dtype)

      args="$bsize"
      defines="-Ddtype=${dtype}"

      clean_and_gen_data $kernel "$args" || exit

      # Default System
      compile_and_run $kernel "$defines" $tempfile 0                                           || exit
      extract_performance_dotp $kernel "$args" $sew $tempfile ${kernel}_${nr_lanes}.benchmark  || exit

      # Ideal Dispatcher System, if QuestaSim is available
      if [ "$ci" == 0 ]; then
        compile_and_run $kernel "$defines" $tempfile 1                                                || exit
        extract_performance_dotp $kernel "$args" $sew $tempfile ${kernel}_${nr_lanes}_ideal.benchmark || exit
        # Verify ID results is non-blocking! Check the report afterwards
        verify_id_results 0 | tee -a ${error_rpt}
      fi
    done
  done
}

################
## PATHFINDER ##
################

pathfinder() {

  kernel=pathfinder
  defines=""

  runs=1

  tempfile=`mktemp`

  # Log the performance results
  > ${kernel}_${nr_lanes}.benchmark
  > ${kernel}_${nr_lanes}_ideal.benchmark

  for cols in 4 8 16 32 64 128 256 512 1024; do
    for rows in 64; do

      args="$runs $cols $rows"

      clean_and_gen_data $kernel "$args" || exit

      # Default System
      compile_and_run $kernel "$defines" $tempfile 0                                || exit
      extract_performance $kernel "$args" $tempfile ${kernel}_${nr_lanes}.benchmark || exit

      # Ideal Dispatcher System, if QuestaSim is available
      if [ "$ci" == 0 ]; then
        compile_and_run $kernel "$defines" $tempfile 1                                      || exit
        extract_performance $kernel "$args" $tempfile ${kernel}_${nr_lanes}_ideal.benchmark || exit
        # Verify ID results is non-blocking! Check the report afterwards
        verify_id_results 0 | tee -a ${error_rpt}
      fi
    done
  done
}

###############
## ROI-ALIGN ##
###############

roi_align() {

  kernel=roi_align
  defines=""

  batch_size=1
  height=16
  width=16
  n_boxes=4
  crop_h=4
  crop_w=4

  tempfile=`mktemp`

  # Log the performance results
  > ${kernel}_${nr_lanes}.benchmark
  > ${kernel}_${nr_lanes}_ideal.benchmark

  for depth in 4 8 16 32 64 128 256 512; do

    args="$batch_size $depth $height $width $n_boxes $crop_h $crop_w"

    clean_and_gen_data $kernel "$args" || exit

    # Default System
    compile_and_run $kernel "$defines" $tempfile 0                                || exit
    extract_performance $kernel "$args" $tempfile ${kernel}_${nr_lanes}.benchmark || exit

    # Ideal Dispatcher System, if QuestaSim is available
    if [ "$ci" == 0 ]; then
      compile_and_run $kernel "$defines" $tempfile 1                                      || exit
      extract_performance $kernel "$args" $tempfile ${kernel}_${nr_lanes}_ideal.benchmark || exit
      # Verify ID results is non-blocking! Check the report afterwards
      verify_id_results 0 | tee -a ${error_rpt}
    fi
  done
}

case $1 in
  "imatmul" | "fmatmul")
    matmul $1
    ;;

  "iconv2d" | "fconv2d")
    conv2d $1
    ;;

  "fconv3d")
    fconv3d
    ;;

  "jacobi2d")
    jacobi2d
    ;;

  "dropout")
    dropout
    ;;

  "fft")
    fft
    ;;

  "dwt")
    dwt
    ;;

  "exp")
    exp
    ;;

  "softmax")
    softmax
    ;;

  "fdotproduct")
    fdotproduct
    ;;

  "dotproduct")
    dotproduct
    ;;

  "pathfinder")
    pathfinder
    ;;

  "roi_align")
    roi_align
    ;;

  *)
    echo "Benchmarking all the apps."
    matmul imatmul
    matmul fmatmul
    conv2d iconv2d
    conv2d fconv2d
    fconv3d
    jacobi2d
    dropout
    fft
    dwt
    exp
    softmax
    fdotproduct
    dotproduct
    pathfinder
    roi_align
    ;;
esac
