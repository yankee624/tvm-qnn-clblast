# CLBlast Bandwidth Test

A benchmark tool for testing OpenCL matrix multiplication kernel performance using CLBlast-optimized kernels.

## Overview

This project benchmarks GPU matrix multiplication performance by running optimized OpenCL kernels with various parameter configurations. It measures GPU latency and provides statistics over multiple runs.

## Features

- Multiple kernel parameter configurations (7 predefined sets)
- Configurable matrix dimensions
- Asynchronous kernel execution with event-based profiling
- GPU latency measurement and statistics
- Android build support

## Requirements

- OpenCL SDK (1.2 or higher)
- CMake 3.20 or higher
- C++17 compatible compiler
- For Android builds: Android NDK

## Building

### Linux/Desktop

```bash
mkdir build
cd build
cmake ..
cmake --build .
```

### Android

```bash
export ANDROID_NDK_HOME=/path/to/android-ndk
sh build-android.sh
```

The Android build script requires:
- `ANDROID_NDK_HOME` environment variable set
- OpenCL libraries at `$HOME/opt/opencl/s25/lib/libOpenCL.so`
- OpenCL headers at `$HOME/opt/opencl/s25/include`

## Usage

```bash
./clblast_bw_test <index> [<num_runs>] [<m> <n> <k>]
```

### Arguments

- `index` (required): Parameter set index (0-6)
  - Selects from 7 predefined kernel parameter configurations
- `num_runs` (optional, default: 1): Number of times to run the kernel
- `m` (optional, default: 1024): Matrix M dimension
- `n` (optional, default: 1024): Matrix N dimension  
- `k` (optional, default: 1024): Matrix K dimension

### Examples

```bash
# Run with default settings (index 0, 1 run, 1024x1024x1024)
./clblast_bw_test 0

# Run 10 times with default dimensions
./clblast_bw_test 0 10

# Run with custom dimensions
./clblast_bw_test 0 512 256 128

# Run 5 times with custom dimensions
./clblast_bw_test 0 5 512 256 128
```

## Output

The program outputs:
- Parameter set information
- Matrix dimensions
- Per-run GPU latency (in milliseconds and microseconds)
- Statistics (when num_runs > 1):
  - Average latency
  - Minimum latency
  - Maximum latency

Example output:
```
Using parameter set 0
Matrix dimensions: M=1024, N=1024, K=1024
Queuing kernel orchestra_main 5 time(s) with dimensions M=1024, N=1024, K=1024
All kernels queued. Waiting for completion...
Run 1/5 - GPU Latency: 2.345 ms (2345.67 us)
Run 2/5 - GPU Latency: 2.301 ms (2301.23 us)
...

Statistics over 5 runs:
  Average: 2.325 ms
  Min:     2.301 ms
  Max:     2.345 ms
```

## Parameter Sets

The project includes 7 predefined parameter sets (indices 0-6) with different kernel tuning parameters:
- Workgroup sizes (MWG, NWG, KWG)
- Thread dimensions (MDIMC, NDIMC, MDIMA, NDIMB)
- Vector widths (VWM, VWN)
- Local memory usage (SA, SB)
- Other optimization flags

## Project Structure

```
.
├── main.cc                 # Main benchmark program
├── CMakeLists.txt          # CMake build configuration
├── build-android.sh       # Android build script
├── include/
│   ├── kernel.cl          # OpenCL kernel source
│   └── kernel_source.h    # Kernel source header wrapper
└── cmake/
    └── FindOpenCL.cmake   # OpenCL find module
```

## Kernel Details

The benchmark uses the `orchestra_main` kernel from CLBlast, which performs matrix multiplication:
- C = alpha * A * B + beta * C
- Supports single precision (float)
- Highly optimized with configurable parameters

## Notes

- Kernels are queued asynchronously for better GPU utilization
- GPU timing uses OpenCL profiling events for accurate measurement
- Results are read back synchronously after all kernels complete

