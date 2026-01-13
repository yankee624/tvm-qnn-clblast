#!/bin/bash

set -e pipefail

# allow conda activate command in shell script
source "$(conda info --base)/etc/profile.d/conda.sh"
conda activate qnn

source /opt/qairt/2.40.0.251030/bin/envsetup.sh

export QNN_TARGET_ARCH_AND_OS="aarch64-android"
export HOST_ARCH="x86_64-linux-clang"

export QNN_INCLUDE="${QNN_SDK_ROOT}/include/QNN"
export HEXAGON_SDK_ROOT="/local/mnt/workspace/Qualcomm/Hexagon_SDK/6.3.0.0"
export HEXAGON_VERSION="79"
export QNN_TARGET_DEST=/data/local/tmp/qnn

# Need to modify /opt/qairt/2.40.0.251030/examples/QNN/OpPackage/HTP/Makefile a bit before running make
cp QNN_OpPackage_HTP_Makefile /opt/qairt/2.40.0.251030/examples/QNN/OpPackage/HTP/Makefile
# Build the op package used by HTP backend (only once)
pushd ${QNN_SDK_ROOT}/examples/QNN/OpPackage/HTP
make htp_v${HEXAGON_VERSION}
export QNN_OP_PACKAGE="${QNN_SDK_ROOT}/examples/QNN/OpPackage/HTP/build/hexagon-v${HEXAGON_VERSION}/libQnnHtpOpPackageExample.so"
popd

MODEL_ROOT="$(pwd)/model"
mkdir -p "$MODEL_ROOT"

SIZE_ARR=(
  # "257x1024x3072" # clip L14 qkv fuse
  # "257x1024x4096" # clip L14 up projection
  # "197x768x2304" # clip B16 qkv fuse
  # "197x768x3072" # clip B16 up projection
  "1x1024x4096" # internvl3.5-1b qkv fuse
  "1x1024x3072" # internvl3.5-1b up projection
  # "1x1536x2048" # qwen2-vl-2b qkv fuse
  # "1x1536x8960" # qwen2-vl-2b up projection
  # "257x4096x4096" # large matmul test
)

echo "Preparing matmul QNN models for sizes: ${SIZE_ARR[*]}"

