#!/bin/bash

WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

########################################
#### Set up RPC tracker before running this script ####
# ## Run in server
# conda activate tvm-build-venv
# export TVM_LIBRARY_PATH=${WORKSPACE_DIR}/tvm/build
# python -m tvm.exec.rpc_tracker --host 0.0.0.0 --port 9190

# ## Run in local
# adb -s R3CX80PSDPY forward --remove-all
# adb -s R3CX80PSDPY reverse --remove-all
# # device -> local -> server
# adb -s R3CX80PSDPY reverse tcp:9190 tcp:9190 # device to local
# ssh -N -L 9190:127.0.0.1:9190 hamburg # local to server
# # server -> local -> device
# adb -s R3CX80PSDPY forward tcp:9090 tcp:9090 # local to device
# ssh -N -R 9090:127.0.0.1:9090 hamburg # server to local
# # rpc server on device
# adb -s R3CX80PSDPY shell "cd /data/local/tmp && LD_LIBRARY_PATH=/data/local/tmp /data/local/tmp/tvm_rpc server --tracker=127.0.0.1:9190 --key=android64"
########################################

# allow conda activate command in shell script
source "$(conda info --base)/etc/profile.d/conda.sh"
conda activate tvm-build-venv
export TVM_LIBRARY_PATH=${WORKSPACE_DIR}/tvm/build

# 1 core: cpu 꽤 느려지고 나머지 미세하게 느려짐
# python run_contention.py -c pareto_so_files/1x1024x3072_cand001_neon+dotprod.so -g 0,1024,1024,1024 -n matmul_257x1024x4096 \
#   --CPU_REPEAT_LONG 200 --CPU_REPEAT_SHORT 20 \
#   --GPU_REPEAT_LONG 200 --GPU_REPEAT_SHORT 50 \
#   --NPU_REPEAT_LONG 200 --NPU_REPEAT_SHORT 20

# python run_contention.py -c pareto_so_files/1x1024x3072_cand001_neon+dotprod.so -g 0,257,1024,4096 -n matmul_257x1024x4096 \
#   --CPU_REPEAT_LONG 200 --CPU_REPEAT_SHORT 20 \
#   --GPU_REPEAT_LONG 500 --GPU_REPEAT_SHORT 50 \
#   --NPU_REPEAT_LONG 200 --NPU_REPEAT_SHORT 20

# python run_contention.py -c pareto_so_files/1x1024x3072_cand001_neon+dotprod.so -g 0,257,1024,4096 -n matmul_1x1024x4096 \
#   --CPU_REPEAT_LONG 500 --CPU_REPEAT_SHORT 20 \
#   --GPU_REPEAT_LONG 200 --GPU_REPEAT_SHORT 50 \
#   --NPU_REPEAT_LONG 6000 --NPU_REPEAT_SHORT 100


# # all matvec large
# python run_contention.py -c pareto_so_files/1x8192x8192_cand004_neon+dotprod.so -g 0,1,16384,16384 -n matmul_1x16384x16384 \
#   --CPU_REPEAT_LONG 20 --CPU_REPEAT_SHORT 20 \
#   --GPU_REPEAT_LONG 100 --GPU_REPEAT_SHORT 20 \
#   --NPU_REPEAT_LONG 1000 --NPU_REPEAT_SHORT 50
# # gpu prefill
# python run_contention.py -c pareto_so_files/1x8192x8192_cand004_neon+dotprod.so -g 0,257,4096,4096 -n matmul_1x16384x16384 \
#   --CPU_REPEAT_LONG 20 --CPU_REPEAT_SHORT 20 \
#   --GPU_REPEAT_LONG 100 --GPU_REPEAT_SHORT 20 \
#   --NPU_REPEAT_LONG 1000 --NPU_REPEAT_SHORT 50
# # gpu prefill + ours
# python run_contention.py -c pareto_so_files/1x8192x8192_cand004_neon+dotprod.so -g 5,257,4096,4096 -n matmul_1x16384x16384 \
#   --CPU_REPEAT_LONG 20 --CPU_REPEAT_SHORT 20 \
#   --GPU_REPEAT_LONG 100 --GPU_REPEAT_SHORT 20 \
#   --NPU_REPEAT_LONG 1000 --NPU_REPEAT_SHORT 50



