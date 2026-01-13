import subprocess
import re
import csv
import sys
import os

# Define the list of (M, K, N) tuples to benchmark
# You can add or modify tuples here
m_values = [1, 32, 64, 128, 256]
kn_shapes = [
    (1024, 1024),
    (1024, 2048),
    (1024, 4096),
    (1024, 8192),
    (4096, 4096)
]

shapes = []
for m in m_values:
    for k, n in kn_shapes:
        shapes.append((m, k, n))

output_csv = "benchmark_results.csv"
script_path = "./qnn_custom.sh"

def parse_time(output, stat_type):
    """
    Parses the execution time from the qnn-profile-viewer output.
    Looks for a block starting with 'Execute Stats (<stat_type>):'
    and extracts the value for 'NetRun'.
    """
    # Regex explanation:
    # Execute Stats \({stat_type}\):  -> Matches the header, e.g., "Execute Stats (Average):"
    # (?:(?!Execute Stats).)*?        -> Non-greedy match of any character, but stop if we see another "Execute Stats" header (to stay within the block)
    # NetRun:\s+(\d+)\s+us            -> Matches "NetRun: 1234 us" and captures the digits
    
    pattern = re.compile(rf"Execute Stats \({stat_type}\):(.*?)(?=Execute Stats|\Z)", re.DOTALL)
    block_match = pattern.search(output)
    
    if block_match:
        block_content = block_match.group(1)
        time_match = re.search(r"NetRun:\s+(\d+)\s+us", block_content)
        if time_match:
            return int(time_match.group(1))
    
    return None

def run_benchmark():
    # Ensure the script is executable
    if not os.access(script_path, os.X_OK):
        print(f"Making {script_path} executable...")
        os.chmod(script_path, 0o755)

    print(f"Starting benchmark. Results will be saved to {output_csv}")

    NUM_REPEAT = 100

    with open(output_csv, 'w', newline='') as csvfile:
        fieldnames = ['M', 'K', 'N', 'min_total_us', 'max_total_us', 'avg_total_us']
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        writer.writeheader()

        for M, K, N in shapes:
            print(f"--------------------------------------------------")
            print(f"Running benchmark for shape: M={M}, K={K}, N={N}")
            
            try:
                # Run the shell script with arguments
                # capture_output=True captures both stdout and stderr
                result = subprocess.run(
                    [script_path, str(M), str(K), str(N)],
                    capture_output=True,
                    text=True,
                    check=True
                )
                
                output = result.stdout
                
                # Parse the output for Min, Max, Avg
                avg_time = parse_time(output, "Average")
                min_time = parse_time(output, "Min")
                max_time = parse_time(output, "Max")
                
                if avg_time is not None and min_time is not None and max_time is not None:
                    print(f"Success! Min={min_time}us, Max={max_time}us, Avg={avg_time}us")
                    writer.writerow({
                        'M': M,
                        'K': K,
                        'N': N,
                        'min_total_us': min_time / NUM_REPEAT,
                        'max_total_us': max_time / NUM_REPEAT,
                        'avg_total_us': avg_time / NUM_REPEAT
                    })
                    csvfile.flush()
                else:
                    print(f"Warning: Failed to parse results for {M}x{K}x{N}")
                    # Debugging: print part of the output if parsing fails
                    print("Output snippet (last 1000 chars):")
                    print(output[-1000:])

            except subprocess.CalledProcessError as e:
                print(f"Error: Script execution failed for {M}x{K}x{N}")
                print("Stderr output:")
                print(e.stderr)
            except Exception as e:
                print(f"An unexpected error occurred: {e}")

    print(f"--------------------------------------------------")
    print(f"Benchmark complete. Check {output_csv} for results.")

if __name__ == "__main__":
    run_benchmark()
