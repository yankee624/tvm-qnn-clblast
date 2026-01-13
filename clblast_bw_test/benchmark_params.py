#!/usr/bin/env python3
"""
Benchmark all parameter sets and rank them by average latency.
"""

import subprocess
import re
import sys
import time
import argparse

def run_benchmark(param_idx, num_runs=10, m=1024, n=1024, k=1024):
    """Run clblast_bw_test for a specific parameter set."""
    cmd = f'adb shell "/data/local/tmp/clblast_bw_test {param_idx} {num_runs} {m} {k} {n}"'
    
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=60)
        output = result.stdout
        
        # Extract average latency from output
        # Looking for: "  Average: 1.94109 ms"
        avg_match = re.search(r'Average:\s+([\d.]+)\s+ms', output)
        
        if avg_match:
            avg_latency = float(avg_match.group(1))
            return avg_latency
        else:
            print(f"Warning: Could not parse output for parameter set {param_idx}", file=sys.stderr)
            return None
            
    except subprocess.TimeoutExpired:
        print(f"Error: Timeout for parameter set {param_idx}", file=sys.stderr)
        return None
    except Exception as e:
        print(f"Error running parameter set {param_idx}: {e}", file=sys.stderr)
        return None

def main():
    parser = argparse.ArgumentParser(description='Benchmark all CLBlast parameter sets')
    parser.add_argument('-m', '--m', type=int, default=1024, help='Matrix dimension M (default: 1024)')
    parser.add_argument('-k', '--k', type=int, default=1024, help='Matrix dimension K (default: 1024)')
    parser.add_argument('-n', '--n', type=int, default=1024, help='Matrix dimension N (default: 1024)')
    parser.add_argument('-r', '--runs', type=int, default=10, help='Number of runs per parameter set (default: 10)')
    parser.add_argument('-s', '--sleep', type=float, default=1.0, help='Sleep time between runs in seconds (default: 1.0)')
    
    args = parser.parse_args()
    
    print("Benchmarking all parameter sets...")
    print("=" * 60)
    print(f"Matrix dimensions: M={args.m}, K={args.k}, N={args.n}")
    print(f"Runs per parameter set: {args.runs}")
    print(f"Sleep between runs: {args.sleep}s")
    print("=" * 60)
    
    results = []
    
    # Run benchmarks for parameter sets 0-6
    for idx in range(7):
        print(f"\nRunning parameter set {idx}...")
        avg_latency = run_benchmark(idx, num_runs=args.runs, m=args.m, k=args.k, n=args.n)
        
        if avg_latency is not None:
            results.append((idx, avg_latency))
            print(f"  → Average latency: {avg_latency:.5f} ms")
        else:
            print(f"  → Failed to get result")
        
        # Sleep between runs to prevent overheating (except after the last run)
        if idx < 6:
            print(f"  → Cooling down for {args.sleep}s...")
            time.sleep(args.sleep)
    
    print("\n" + "=" * 60)
    print("\nResults Summary:")
    print("=" * 60)
    
    # Sort by average latency (ascending - fastest first)
    results.sort(key=lambda x: x[1])
    
    print("\nRanking (fastest to slowest):")
    print("-" * 60)
    print(f"{'Rank':<8} {'Param Set':<12} {'Avg Latency (ms)':<20}")
    print("-" * 60)
    
    for rank, (idx, latency) in enumerate(results, 1):
        print(f"{rank:<8} {idx:<12} {latency:.5f}")
    
    print("\n" + "=" * 60)
    print("\nParameter sets in order of performance (fastest to slowest):")
    fastest_order = [idx for idx, _ in results]
    print(fastest_order)
    
    print("\nBest parameter set: {}".format(fastest_order[0]))
    print("=" * 60)

if __name__ == "__main__":
    main()
