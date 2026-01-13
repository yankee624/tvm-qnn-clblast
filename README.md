# How to run

1. run `./qnn_prepare_model.sh` to generate matmul models of various sizes for NPU and push them to the target device.
    - Modify `SIZE_ARR` in the script to change the sizes of the models to be generated.
2. run `./build_tvm.sh` to build TVM.
3. run `./run_contention.sh` to run the matmul models on CPU, GPU, and NPU simultaneously on the target device and collect performance data.
    - Need to setup RPC tracker before running this script. See comments in the script for details.