# # gpu npu prefill
# python run_contention.py -c pareto_so_files/1x8192x8192_cand004_neon+dotprod.so -g 0,257,4096,4096 -n matmul_257x4096x4096 \
#   --CPU_REPEAT_LONG 20 --CPU_REPEAT_SHORT 20 \
#   --GPU_REPEAT_LONG 100 --GPU_REPEAT_SHORT 20 \
#   --NPU_REPEAT_LONG 1000 --NPU_REPEAT_SHORT 50
# python run_contention.py -c pareto_so_files/1x8192x8192_cand004_neon+dotprod.so -g 4,257,4096,4096 -n matmul_257x4096x4096 \
#   --CPU_REPEAT_LONG 20 --CPU_REPEAT_SHORT 20 \
#   --GPU_REPEAT_LONG 100 --GPU_REPEAT_SHORT 20 \
#   --NPU_REPEAT_LONG 1000 --NPU_REPEAT_SHORT 50
# python run_contention.py -c pareto_so_files/1x8192x8192_cand004_neon+dotprod.so -g 2,257,4096,4096 -n matmul_257x4096x4096 \
#   --CPU_REPEAT_LONG 20 --CPU_REPEAT_SHORT 20 \
#   --GPU_REPEAT_LONG 100 --GPU_REPEAT_SHORT 20 \
#   --NPU_REPEAT_LONG 1000 --NPU_REPEAT_SHORT 50
# python run_contention.py -c pareto_so_files/1x8192x8192_cand004_neon+dotprod.so -g 1,257,4096,4096 -n matmul_257x4096x4096 \
#   --CPU_REPEAT_LONG 20 --CPU_REPEAT_SHORT 20 \
#   --GPU_REPEAT_LONG 100 --GPU_REPEAT_SHORT 20 \
#   --NPU_REPEAT_LONG 1000 --NPU_REPEAT_SHORT 50


# # all matvec
# # 1 core: 거의 차이 없음
# python run_contention.py -c pareto_so_files/1x1024x3072_cand001_neon+dotprod.so -g 0,1,1024,4096 -n matmul_1x1024x4096 \
#   --CPU_REPEAT_LONG 500 --CPU_REPEAT_SHORT 20 \
#   --GPU_REPEAT_LONG 1000 --GPU_REPEAT_SHORT 100 \
#   --NPU_REPEAT_LONG 6000 --NPU_REPEAT_SHORT 100

# all matvec - ours
python run_contention.py -c pareto_so_files/1x1024x3072_cand099_neon+dotprod.so -g 6,1,1024,4096 -n matmul_1x1024x4096 \
  --CPU_REPEAT_LONG 500 --CPU_REPEAT_SHORT 20 \
  --GPU_REPEAT_LONG 1000 --GPU_REPEAT_SHORT 100 \
  --NPU_REPEAT_LONG 6000 --NPU_REPEAT_SHORT 100


### Rank the 7 predefined kernels by latency for various shapes
# # [0, 6, 2, 3, 4, 5, 1]
# python clblast_bw_test/benchmark_params.py -m 257 -k 4096 -n 4096 -r 30 -s 1.0

# # [0, 3, 2, 6, 4, 5, 1]
# python clblast_bw_test/benchmark_params.py -m 1024 -k 1024 -n 1024 -r 30 -s 1.0

# # [0, 3, 2, 6, 4, 5, 1]
# python clblast_bw_test/benchmark_params.py -m 257 -k 1024 -n 4096 -r 30 -s 1.0

# # [0, 3, 6, 2, 4, 5, 1]
# python clblast_bw_test/benchmark_params.py -m 2048 -k 1024 -n 4096 -r 30 -s 1.0

# # [0, 4, 6, 2, 3, 5, 1]
# python clblast_bw_test/benchmark_params.py -m 1 -k 1024 -n 4096 -r 30 -s 1.0


# gemm_shapes = [
#     # ----- CLIP L-14 -----
#     (257, 1024, 3072, "clip L14 qkv fuse"),
#     (257, 1024, 4096, "clip L14 up projection"),

#     # ----- CLIP B-16 -----
#     (197, 768, 2304, "clip B16 qkv fuse"),
#     (197, 768, 3072, "clip B16 up projection"),

#     # ----- InternVL3.5-1B -----
#     (1, 1024, 4096, "internvl3.5-1b qkv fuse"),
#     (1, 1024, 3072, "internvl3.5-1b up projection"),

#     # ----- Qwen2-VL-2B -----
#     (1, 1536, 2048, "qwen2-vl-2b qkv fuse"),
#     (1, 1536, 8960, "qwen2-vl-2b up projection"),
# ]