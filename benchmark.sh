#!/bin/bash

# Check if the configuration file is passed as an argument
if [ $# -lt 1 ]; then
  echo "Usage: $0 <config_file>"
  exit 1
fi

config_file=$1

# Validate if the configuration file exists
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
clients=($(jq -r '.clients[]' "$config_file"))
iterations=$(jq -r '.iterations' "$config_file")
data_dir=$(jq -r '.data_dir' "$config_file")
quota_backend_bytes=$(jq -r '.quota_backend_bytes' "$config_file")

# Use a default directory if not set
if [ -z "$output_dir" ] || [ "$output_dir" == "null" ]; then
  output_dir="$(date +'%Y%m%d_%H%M%S')"
fi

output_dir="bench_results/$output_dir"
mkdir -p "$output_dir"
echo "Output directory: $output_dir"

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
        # Generate a Procfile for the current node count with data_dir and quota_backend_bytes
        echo "Generating Procfile for $node_count nodes with data_dir: $data_dir and quota_backend_bytes: $quota_backend_bytes..."
        if [ "$quota_backend_bytes" == "null" ]; then
            $generate_proc_file "$node_count" "$data_dir" || exit 1
        else
            $generate_proc_file "$node_count" "$data_dir" "$quota_backend_bytes" || exit 1
        fi

        for val_size in "${value_sizes[@]}"; do
              for client_count in "${clients[@]}"; do
                  for i in $(seq 1 "$iterations"); do
                      echo "Running benchmark: branch=$branch, nodes=$node_count, val_size=$val_size, clients=$client_count, iteration=$i"

                      # Clean up previous run data
                      rm -rf "$data_dir"/*

                      # Start etcd cluster
                      $goreman_cmd > etcd_cluster.log 2>&1 &  # Redirects both stdout and stderr to etcd_cluster.log
                      etcd_pid=$!

                      # Wait for etcd to start (add delay if necessary)
                      sleep 5

                      benchmark_cmd="put --clients=$client_count --val-size=$val_size --sequential-keys --conns=100"

                      # Run warmup
                      echo "Running warmup with $warmup_requests requests..."
                      $benchmark_tool $benchmark_cmd --total=$warmup_requests

                      # Run benchmark
                      output_file="${branch},${node_count},${val_size},snapshot=${snapshot},clients=${client_count},${benchmark_requests}-${i}.out"
                      echo "Running benchmark with $benchmark_requests requests, output to $output_file..."
                      $benchmark_tool $benchmark_cmd --total=$benchmark_requests > "$output_dir/$output_file"

                      # Stop etcd
                      kill $etcd_pid
                      sleep 5
                      wait $etcd_pid 2>/dev/null
                  done
              done
          done
    done
done

echo "Benchmarking complete."
