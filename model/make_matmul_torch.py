import argparse
import torch
import torch.nn as nn
import numpy as np


def parse_args():
    p = argparse.ArgumentParser(description="Create and save a small matmul Torch module and a raw input file.")
    # Positional arguments: allow omission to fall back to sensible defaults
    p.add_argument("M", type=int, nargs="?", default=1, help="Batch size / number of rows")
    p.add_argument("K", type=int, nargs="?", default=16, help="Input features / inner dim")
    p.add_argument("N", type=int, nargs="?", default=16, help="Output features / number of columns")
    return p.parse_args()


class MatMulModel(nn.Module):
    def __init__(self, K: int, N: int):
        super().__init__()

        self.K = K
        self.N = N
        
        self.layers = nn.ModuleList([
            nn.Sequential(nn.Linear(K, N, bias=False), 
                        #   nn.ReLU()
                          )
            for _ in range(20)
        ])


    def forward(self, x):
        out = torch.zeros(x.shape[0], self.N)
        for layer in self.layers:
            out += layer(x)
        return out

def main():
    args = parse_args()
    M = args.M
    K = args.K
    N = args.N

    model = MatMulModel(K, N).eval()

    example = torch.randn(M, K)

    # torch._C._jit_set_profiling_mode(False)
    # torch._C._jit_set_profiling_executor(False)
    # torch._C._jit_override_can_fuse_on_cpu(False)
    # torch.jit.optimized_execution(False)
    
    traced = torch.jit.trace(model, example)
    traced.save("matmul.pt")
    print(f"saved matmul of shape ({M}, {K}) @ ({K}, {N}) to matmul.pt")

    x = np.random.randn(M, K).astype("float32")
    x.tofile("input_0.raw")
    print(f"saved input_0.raw, shape (M, K)=({M}, {K})")


if __name__ == "__main__":
    main()