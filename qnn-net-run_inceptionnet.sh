#!/bin/bash

source /opt/qairt/2.40.0.251030/bin/envsetup.sh

export HOST_ARCH="x86_64-linux-clang"
export QNN_TARGET_ARCH="aarch64-android"

tensorflowLocation=$(python -m pip show tensorflow | grep '^Location: ' | awk '{print $2}')
export TENSORFLOW_HOME="$tensorflowLocation/tensorflow"
echo "export TENSORFLOW_HOME=$tensorflowLocation/tensorflow" >> ~/.profile

python3 ${QNN_SDK_ROOT}/examples/Models/InceptionV3/scripts/setup_inceptionv3.py -a ~/tmpdir -d

# Quantized model conversion
python ${QNN_SDK_ROOT}/bin/x86_64-linux-clang/qnn-tensorflow-converter \
  --input_network "${QNN_SDK_ROOT}/examples/Models/InceptionV3/tensorflow/inception_v3_2016_08_28_frozen.pb" \
  --input_dim input 1,299,299,3 \
  --input_list "${QNN_SDK_ROOT}/examples/Models/InceptionV3/data/cropped/raw_list.txt" \
  --out_node "InceptionV3/Predictions/Reshape_1" \
  --output_path "${QNN_SDK_ROOT}/examples/Models/InceptionV3/model/Inception_v3.cpp"

mkdir -p /tmp/qnn_tmp
cd /tmp/qnn_tmp
cp "${QNN_SDK_ROOT}/examples/Models/InceptionV3/model/Inception_v3.cpp" "${QNN_SDK_ROOT}/examples/Models/InceptionV3/model/Inception_v3.bin"  /tmp/qnn_tmp/
# for android
python3 "${QNN_SDK_ROOT}/bin/x86_64-linux-clang/qnn-model-lib-generator" \
    -c "Inception_v3.cpp" \
    -b "Inception_v3.bin" \
    -o model_libs \
    -t ${QNN_TARGET_ARCH}
# for host
python3 "${QNN_SDK_ROOT}/bin/x86_64-linux-clang/qnn-model-lib-generator" \
    -c "Inception_v3.cpp" \
    -b "Inception_v3.bin" \
    -o model_libs \
    -t ${HOST_ARCH}


adb shell "mkdir -p /data/local/tmp/inception_v3"
adb push ${QNN_SDK_ROOT}/lib/${QNN_TARGET_ARCH}/libQnnCpu.so /data/local/tmp/inception_v3
adb push /tmp/qnn_tmp/model_libs/aarch64-android/libInception_v3.so /data/local/tmp/inception_v3


# CPU
adb push "${QNN_SDK_ROOT}/examples/Models/InceptionV3/data/cropped"  /data/local/tmp/inception_v3
adb push "${QNN_SDK_ROOT}/examples/Models/InceptionV3/data/target_raw_list.txt"  /data/local/tmp/inception_v3
adb push "${QNN_SDK_ROOT}/examples/Models/InceptionV3/data/imagenet_slim_labels.txt"  /data/local/tmp/inception_v3
adb push "${QNN_SDK_ROOT}/examples/Models/InceptionV3/scripts/show_inceptionv3_classifications.py"  /data/local/tmp/inception_v3
adb push "${QNN_SDK_ROOT}/bin/$QNN_TARGET_ARCH/qnn-net-run" /data/local/tmp/inception_v3/qnn-net-run

adb shell "cd /data/local/tmp/inception_v3 && ./qnn-net-run \
  --model ./libInception_v3.so \
  --input_list ./target_raw_list.txt \
  --backend ./libQnnCpu.so \
  --output_dir ./output"

adb pull /data/local/tmp/inception_v3/output ./output

python3 "${QNN_SDK_ROOT}/examples/Models/InceptionV3/scripts/show_inceptionv3_classifications.py" \
    -i "${QNN_SDK_ROOT}/examples/Models/InceptionV3/data/target_raw_list.txt" \
    -o "output" \
    -l "${QNN_SDK_ROOT}/examples/Models/InceptionV3/data/imagenet_slim_labels.txt"



# HTP
"$QNN_SDK_ROOT/bin/${HOST_ARCH}/qnn-context-binary-generator" \
    --backend "${QNN_SDK_ROOT}/lib/${HOST_ARCH}/libQnnHtp.so" \
    --model "/tmp/qnn_tmp/model_libs/${HOST_ARCH}/libInception_v3.so" \
    --binary_file "libInception_v3.serialized" \
    --config_file /workspaces/tvmqnn/backend_extensions.json

HTP_VERSION="79"
HTP_ARCH="hexagon-v${HTP_VERSION}"
adb push ${QNN_SDK_ROOT}/lib/${QNN_TARGET_ARCH}/libQnnHtp.so /data/local/tmp/inception_v3
adb push ${QNN_SDK_ROOT}/lib/${HTP_ARCH}/unsigned/* /data/local/tmp/inception_v3
adb push ${QNN_SDK_ROOT}/lib/${QNN_TARGET_ARCH}/libQnnHtpV${HTP_VERSION}Stub.so /data/local/tmp/inception_v3
adb push /tmp/qnn_tmp/output/libInception_v3.serialized.bin /data/local/tmp/inception_v3/Inception_v3.serialized.bin

adb push /tmp/qnn_tmp/model_libs/${QNN_TARGET_ARCH}/libInception_v3.so /data/local/tmp/inception_v3

adb push "${QNN_SDK_ROOT}/examples/Models/InceptionV3/data/cropped"  /data/local/tmp/inception_v3
adb push "${QNN_SDK_ROOT}/examples/Models/InceptionV3/data/target_raw_list.txt"  /data/local/tmp/inception_v3
adb push "${QNN_SDK_ROOT}/examples/Models/InceptionV3/data/imagenet_slim_labels.txt"  /data/local/tmp/inception_v3
adb push "${QNN_SDK_ROOT}/examples/Models/InceptionV3/scripts/show_inceptionv3_classifications.py"  /data/local/tmp/inception_v3
adb push "${QNN_SDK_ROOT}/bin/$QNN_TARGET_ARCH/qnn-net-run" /data/local/tmp/inception_v3/qnn-net-run

adb push /workspaces/tvmqnn/backend_extensions.json \
  /data/local/tmp/inception_v3/backend_extensions.json
adb shell "cd /data/local/tmp/inception_v3 && \
  LD_LIBRARY_PATH=/data/local/tmp/inception_v3 ADSP_LIBRARY_PATH=/data/local/tmp/inception_v3 \
  ./qnn-net-run \
  --backend ./libQnnHtp.so \
  --input_list ./target_raw_list.txt \
  --retrieve_context ./Inception_v3.serialized.bin \
  --output_dir ./output_htp \
  --profiling_level backend \
  --config_file ./backend_extensions.json"

adb pull /data/local/tmp/inception_v3/output_htp ./
python3 "${QNN_SDK_ROOT}/examples/Models/InceptionV3/scripts/show_inceptionv3_classifications.py" \
    -i "${QNN_SDK_ROOT}/examples/Models/InceptionV3/data/target_raw_list.txt" \
    -o "output_htp" \
    -l "${QNN_SDK_ROOT}/examples/Models/InceptionV3/data/imagenet_slim_labels.txt"



