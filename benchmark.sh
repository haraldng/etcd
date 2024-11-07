#!/bin/bash

# Load benchmark configurations from JSON file
config_file="bench_config.json"
if ! [ -f "$config_file" ]; then
  echo "Configuration file $config_file not found!"
  exit 1
fi

# Parse configurations using jq
branches=($(jq -r '.branches[]' "$config_file"))
nodes=($(jq -r '.nodes[]' "$config_file"))
value_sizes=($(jq -r '.value_sizes[]' "$config_file"))
warmup_requests=$(jq -r '.request_count.warmup' "$config_file")
benchmark_requests=$(jq -r '.request_count.benchmark' "$config_file")
output_dir=$(jq -r '.output_dir' "$config_file")
clients=$(jq -r '.clients' "$config_file")
iterations=$(jq -r '.iterations' "$config_file")

# Use a default directory if not set
if [ -z "$output_dir" ] || [ "$output_dir" == "null" ]; then
  output_dir="$(date +'%Y%m%d_%H%M%S')"
fi

output_dir="bench_results/$output_dir"
mkdir -p "$output_dir"
echo "Output directory: $output_dir"

# Example command for using the output directory for logs or other files
log_file="$output_dir/benchmark.log"

# Paths to scripts and binaries
clean_script="./clean_local.sh"
goreman_cmd="goreman start"
generate_proc_file="./generate_procfile.sh"
benchmark_tool="go run ./tools/benchmark"  # Replace with the path to the benchmark tool

# Loop through configurations
for branch in "${branches[@]}"; do
    # Checkout the branch and rebuild
    echo "Checking out branch $branch and rebuilding..."
    git checkout "$branch" || exit 1
    make build || exit 1

    for node_count in "${nodes[@]}"; do
        # Generate a Procfile for the current node count
        echo "Generating Procfile for $node_count nodes..."
        $generate_proc_file "$node_count" || exit 1

        for val_size in "${value_sizes[@]}"; do
            for i in $(seq 1 "$iterations"); do
                echo "Running benchmark: branch=$branch, nodes=$node_count, val_size=$val_size, iteration=$i"

                # Clean up previous run data
                $clean_script

                # Start etcd cluster
                $goreman_cmd > etcd_cluster.log 2>&1 &  # Redirects both stdout and stderr to etcd_cluster.log
                etcd_pid=$!

                # Wait for etcd to start (add delay if necessary)
                sleep 5

                benchmark_cmd="put --clients=$clients --val-size=$val_size --sequential-keys --conns=100 --compact-index-delta=2000000000 --compact-interval=60m"

                # Run warmup
                echo "Running warmup with $warmup_requests requests..."
                $benchmark_tool $benchmark_cmd --total=$warmup_requests

                # Run benchmark
                output_file="${branch},${node_count},${val_size},${benchmark_requests}-${i}.out"
                echo "Running benchmark with $benchmark_requests requests, output to $output_file..."
                $benchmark_tool $benchmark_cmd --total=$benchmark_requests > "$output_dir/$output_file"

                # Stop etcd
                kill $etcd_pid
                wait $etcd_pid 2>/dev/null
            done
        done
    done
done

echo "Benchmarking complete."
