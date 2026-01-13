#!/bin/bash

set -e

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


cd ${QNN_SDK_ROOT}/examples/QNN/OpPackage/HTP
# Need to modify /opt/qairt/2.40.0.251030/examples/QNN/OpPackage/HTP/Makefile a bit before running make
make htp_v${HEXAGON_VERSION}
export QNN_OP_PACKAGE="${QNN_SDK_ROOT}/examples/QNN/OpPackage/HTP/build/hexagon-v${HEXAGON_VERSION}/libQnnHtpOpPackageExample.so"


cd /workspaces/tvmqnn/model
# make model file and input (raw) file
M=${1:-256}
K=${2:-4096}
N=${3:-4096}
python make_matmul_torch.py $M $K $N

# Move input to a specific folder to avoid pushing everything
INPUT_DIR="matmul_${M}x${K}x${N}"
mkdir -p "$INPUT_DIR"
mv input_0.raw "$INPUT_DIR/"

# prepare input_list.txt for qnn-pytorch-converter
cat > input_list.txt <<EOF
${INPUT_DIR}/input_0.raw
EOF
# convert to QNN model
$QNN_SDK_ROOT/bin/x86_64-linux-clang/qnn-pytorch-converter \
  --input_network ./matmul.pt \
  --input_dim "x" $M,$K \
  --input_list ./input_list.txt \
  --output_path ./matmul_qnn.cpp \
  --weights_bitwidth 8 \
  --act_bitwidth 8 \

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
QNN_MODEL_PATH_HOST=$(realpath ./model_libs/$HOST_ARCH/libmatmul_qnn.so)


if [ ! -f "${QNN_SDK_ROOT}/examples/QNN/SampleApp/SampleApp/bin/${QNN_TARGET_ARCH_AND_OS}/qnn-sample-app" ]; then
  cd ${QNN_SDK_ROOT}/examples/QNN/SampleApp/SampleApp
  make all_android
fi

cd /workspaces/tvmqnn/model
awk -F'/' -v dest="$QNN_TARGET_DEST" '{print dest "/" $(NF-1) "/" $NF}' input_list.txt > input_list_target.txt
echo "export QNN_INPUT_LIST=${QNN_TARGET_DEST}/input_list_target.txt" > ./target_env_vars.env
echo "export QNN_SAMPLE_APP=${QNN_TARGET_DEST}/qnn-sample-app" >> ./target_env_vars.env
echo "export QNN_MODEL_PATH=${QNN_TARGET_DEST}/${QNN_MODEL_PATH##*/}" >> ./target_env_vars.env
echo "export QNN_OP_PACKAGE=${QNN_TARGET_DEST}/${QNN_OP_PACKAGE##*/}" >> ./target_env_vars.env

adb shell "mkdir -p $QNN_TARGET_DEST"

for dir in $(awk -F'/' '{print $(NF-1)}' input_list_target.txt | sort -u); do
  adb push "$dir" "$QNN_TARGET_DEST/"
done
adb push input_list_target.txt "$QNN_TARGET_DEST/"
adb push target_env_vars.env "$QNN_TARGET_DEST/"

adb push "${QNN_SDK_ROOT}/examples/QNN/SampleApp/SampleApp/bin/${QNN_TARGET_ARCH_AND_OS}/qnn-sample-app" "$QNN_TARGET_DEST/"
adb push "${QNN_SDK_ROOT}/lib/${QNN_TARGET_ARCH_AND_OS}/libQnnHtp.so" "$QNN_TARGET_DEST/"
adb push "${QNN_SDK_ROOT}/lib/${QNN_TARGET_ARCH_AND_OS}/libQnnCpu.so" "$QNN_TARGET_DEST/"
adb push "${QNN_SDK_ROOT}/lib/${QNN_TARGET_ARCH_AND_OS}/libQnnGpu.so" "$QNN_TARGET_DEST/"
adb push "${QNN_SDK_ROOT}/lib/${QNN_TARGET_ARCH_AND_OS}/libQnnDsp.so" "$QNN_TARGET_DEST/"
adb push "${QNN_SDK_ROOT}/lib/${QNN_TARGET_ARCH_AND_OS}/libQnnHtpPrepare.so" "$QNN_TARGET_DEST/"
adb push ${QNN_SDK_ROOT}/lib/${QNN_TARGET_ARCH_AND_OS}/libQnnHtpV${HEXAGON_VERSION}* "$QNN_TARGET_DEST/"
adb push $QNN_SDK_ROOT/lib/hexagon-v${HEXAGON_VERSION}/unsigned/* "$QNN_TARGET_DEST/"

adb push "${QNN_MODEL_PATH}" "$QNN_TARGET_DEST/"
adb push "${QNN_OP_PACKAGE}" "$QNN_TARGET_DEST/"

"$QNN_SDK_ROOT/bin/${HOST_ARCH}/qnn-context-binary-generator" \
    --backend "${QNN_SDK_ROOT}/lib/${HOST_ARCH}/libQnnHtp.so" \
    --model ${QNN_MODEL_PATH_HOST} \
    --binary_file "matmul_qnn.serialized" \
    --output_dir "./" \
    --profiling_level "detailed"
adb push ./matmul_qnn.serialized.bin $QNN_TARGET_DEST

# adb shell "cd $QNN_TARGET_DEST && \
#   source ./target_env_vars.env && \
#   LD_LIBRARY_PATH=. ADSP_LIBRARY_PATH=. \
#   ./qnn-sample-app \
#     --backend ./libQnnHtp.so \
#     --retrieve_context /data/local/tmp/qnn/matmul_qnn.serialized.bin \
#     --input_list \$QNN_INPUT_LIST \
#     --profiling_level detailed \
#     --serialize_profile_logs \
#     --system_library ./libQnnSystem.so \
#     --num_inferences 10 \
#     "
# adb pull $QNN_TARGET_DEST/output/qnn-sample-app-profiling-data.log ./out_htp/
# $QNN_SDK_ROOT/bin/x86_64-linux-clang/qnn-profile-viewer \
#   --input_log out_htp/qnn-sample-app-profiling-data.log \
#   --reader $QNN_SDK_ROOT/lib/${HOST_ARCH}/libQnnHtpOptraceProfilingReader.so \
#   --output out

# adb shell "cd $QNN_TARGET_DEST && \
#   source ./target_env_vars.env && \
#   LD_LIBRARY_PATH=. ADSP_LIBRARY_PATH=. \
#   ./qnn-sample-app \
#     --backend ./libQnnHtp.so \
#     --model \$QNN_MODEL_PATH \
#     --input_list \$QNN_INPUT_LIST \
#     --profiling_level detailed \
#     --num_inferences 10 \
#     "

### qnn-net-run
adb push "${QNN_SDK_ROOT}/bin/$QNN_TARGET_ARCH_AND_OS/qnn-net-run" /data/local/tmp/qnn/

adb shell "cd $QNN_TARGET_DEST && \
  LD_LIBRARY_PATH=. ADSP_LIBRARY_PATH=. \
  ./qnn-net-run \
    --backend ./libQnnHtp.so \
    --model ./libmatmul_qnn.so \
    --input_list ./input_list_target.txt \
    --profiling_level client \
    --num_inferences 100 \
    --output_dir ./out_htp"

adb pull $QNN_TARGET_DEST/out_htp/qnn-profiling-data_0.log ./
$QNN_SDK_ROOT/bin/x86_64-linux-clang/qnn-profile-viewer \
  --input_log qnn-profiling-data_0.log




