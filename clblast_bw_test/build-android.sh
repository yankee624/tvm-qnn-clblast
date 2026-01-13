#!/bin/bash

set -e

BUILD_TYPE=Release

rm -r build-android || true

WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cmake -GNinja -Bbuild-android \
  -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake \
  -DANDROID_ABI=arm64-v8a \
  -DOPENCL_LIBRARIES=$WORKSPACE_DIR/clblast_bw_test/libOpenCL.so \
  -DOPENCL_INCLUDE_DIRS=$WORKSPACE_DIR/clblast_bw_test/OpenCL-Headers/ \
  -DCMAKE_BUILD_TYPE=$BUILD_TYPE \
  .

cmake --build build-android

adb push ./build-android/clblast_bw_test /data/local/tmp
adb shell "/data/local/tmp/clblast_bw_test 4 100 1024 1024 1024"
