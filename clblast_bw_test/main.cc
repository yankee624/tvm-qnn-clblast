#include "kernel_source.h"
#include <CL/cl.h>
#include <cstring>
#include <iostream>
#include <vector>

std::vector<std::vector<int>> params = {
    {0, 64, 64, 32, 16, 8, 16, 8, 2, 4, 2, 0, 0, 0, 0, 1},
    {0, 64, 64, 32, 16, 8, 16, 8, 2, 4, 1, 0, 0, 0, 0, 1},
    {0, 64, 64, 32, 16, 8, 16, 8, 2, 4, 4, 0, 0, 1, 1, 1},
    {0, 64, 64, 32, 16, 8, 16, 8, 2, 4, 1, 0, 0, 1, 1, 1},
    {0, 64, 64, 32, 16, 8, 16, 8, 2, 1, 4, 0, 0, 1, 1, 1},
    {0, 64, 64, 32, 16, 8, 16, 8, 2, 1, 2, 0, 0, 1, 1, 1},
    {0, 64, 64, 32, 16, 8, 16, 8, 2, 4, 2, 0, 0, 1, 1, 1},
};

std::vector<std::vector<unsigned long>> dims = {
    {16, 8, 256, 128}, {16, 8, 256, 128}, {16, 8, 256, 128}, {16, 8, 256, 128},
    {16, 8, 256, 128}, {16, 8, 256, 128}, {16, 8, 256, 128},
};

#define CHECK_CL_ERROR(err, msg)                                               \
  if (err != CL_SUCCESS) {                                                     \
    std::cerr << "Error: " << msg << " (code: " << err << ")" << std::endl;    \
    return err;                                                                \
  }