# Keep track of size dirs for pushing later
SIZE_DIRS=()
for size in "${SIZE_ARR[@]}"; do
  # expect format MxKxN
  if [[ ! "$size" =~ ^[0-9]+x[0-9]+x[0-9]+$ ]]; then
    echo "Skipping invalid size entry: $size"
    continue
  fi
  M=${size%%x*}
  rest=${size#*x}
  K=${rest%%x*}
  N=${rest#*x}

  size_dir="matmul_${M}x${K}x${N}"
  echo "-- Generating size $size -> $size_dir"
  rm -rf "$MODEL_ROOT/$size_dir"
  mkdir -p "$MODEL_ROOT/$size_dir"
  pushd "$MODEL_ROOT/$size_dir" >/dev/null

  # make model file and input (raw) file in this size directory
  python3 "$MODEL_ROOT/make_matmul_torch.py" "$M" "$K" "$N"

  # prepare input_list.txt for qnn-pytorch-converter (single input case)
  cat > input_list.txt <<EOF
./input_0.raw
EOF

  # convert to QNN model
  $QNN_SDK_ROOT/bin/x86_64-linux-clang/qnn-pytorch-converter \
    --input_network ./matmul.pt \
    --input_dim "x" $M,$K \
    --input_list ./input_list.txt \
    --output_path ./matmul_qnn.cpp \
    --weights_bitwidth 8 \
    --act_bitwidth 8

  # generate model libs for target and host (placed inside this size_dir/model_libs)
  # Before running this, make sure ANDROID_NDK_ROOT is included in PATH
  python3 "${QNN_SDK_ROOT}/bin/x86_64-linux-clang/qnn-model-lib-generator" \
      -c "matmul_qnn.cpp" \
      -b "matmul_qnn.bin" \
      -o "./model_libs" \
      -t ${QNN_TARGET_ARCH_AND_OS}
  python3 "${QNN_SDK_ROOT}/bin/x86_64-linux-clang/qnn-model-lib-generator" \
      -c "matmul_qnn.cpp" \
      -b "matmul_qnn.bin" \
      -o "./model_libs" \
      -t ${HOST_ARCH}

  QNN_MODEL_PATH=$(realpath ./model_libs/$QNN_TARGET_ARCH_AND_OS/libmatmul_qnn.so)

  # Create input_list_target and env vars that are specific to this size dir on device
  echo "${QNN_TARGET_DEST}/${size_dir}/input_0.raw" > input_list_target.txt
  cat > target_env_vars.env <<EOF
export QNN_INPUT_LIST=${QNN_TARGET_DEST}/${size_dir}/input_list_target.txt
export QNN_MODEL_PATH=${QNN_TARGET_DEST}/${size_dir}/${QNN_MODEL_PATH##*/}
export QNN_OP_PACKAGE=${QNN_TARGET_DEST}/${QNN_OP_PACKAGE##*/}
EOF

  popd >/dev/null

  SIZE_DIRS+=("$size_dir")
done

# Ensure remote base dir exists
adb shell "mkdir -p $QNN_TARGET_DEST"

# Push each size directory to the device under $QNN_TARGET_DEST/<size_dir>
for dir in "${SIZE_DIRS[@]}"; do
  echo "Pushing $dir -> $QNN_TARGET_DEST/"
  adb push "$MODEL_ROOT/$dir" "$QNN_TARGET_DEST/"
  # push the generated input_list_target and env file into the remote dir
  adb push "$MODEL_ROOT/$dir/input_list_target.txt" "$QNN_TARGET_DEST/$dir/"
  adb push "$MODEL_ROOT/$dir/target_env_vars.env" "$QNN_TARGET_DEST/$dir/"
  # push model lib
  adb push "$MODEL_ROOT/$dir/model_libs/$QNN_TARGET_ARCH_AND_OS/libmatmul_qnn.so" "$QNN_TARGET_DEST/$dir/"
done

# Push common runtime pieces once
adb push "${QNN_SDK_ROOT}/lib/${QNN_TARGET_ARCH_AND_OS}/libQnnHtp.so" "$QNN_TARGET_DEST/"
adb push "${QNN_SDK_ROOT}/lib/${QNN_TARGET_ARCH_AND_OS}/libQnnCpu.so" "$QNN_TARGET_DEST/"
adb push "${QNN_SDK_ROOT}/lib/${QNN_TARGET_ARCH_AND_OS}/libQnnGpu.so" "$QNN_TARGET_DEST/"
adb push "${QNN_SDK_ROOT}/lib/${QNN_TARGET_ARCH_AND_OS}/libQnnDsp.so" "$QNN_TARGET_DEST/"
adb push "${QNN_SDK_ROOT}/lib/${QNN_TARGET_ARCH_AND_OS}/libQnnHtpPrepare.so" "$QNN_TARGET_DEST/"
adb push ${QNN_SDK_ROOT}/lib/${QNN_TARGET_ARCH_AND_OS}/libQnnHtpV${HEXAGON_VERSION}* "$QNN_TARGET_DEST/"
adb push $QNN_SDK_ROOT/lib/hexagon-v${HEXAGON_VERSION}/unsigned/* "$QNN_TARGET_DEST/"

# push qnn-net-run binary into /data/local/tmp/qnn (sample app launcher)
adb push "${QNN_SDK_ROOT}/bin/$QNN_TARGET_ARCH_AND_OS/qnn-net-run" /data/local/tmp/qnn/


# run example
RUN_DIR="/data/local/tmp/qnn/matmul_${SIZE_ARR[0]}"
adb shell "cd $RUN_DIR && \
  LD_LIBRARY_PATH=.. ADSP_LIBRARY_PATH=.. \
  ../qnn-net-run --backend ../libQnnHtp.so --model ./libmatmul_qnn.so \
    --input_list ./input_list_target.txt --profiling_level detailed \
    --num_inferences 100 --output_dir ./out_htp"

adb pull $RUN_DIR/out_htp/qnn-profiling-data_0.log ./
/opt/qairt/2.40.0.251030/bin/x86_64-linux-clang/qnn-profile-viewer \
  --input_log qnn-profiling-data_0.log
rm qnn-profiling-data_0.log