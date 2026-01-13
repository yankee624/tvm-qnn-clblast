#!/usr/bin/env python3
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

"""
Benchmark pre-built matrix multiplication libraries on Android device via RPC.
This script loads existing .so files and benchmarks them without tuning.
"""

import os
import re
import time
import subprocess
import threading
from pathlib import Path
import logging

import numpy as np
import tvm
from tvm import rpc
import argparse
import json
import datetime

logging.basicConfig(
    level=logging.INFO,
    format='[%(asctime)s.%(msecs)03d] %(message)s',
    datefmt='%H:%M:%S'
)
logger = logging.getLogger(__name__)

    
# Fixed cpu core configuration
mode = 0
nthreads = 1


def _adb_cmd(serial=None):
    """Helper function to build adb command with optional serial number."""
    cmd = ["adb"]
    if serial:
        cmd.extend(["-s", serial])
    return cmd

def wait_for_device_cooldown(adb_serial=None, 
                             thermal_zone="thermal_zone53",
                             start_temp=40.0, 
                             end_temp=30.0,
                             check_interval=10):
    """
    Monitor device temperature and wait for it to cool down if needed.
    
    Args:
        adb_serial: ADB device serial number (optional)
        thermal_zone: Thermal zone to monitor (default: thermal_zone53)
        start_temp: Temperature threshold to start cooling (Celsius)
        end_temp: Temperature threshold to resume execution (Celsius)
        check_interval: Time between temperature checks (seconds)
    
    Returns:
        bool: True if ready to proceed, False if temperature check failed
    """
    temp_cmd = _adb_cmd(adb_serial) + ["shell", "cat", f"/sys/class/thermal/{thermal_zone}/temp"]
    sleep_on = False
    
    while True:
        try:
            output = subprocess.check_output(temp_cmd, timeout=10).decode("utf-8")
            temp_milli = int(re.search(r'(\d+)', output).group(1))
            temp_c = temp_milli / 1000.0
            print(f"Current device temperature: {temp_c:.2f} °C")

            if sleep_on:
                if temp_c <= end_temp:
                    print(f"✓ Device cooled down to {temp_c:.2f} °C, resuming execution.")
                    break
                else:
                    print(f"Waiting for device to cool down below {end_temp} °C...")
            else:
                if temp_c >= start_temp:
                    sleep_on = True
                    print(f"Device temperature {temp_c:.2f} °C exceeds {start_temp} °C, waiting to cool down...")
                else:
                    break
        except Exception as e:
            print(f"WARN: Failed to get device temperature: {e}")
            return False
        
        time.sleep(check_interval)
    
    print("Starting execution...")
    return True


def run_cpu_benchmark(remote_mod, r_entry, rdev, ra, rb, rc, config_func, mode, nthreads, repeat=100, number=20):
    """Run CPU benchmark and return timing statistics."""
    config_func(mode, nthreads)
    time.sleep(0.1)
    
    logger.info(f"[CPU] Running (repeat={repeat}, number={number})...")
    time_f = remote_mod.time_evaluator(r_entry, rdev, number=number, repeat=repeat)
    latencies = np.array(time_f(ra, rb, rc).results) # seconds
    latencies = latencies * 1000.0 # convert to ms

    stats = {
        'mean': float(np.mean(latencies)),
        'min': float(np.min(latencies)),
        'max': float(np.max(latencies)),
        'std': float(np.std(latencies))
    }
    
    logger.info(f"[CPU] Mean: {stats['mean']:.3f} ms, Min: {stats['min']:.3f} ms, Max: {stats['max']:.3f} ms, Std: {stats['std']:.3f} ms")
    return stats, list(latencies)