cl_int test_clblast_bw(int index, int M, int N, int K, int num_runs) {
  cl_int err;
  cl_platform_id platform;
  cl_device_id device;
  cl_context context;
  cl_command_queue queue;
  cl_program program;
  cl_kernel kernel;

  // Get platform
  err = clGetPlatformIDs(1, &platform, nullptr);
  CHECK_CL_ERROR(err, "Failed to get platform");

  // Get device
  err = clGetDeviceIDs(platform, CL_DEVICE_TYPE_GPU, 1, &device, nullptr);
  if (err != CL_SUCCESS) {
    // Fallback to CPU if GPU not available
    err = clGetDeviceIDs(platform, CL_DEVICE_TYPE_CPU, 1, &device, nullptr);
    CHECK_CL_ERROR(err, "Failed to get device");
  }

  // Create context
  context = clCreateContext(nullptr, 1, &device, nullptr, nullptr, &err);
  CHECK_CL_ERROR(err, "Failed to create context");

  // Create command queue with profiling enabled
  // Try OpenCL 2.0+ API first, fallback to 1.2 API
  #ifdef CL_VERSION_2_0
    cl_queue_properties queue_props[] = {CL_QUEUE_PROPERTIES, CL_QUEUE_PROFILING_ENABLE, 0};
    queue = clCreateCommandQueueWithProperties(context, device, queue_props, &err);
  #else
    queue = clCreateCommandQueue(context, device, CL_QUEUE_PROFILING_ENABLE, &err);
  #endif
  CHECK_CL_ERROR(err, "Failed to create command queue");

  // Kernel source is included from header
  const char *kernel_str = kernel_source;
  size_t kernel_len = strlen(kernel_source);

  // Create program
  program =
      clCreateProgramWithSource(context, 1, &kernel_str, &kernel_len, &err);
  CHECK_CL_ERROR(err, "Failed to create program");

  // Build program with PRECISION=32 (single precision)

  std::string build_options = "-DGEMMK=" + std::to_string(params[index][0]) + " " +
                              "-DMWG=" + std::to_string(params[index][1]) + " " +
                              "-DNWG=" + std::to_string(params[index][2]) + " " +
                              "-DKWG=" + std::to_string(params[index][3]) + " " +
                              "-DMDIMC=" + std::to_string(params[index][4]) + " " +
                              "-DNDIMC=" + std::to_string(params[index][5]) + " " +
                              "-DMDIMA=" + std::to_string(params[index][6]) + " " +
                              "-DNDIMB=" + std::to_string(params[index][7]) + " " +
                              "-DKWI=" + std::to_string(params[index][8]) + " " +
                              "-DVWM=" + std::to_string(params[index][9]) + " " +
                              "-DVWN=" + std::to_string(params[index][10]) + " " +
                              "-DSTRM=" + std::to_string(params[index][11]) + " " +
                              "-DSTRN=" + std::to_string(params[index][12]) + " " +
                              "-DSA=" + std::to_string(params[index][13]) + " " +
                              "-DSB=" + std::to_string(params[index][14]) + " " +
                              "-DKREG=" + std::to_string(params[index][15]);
  err = clBuildProgram(program, 1, &device, build_options.c_str(), nullptr,
                       nullptr);
  if (err != CL_SUCCESS) {
    size_t log_size;
    clGetProgramBuildInfo(program, device, CL_PROGRAM_BUILD_LOG, 0, nullptr,
                          &log_size);
    std::vector<char> log(log_size);
    clGetProgramBuildInfo(program, device, CL_PROGRAM_BUILD_LOG, log_size,
                          log.data(), nullptr);
    std::cerr << "Build log:\n" << log.data() << std::endl;
    CHECK_CL_ERROR(err, "Failed to build program");
  }

  // Create kernel
  kernel = clCreateKernel(program, "orchestra_main", &err);
  CHECK_CL_ERROR(err, "Failed to create kernel");

  // Matrix dimensions from command-line arguments
  const size_t size_A = M * K * sizeof(float);
  const size_t size_B = K * N * sizeof(float);
  const size_t size_C = M * N * sizeof(float);

  // Create test data
  std::vector<float> A(M * K, 1.0f);
  std::vector<float> B(K * N, 2.0f);
  std::vector<float> C(M * N, 0.0f);

  // Create buffers
  cl_mem buf_A =
      clCreateBuffer(context, CL_MEM_READ_ONLY, size_A, nullptr, &err);
  CHECK_CL_ERROR(err, "Failed to create buffer A");
  cl_mem buf_B =
      clCreateBuffer(context, CL_MEM_READ_ONLY, size_B, nullptr, &err);
  CHECK_CL_ERROR(err, "Failed to create buffer B");
  cl_mem buf_C =
      clCreateBuffer(context, CL_MEM_WRITE_ONLY, size_C, nullptr, &err);
  CHECK_CL_ERROR(err, "Failed to create buffer C");

  // Write data to buffers
  err = clEnqueueWriteBuffer(queue, buf_A, CL_TRUE, 0, size_A, A.data(), 0,
                             nullptr, nullptr);
  CHECK_CL_ERROR(err, "Failed to write buffer A");
  err = clEnqueueWriteBuffer(queue, buf_B, CL_TRUE, 0, size_B, B.data(), 0,
                             nullptr, nullptr);
  CHECK_CL_ERROR(err, "Failed to write buffer B");

  // Set kernel arguments
  int kSizeM = M;
  int kSizeN = N;
  int kSizeK = K;
  float alpha = 1.0f;
  float beta = 0.0f;
  int b_offset = 0;
  int c_offset = 0;

  err = clSetKernelArg(kernel, 0, sizeof(int), &kSizeM);
  CHECK_CL_ERROR(err, "Failed to set arg 0");
  err = clSetKernelArg(kernel, 1, sizeof(int), &kSizeN);
  CHECK_CL_ERROR(err, "Failed to set arg 1");
  err = clSetKernelArg(kernel, 2, sizeof(int), &kSizeK);
  CHECK_CL_ERROR(err, "Failed to set arg 2");
  err = clSetKernelArg(kernel, 3, sizeof(float), &alpha);
  CHECK_CL_ERROR(err, "Failed to set arg 3");
  err = clSetKernelArg(kernel, 4, sizeof(float), &beta);
  CHECK_CL_ERROR(err, "Failed to set arg 4");
  err = clSetKernelArg(kernel, 5, sizeof(cl_mem), &buf_A);
  CHECK_CL_ERROR(err, "Failed to set arg 5");
  err = clSetKernelArg(kernel, 6, sizeof(cl_mem), &buf_B);
  CHECK_CL_ERROR(err, "Failed to set arg 6");
  err = clSetKernelArg(kernel, 7, sizeof(cl_mem), &buf_C);
  CHECK_CL_ERROR(err, "Failed to set arg 7");
  err = clSetKernelArg(kernel, 8, sizeof(int), &b_offset);
  CHECK_CL_ERROR(err, "Failed to set arg 8");
  err = clSetKernelArg(kernel, 9, sizeof(int), &c_offset);
  CHECK_CL_ERROR(err, "Failed to set arg 9");

  // Set work group size
  size_t global_work_size[2] = {static_cast<size_t>(dims[index][2]),
                                static_cast<size_t>(dims[index][3])};
  size_t local_work_size[2] = {static_cast<size_t>(dims[index][0]),
                               static_cast<size_t>(dims[index][1])};

  std::cout << "Queuing kernel orchestra_main " << num_runs << " time(s) with dimensions M=" << M
            << ", N=" << N << ", K=" << K << std::endl;

  // Queue all kernels asynchronously
  std::vector<cl_event> kernel_events(num_runs);
  for (int run = 0; run < num_runs; run++) {
    // Enqueue kernel with event (no wait)
    err = clEnqueueNDRangeKernel(queue, kernel, 2, nullptr, global_work_size,
                                 local_work_size, 0, nullptr, &kernel_events[run]);
    CHECK_CL_ERROR(err, "Failed to enqueue kernel");
  }

  std::cout << "All kernels queued. Waiting for completion..." << std::endl;

  // Wait for all kernels to complete
  err = clWaitForEvents(num_runs, kernel_events.data());
  CHECK_CL_ERROR(err, "Failed to wait for kernel events");

  // Collect timing from all events
  std::vector<double> latencies_ms;
  for (int run = 0; run < num_runs; run++) {
    // Get GPU timing
    cl_ulong start_time, end_time;
    err = clGetEventProfilingInfo(kernel_events[run], CL_PROFILING_COMMAND_START,
                                  sizeof(cl_ulong), &start_time, nullptr);
    CHECK_CL_ERROR(err, "Failed to get start time");
    err = clGetEventProfilingInfo(kernel_events[run], CL_PROFILING_COMMAND_END,
                                  sizeof(cl_ulong), &end_time, nullptr);
    CHECK_CL_ERROR(err, "Failed to get end time");
    
    double gpu_latency_ms = (end_time - start_time) / 1e6; // Convert nanoseconds to milliseconds
    double gpu_latency_us = (end_time - start_time) / 1e3; // Convert nanoseconds to microseconds
    latencies_ms.push_back(gpu_latency_ms);
    
    std::cout << "Run " << (run + 1) << "/" << num_runs 
              << " - GPU Latency: " << gpu_latency_ms << " ms (" 
              << gpu_latency_us << " us)" << std::endl;
    
    // Release event
    clReleaseEvent(kernel_events[run]);
  }

  // Calculate and display statistics
  if (num_runs > 1) {
    double sum = 0.0;
    double min_latency = latencies_ms[0];
    double max_latency = latencies_ms[0];
    for (double latency : latencies_ms) {
      sum += latency;
      if (latency < min_latency) min_latency = latency;
      if (latency > max_latency) max_latency = latency;
    }
    double avg_latency = sum / num_runs;
    
    std::cout << "\nStatistics over " << num_runs << " runs:" << std::endl;
    std::cout << "  Average: " << avg_latency << " ms" << std::endl;
    std::cout << "  Min:     " << min_latency << " ms" << std::endl;
    std::cout << "  Max:     " << max_latency << " ms" << std::endl;
  }

  // Read results
  err = clEnqueueReadBuffer(queue, buf_C, CL_TRUE, 0, size_C, C.data(), 0,
                            nullptr, nullptr);
  CHECK_CL_ERROR(err, "Failed to read buffer C");

  // Cleanup
  clReleaseMemObject(buf_A);
  clReleaseMemObject(buf_B);
  clReleaseMemObject(buf_C);
  clReleaseKernel(kernel);
  clReleaseProgram(program);
  clReleaseCommandQueue(queue);
  clReleaseContext(context);

  return CL_SUCCESS;
}

