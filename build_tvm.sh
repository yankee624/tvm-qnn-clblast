#!/bin/bash

set -e

# allow conda activate command in shell script
source "$(conda info --base)/etc/profile.d/conda.sh"

### Build TVM

# full linux build
# conda env remove -n tvm-build-venv
conda create -n tvm-build-venv -y -c conda-forge \
    "llvmdev>=15" \
    "cmake>=3.24" \
    git \
    python=3.11
conda activate tvm-build-venv

git clone --recursive https://github.com/apache/tvm tvm

cd tvm
mkdir -p build && cd build
cmake .. \
  -DUSE_LLVM="$(which llvm-config)" \
  -DUSE_LLVM_RTTI=ON \
  -G "Ninja"
cmake --build . --parallel 40

cd ../3rdparty/tvm-ffi; pip install .; cd ../..
pip install python/

pip install numpy psutil tornado cloudpickle

WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export TVM_LIBRARY_PATH=${WORKSPACE_DIR}/tvm/build
export TVM_NDK_CC="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android21-clang++"


# android build
mkdir -p build-android && cd build-android
cmake .. \
  -DCMAKE_BUILD_TYPE=Release \
  -DUSE_CPP_RPC=ON \
  -DTVM_FFI_USE_LIBBACKTRACE=OFF \
  -DCMAKE_TOOLCHAIN_FILE=${ANDROID_NDK_HOME}/build/cmake/android.toolchain.cmake \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM=android-30
cmake --build . --parallel 40 --target tvm_runtime tvm_rpc

adb push libtvm_runtime.so /data/local/tmp/
adb push tvm_rpc /data/local/tmp/
adb push lib/libtvm_ffi.so /data/local/tmp/
adb push \
  ${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so \
  /data/local/tmp/

cd ..