def run_gpu_benchmark(gpu_config, repeat):
    
    logger.info(f"[GPU] Running (repeat={repeat})...")
    
    # Mock
    # time.sleep(0.01 * repeat)
    # return {}, []

    kernel_idx, m, k, n = map(int, gpu_config.split(','))
    cmd = f"/data/local/tmp/clblast_bw_test {kernel_idx} {repeat} {m} {n} {k}"
    result = subprocess.run(["adb", "shell", cmd], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

    latencies = []
    for line in result.stdout.split('\n'):
        if 'GPU Latency' in line:
            match = re.search(r'GPU Latency:\s+([\d.]+)\s+ms', line)
            if match:
                latencies.append(float(match.group(1)))
    latencies = np.array(latencies)
    stats = {
        'mean': float(np.mean(latencies)),
        'min': float(np.min(latencies)),
        'max': float(np.max(latencies)),
        'std': float(np.std(latencies))
    }
    logger.info(f"[GPU] Mean: {stats['mean']:.3f} ms, Min: {stats['min']:.3f} ms, Max: {stats['max']:.3f} ms, Std: {stats['std']:.3f} ms")
    return stats, list(latencies)

def run_npu_benchmark(npu_cmd_template, num_inferences=100, label="NPU"):
    """Run NPU QNN benchmark."""
    npu_cmd = f"{npu_cmd_template} --num_inferences {num_inferences}"
    
    logger.info(f"[{label}] Starting command (num_inferences={num_inferences}): {npu_cmd}")
    result = subprocess.run(["adb", "shell", npu_cmd], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    logger.info(f"[{label}] Command completed with exit code {result.returncode}")
    
    if result.returncode != 0:
        raise RuntimeError(f"NPU command failed with exit code {result.returncode}, stderr:\n{result.stderr}")
    
    return result.returncode, result.stdout


def pull_and_parse_qnn_profile(run_dir, label="QNN"):
    """Pull QNN profiling log from device and parse latency statistics."""
    # Pull profiling log from device
    log_remote_path = f"{run_dir}/out_htp/qnn-profiling-data_0.log"
    log_local_path = "./qnn-profiling-data_0.log"
    
    logger.info(f"[{label}] Pulling profiling log: npu pull {log_remote_path} {log_local_path}")
    pull_result = subprocess.run(
        ["adb", "pull", log_remote_path, log_local_path],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    
    if pull_result.returncode != 0:
        logger.error(f"[{label}] ERROR: Failed to pull profiling log")
        logger.error(f"[{label}] stderr:\n{pull_result.stderr}")
        return None
    
    # Run qnn-profile-viewer to parse the log
    qnn_viewer_path = "/opt/qairt/2.40.0.251030/bin/x86_64-linux-clang/qnn-profile-viewer"
    logger.info(f"[{label}] Running qnn-profile-viewer...")
    viewer_result = subprocess.run(
        [qnn_viewer_path, "--input_log", log_local_path],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    
    if viewer_result.returncode != 0:
        logger.error(f"[{label}] ERROR: qnn-profile-viewer failed")
        logger.error(f"[{label}] stderr:\n{viewer_result.stderr}")
        return None
    
    # Parse output to extract Average/Min/Max inference times
    # Expected format:
    # Execute Stats (Average):
    # ...
    # Graph 0 (matmul_qnn):
    #     NetRun: 80500 us
    
    viewer_output = viewer_result.stdout
    # logger.info(f"[{label}] qnn-profile-viewer output:\n{viewer_output}")
    
    latency_stats = {}
    current_stat_type = None
    
    for line in viewer_output.split('\n'):
        line = line.strip()
        
        # Detect stat type section
        if 'Execute Stats (Average)' in line:
            current_stat_type = 'mean'
        elif 'Execute Stats (Min)' in line:
            current_stat_type = 'min'
        elif 'Execute Stats (Max)' in line:
            current_stat_type = 'max'
        
        # Parse NetRun time
        if current_stat_type and 'NetRun:' in line:
            # Format: "NetRun: 80500 us"
            parts = line.split(':')
            if len(parts) >= 2:
                time_str = parts[1].strip().replace('us', '').strip()
                try:
                    time_us = int(time_str)
                    time_ms = time_us / 1000.0  # Convert to ms
                    latency_stats[current_stat_type] = time_ms
                except ValueError:
                    logger.warning(f"[{label}] WARNING: Failed to parse time from: {line}")
    
    logger.info(f"[{label}] Parsed latency stats: {latency_stats}")
    return latency_stats


def benchmark_variant(remote, cpu_kernel_path, gpu_kernel_config, npu_kernel_path,
                        CPU_REPEAT_LONG, CPU_REPEAT_SHORT,
                        GPU_REPEAT_LONG, GPU_REPEAT_SHORT,
                        NPU_REPEAT_LONG, NPU_REPEAT_SHORT):
    """Benchmark a single variant with fixed 8-core configuration."""

    if not os.path.exists(cpu_kernel_path):
        logger.error(f"ERROR: .so file not found: {cpu_kernel_path}")
        return
    
    logger.info(f"Running library: {cpu_kernel_path}")

    # Extract shape and variant from filename: matmul_MxKxN_variant.so
    name = Path(cpu_kernel_path).stem
    shape = re.search(r"(\d+x\d+x\d+)", name)
    if not shape:
        logger.error(f"ERROR: Unable to parse shape from filename: {name}")
        return
    m, k, n = map(int, shape.group(1).split('x'))

    # Prepare test data
    a_np = np.random.uniform(size=(m, k)).astype(np.float32)
    b_np = np.random.uniform(size=(k, n)).astype(np.float32)

    # Upload and load module
    remote.upload(cpu_kernel_path)
    remote_filename = os.path.basename(cpu_kernel_path)
    remote_mod = remote.load_module(remote_filename)
    config_func = remote.get_function('runtime.config_threadpool')

    # Allocate device tensors
    rdev = remote.cpu()
    ra = tvm.runtime.tensor(a_np, rdev)
    rb = tvm.runtime.tensor(b_np, rdev)
    rc = tvm.runtime.tensor(np.zeros((m, n), dtype=np.float32), rdev)

    # Get entry function
    r_entry = getattr(remote_mod, "entry_name", "matmul")
    r_f = remote_mod[r_entry]
    
    # NPU command template and run directory
    RUN_DIR = f"/data/local/tmp/qnn/{npu_kernel_path}"
    NPU_CMD = (
        f"cd {RUN_DIR} && "
        "LD_LIBRARY_PATH=.. ADSP_LIBRARY_PATH=.. ../qnn-net-run --backend ../libQnnHtp.so --model ./libmatmul_qnn.so "
        "--input_list ./input_list_target.txt --profiling_level client --output_dir ./out_htp"
    )
    
    # Warmup and verify
    config_func(mode, nthreads)
    time.sleep(0.1)
    r_f(ra, rb, rc)
    np.testing.assert_allclose(rc.numpy(), np.dot(a_np, b_np), rtol=1e-4, atol=1e-4)

    DONE = False

    cpu_result_container = {}
    def delayed_cpu_run(delay, repeat, loop=False):
        time.sleep(delay)
        while True:
            stats, results = run_cpu_benchmark(
                remote_mod, r_entry, rdev, ra, rb, rc, config_func, mode, nthreads,
                repeat=repeat
            )
            cpu_result_container['stats'] = stats
            cpu_result_container['results'] = results
            if not loop or DONE:
                break
    
    gpu_result_container = {}
    def delayed_gpu_run(delay, repeat, loop=False):
        time.sleep(delay)
        while True:
            stats, results = run_gpu_benchmark(gpu_kernel_config, repeat)
            gpu_result_container['stats'] = stats
            gpu_result_container['results'] = results
            if not loop or DONE:
                break

    npu_result_container = {}
    def delayed_npu_run(delay, repeat):
        time.sleep(delay)
        returncode, stdout = run_npu_benchmark(NPU_CMD, num_inferences=repeat)
        npu_result_container['returncode'] = returncode
        npu_result_container['stdout'] = stdout

    wait_for_device_cooldown()

    # ===== Measure standalone latency for each =====
    logger.info(f"\n--- Standalone Latency Measurements ---")
    cpu_stat_standalone, cpu_latency_standalone = run_cpu_benchmark(
        remote_mod, r_entry, rdev, ra, rb, rc, config_func, mode, nthreads,
        repeat=CPU_REPEAT_SHORT
    )
    gpu_stat_standalone, gpu_latency_standalone = run_gpu_benchmark(gpu_kernel_config, GPU_REPEAT_SHORT)

    cpu_thread = threading.Thread(target=delayed_cpu_run, args=(0.0, CPU_REPEAT_LONG), daemon=False)
    cpu_thread.start()
    returncode, stdout = run_npu_benchmark(NPU_CMD, num_inferences=NPU_REPEAT_SHORT)
    cpu_thread.join()
    npu_stat_standalone = pull_and_parse_qnn_profile(RUN_DIR)
    wait_for_device_cooldown()

    # ===== First run: CPU&GPU long, NPU short =====
    # Goal: NPU always overlaps
    logger.info(f"\n--- Run 1: CPU&GPU long, NPU short ---")
    
    
    DONE = False
    # CPU & GPU immediately (loop until NPU finishes)
    cpu_thread = threading.Thread(target=delayed_cpu_run, args=(0.0, CPU_REPEAT_LONG, True), daemon=False)
    cpu_thread.start()
    gpu_thread = threading.Thread(target=delayed_gpu_run, args=(0.0, GPU_REPEAT_LONG, True), daemon=False)
    gpu_thread.start()
    
    # NPU with delay
    npu_thread = threading.Thread(target=delayed_npu_run, args=(1.0, NPU_REPEAT_SHORT), daemon=False)
    npu_thread.start()
    npu_thread.join()
    DONE = True

    if not cpu_thread.is_alive():
        raise RuntimeError("CPU finished before NPU (no overlap). Increase CPU_REPEAT_LONG or decrease NPU_REPEAT_SHORT")
    if not gpu_thread.is_alive():
        raise RuntimeError("GPU finished before NPU (no overlap). Increase GPU_REPEAT_LONG or decrease NPU_REPEAT_SHORT")
    
    cpu_thread.join()
    gpu_thread.join()
    
    npu_stat = pull_and_parse_qnn_profile(RUN_DIR)
    wait_for_device_cooldown()

    # ===== Second run: CPU&NPU long, GPU short =====
    # Goal: GPU always overlap.
    logger.info(f"\n--- Run 2: CPU&NPU long, GPU short ---")
    
    DONE = False
    # CPU & NPU immediately (CPU loop until GPU finishes, NPU doesn't loop due to long startup time)
    cpu_thread = threading.Thread(target=delayed_cpu_run, args=(4.0, CPU_REPEAT_LONG, True), daemon=False)
    cpu_thread.start()
    npu_thread = threading.Thread(target=delayed_npu_run, args=(0, NPU_REPEAT_LONG), daemon=False)
    npu_thread.start()
    
    # GPU waits for NPU startup (usually takes a few seconds)
    gpu_thread = threading.Thread(target=delayed_gpu_run, args=(5.0, GPU_REPEAT_SHORT), daemon=False)
    gpu_thread.start()
    gpu_thread.join()
    DONE = True

    if not cpu_thread.is_alive():
        raise RuntimeError("CPU finished before GPU (no overlap). Increase CPU_REPEAT_LONG or decrease GPU_REPEAT_SHORT")
    if not npu_thread.is_alive():
        raise RuntimeError("NPU finished before GPU (no overlap). Increase NPU_REPEAT_LONG or decrease GPU_REPEAT_SHORT")
    cpu_thread.join()
    npu_thread.join()
    
    gpu_stat, gpu_latency = gpu_result_container.get('stats'), gpu_result_container.get('results')
    wait_for_device_cooldown()
    
    # ====== Third run: GPU&NPU long, CPU short =====
    # Goal: CPU always overlap.
    logger.info(f"\n--- Run 3: GPU&NPU long, CPU short ---")

    DONE = False
    gpu_thread = threading.Thread(target=delayed_gpu_run, args=(4.0, GPU_REPEAT_LONG, True), daemon=False)
    gpu_thread.start()
    npu_thread = threading.Thread(target=delayed_npu_run, args=(0, NPU_REPEAT_LONG), daemon=False)
    npu_thread.start()

    cpu_thread = threading.Thread(target=delayed_cpu_run, args=(5.0, CPU_REPEAT_SHORT), daemon=False)
    cpu_thread.start()
    cpu_thread.join()
    DONE = True

    if not npu_thread.is_alive():
        raise RuntimeError("NPU finished before CPU (no overlap). Increase NPU_REPEAT_LONG or decrease CPU_REPEAT_SHORT")
    if not gpu_thread.is_alive():
        raise RuntimeError("GPU finished before CPU (no overlap). Increase GPU_REPEAT_LONG or decrease CPU_REPEAT_SHORT")
    npu_thread.join()
    gpu_thread.join()
    DONE = True

    cpu_stat, cpu_latency = cpu_result_container.get('stats'), cpu_result_container.get('results')
    
    # Return results
    return {
        'cpu_stat': cpu_stat,
        'cpu_latency': cpu_latency,
        'gpu_stat': gpu_stat,
        'gpu_latency': gpu_latency,
        'npu_stat': npu_stat,
        'cpu_stat_standalone': cpu_stat_standalone,
        'cpu_latency_standalone': cpu_latency_standalone,
        'gpu_stat_standalone': gpu_stat_standalone,
        'gpu_latency_standalone': gpu_latency_standalone,
        'npu_stat_standalone': npu_stat_standalone,
    }


def main():
    # ========== Configuration ==========
    # RPC configuration
    tracker_host = "127.0.0.1"
    tracker_port = 9190
    tracker_key = "android64"

    # Parse command-line arguments: require a single .so file path
    parser = argparse.ArgumentParser(description="Run a single matmul .so on remote via RPC and verify correctness.")
    parser.add_argument("-c", "--cpu_kernel_path", required=True, help="Path to the cpu kernel .so file to run (e.g. matmul_1024x1024x1024_baseline.so)")
    parser.add_argument("-g", "--gpu_kernel_config", required=True, help="GPU kernel config (kernel_idx,m,k,n)")
    parser.add_argument("-n", "--npu_kernel_path", required=True, help="Path to the npu kernel file (on device) to run")
    parser.add_argument("--CPU_REPEAT_LONG", type=int, default=100)
    parser.add_argument("--CPU_REPEAT_SHORT", type=int, default=20)
    parser.add_argument("--GPU_REPEAT_LONG", type=int, default=5000)
    parser.add_argument("--GPU_REPEAT_SHORT", type=int, default=100)
    parser.add_argument("--NPU_REPEAT_LONG", type=int, default=500)
    parser.add_argument("--NPU_REPEAT_SHORT", type=int, default=20)

    args = parser.parse_args()
    cpu_kernel_path = args.cpu_kernel_path
    gpu_kernel_config = args.gpu_kernel_config
    npu_kernel_path = args.npu_kernel_path

    logger.info(f"\nConnecting to RPC tracker at {tracker_host}:{tracker_port}...")
    tracker = rpc.connect_tracker(tracker_host, tracker_port)

    remote = tracker.request(tracker_key, session_timeout=1800, priority=1)
    logger.info("Connected to remote device")


    result = benchmark_variant(remote, cpu_kernel_path, gpu_kernel_config, npu_kernel_path,
                               args.CPU_REPEAT_LONG, args.CPU_REPEAT_SHORT,
                               args.GPU_REPEAT_LONG, args.GPU_REPEAT_SHORT,
                               args.NPU_REPEAT_LONG, args.NPU_REPEAT_SHORT)
    result_stat = {k: v for k, v in result.items() if 'stat' in k}
    
    logger.info(f"\n{'='*60}")
    logger.info(json.dumps(result_stat, indent=2))
    
    result["nthreads"] = nthreads
    result["cpu_kernel_path"] = cpu_kernel_path
    result["gpu_kernel_config"] = gpu_kernel_config
    result["npu_kernel_path"] = npu_kernel_path
    filename = f"result/{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
    with open(filename, "w") as f:
        json.dump(result, f, indent=2)
    
    # Cleanup
    del remote

if __name__ == "__main__":
    main()