int main(int argc, char* argv[]) {
  // Parse command-line arguments: index, [num_runs], [m, n, k]
  if (argc != 2 && argc != 3 && argc != 5 && argc != 6) {
    std::cerr << "Usage: " << argv[0] << " <index> [<num_runs>] [<m> <n> <k>]" << std::endl;
    std::cerr << "  index: 0-6 to select parameter and dimension set" << std::endl;
    std::cerr << "  num_runs: number of times to run the kernel (default: 1)" << std::endl;
    std::cerr << "  m: matrix M dimension (default: 1024)" << std::endl;
    std::cerr << "  n: matrix N dimension (default: 1024)" << std::endl;
    std::cerr << "  k: matrix K dimension (default: 1024)" << std::endl;
    return 1;
  }

  int index = std::stoi(argv[1]);
  if (index < 0 || index > 6) {
    std::cerr << "Error: index must be between 0 and 6" << std::endl;
    return 1;
  }

  // Default values
  int num_runs = 1;
  int M = 1024;
  int N = 1024;
  int K = 1024;

  // Parse arguments based on count
  if (argc == 3) {
    // index, num_runs
    num_runs = std::stoi(argv[2]);
  } else if (argc == 5) {
    // index, m, n, k
    M = std::stoi(argv[2]);
    N = std::stoi(argv[3]);
    K = std::stoi(argv[4]);
  } else if (argc == 6) {
    // index, num_runs, m, n, k
    num_runs = std::stoi(argv[2]);
    M = std::stoi(argv[3]);
    N = std::stoi(argv[4]);
    K = std::stoi(argv[5]);
  }

  if (num_runs <= 0) {
    std::cerr << "Error: num_runs must be a positive integer" << std::endl;
    return 1;
  }

  if (M <= 0 || N <= 0 || K <= 0) {
    std::cerr << "Error: m, n, k must be positive integers" << std::endl;
    return 1;
  }

  std::cout << "Using parameter set " << index << std::endl;
  std::cout << "Matrix dimensions: M=" << M << ", N=" << N << ", K=" << K << std::endl;
  cl_int err = test_clblast_bw(index, M, N, K, num_runs);
  if (err != CL_SUCCESS) {
    return 1;
  }
  return 0;
}