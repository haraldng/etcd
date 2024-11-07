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
value_rate_pairs=($(jq -c '.value_rate_pairs[]' "$config_file"))  # Parse value_rate_pairs as an array of tuples
clients=($(jq -r '.clients[]' "$config_file"))
use_snapshot=($(jq -r '.use_snapshot[]' "$config_file"))
warmup_requests=$(jq -r '.request_count.warmup' "$config_file")
benchmark_requests=$(jq -r '.request_count.benchmark' "$config_file")
output_dir=$(jq -r '.output_dir' "$config_file")
iterations=$(jq -r '.iterations' "$config_file")
base_data_dir=$(jq -r '.data_dir' "$config_file")
sleep_time=$(jq -r '.sleep_time' "$config_file")
quota_backend_bytes=$(jq -r '.quota_backend_bytes' "$config_file")

# Validate base_data_dir
if [ -z "$base_data_dir" ] || [ "$base_data_dir" == "null" ]; then
  echo "ERROR: 'data_dir' must be specified in the configuration file."
  exit 1
fi

# Validate sleep_time
if [ -z "$sleep_time" ] || [ "$sleep_time" == "null" ]; then
  sleep_time=60
fi

# Use a default output directory if not set
if [ -z "$output_dir" ] || [ "$output_dir" == "null" ]; then
  output_dir="$(date +'%Y%m%d_%H%M%S')"
fi

output_dir="bench_results/$output_dir"
mkdir -p "$output_dir"
echo "Output directory: $output_dir"

# SSH configuration file
IP_FILE="cloud_bench_config.txt"

# Validate if IP file exists
if ! [ -f "$IP_FILE" ]; then
  echo "SSH configuration file $IP_FILE not found!"
  exit 1
fi

benchmark_tool="go run ./tools/benchmark"  # Replace with the path to the benchmark tool

# Read SSH username and IPs
USERNAME=$(head -n 1 "$IP_FILE")
readarray -t IP_ADDRESSES < <(tail -n +2 "$IP_FILE")

# Cluster token for etcd
CLUSTER_TOKEN="etcd-cluster-1"

# Build the initial cluster string
INITIAL_CLUSTER=""
for i in "${!IP_ADDRESSES[@]}"; do
  NODE_NAME="infra$((i+1))"
  NODE_IP="${IP_ADDRESSES[i]}"
  INITIAL_CLUSTER+="$NODE_NAME=http://$NODE_IP:2380"
  if [ "$i" -lt $((${#IP_ADDRESSES[@]} - 1)) ]; then
    INITIAL_CLUSTER+=","
  fi
done

# Remote etcd endpoints (dynamically concatenated)
endpoints=$(IFS=, ; echo "${IP_ADDRESSES[*]/%/:2379}")

# Total number of benchmark configurations
total_benchmarks=$(( ${#branches[@]} * ${#nodes[@]} * ${#value_rate_pairs[@]} * ${#clients[@]} * ${#use_snapshot[@]} ))

# Initialize benchmark counter
benchmark_counter=0

# Prepare data directory on VMs
for ip in "${IP_ADDRESSES[@]}"; do
    echo "Setting up base data directory on VM $ip"
    ssh "$USERNAME@$ip" "sudo mkdir -p $base_data_dir && sudo chown -R $(whoami) $base_data_dir && chmod -R u+rwx $base_data_dir" || { echo "ERROR: Failed to set up data directory on VM $ip"; exit 1; }
done

# Start benchmarking
for branch in "${branches[@]}"; do
    echo "Checking out branch $branch and rebuilding on each VM..."
    for ip in "${IP_ADDRESSES[@]}"; do
        ssh "$USERNAME@$ip" "cd etcd && git checkout $branch && git pull && make build" || { echo "ERROR: Failed to build etcd on VM $ip"; exit 1; }
    done

    for node_count in "${nodes[@]}"; do
        for value_rate in "${value_rate_pairs[@]}"; do
            # Extract value_size and rate from the tuple
            val_size=$(echo "$value_rate" | jq -r '.value_size')
            rate=$(echo "$value_rate" | jq -r '.rate')
            for client_count in "${clients[@]}"; do
                for snap_enabled in "${use_snapshot[@]}"; do
                    benchmark_counter=$((benchmark_counter + 1))
                    echo "Benchmark $benchmark_counter/$total_benchmarks: Branch=$branch, Nodes=$node_count, Value Size=$val_size, Rate=$rate, Clients=$client_count, Snapshot=$snap_enabled"

                    for i in $(seq 1 "$iterations"); do
                        ITERATION_DATA_DIR="$base_data_dir/${benchmark_counter}-${i}"

                        echo "Stopping etcd processes and cleaning data directory on all VMs..."
                        for ip in "${IP_ADDRESSES[@]}"; do
                            ssh "$USERNAME@$ip" "killall etcd || true" || { echo "ERROR: Failed to stop etcd on VM $ip"; exit 1; }
                            ssh "$USERNAME@$ip" "sudo rm -rf $base_data_dir/* || { echo 'WARNING: Failed to remove some files in $base_data_dir on VM $ip'; }"
                        done

                        echo "Starting etcd on all VMs for benchmark run $benchmark_counter (iteration $i)..."
                        for j in "${!IP_ADDRESSES[@]}"; do
                            NODE_NAME="infra$((j+1))"
                            NODE_IP="${IP_ADDRESSES[j]}"
                            NODE_LOG="$ITERATION_DATA_DIR/etcd.log"
                            SNAPSHOT_FLAG=""
                            QUOTA_BACKEND_FLAG=""
                            if [ "$quota_backend_bytes" != "null" ]; then
                                QUOTA_BACKEND_FLAG="--quota-backend-bytes=$quota_backend_bytes"
                            fi

                            if [ "$snap_enabled" == "false" ]; then
                                SNAPSHOT_FLAG="--snapshot-count=20000000"
                            fi

                            ssh "$USERNAME@$NODE_IP" "cd etcd; mkdir -p $ITERATION_DATA_DIR; nohup bin/etcd --name $NODE_NAME \
                              --listen-client-urls http://$NODE_IP:2379 \
                              --advertise-client-urls http://$NODE_IP:2379 \
                              --listen-peer-urls http://$NODE_IP:2380 \
                              --initial-advertise-peer-urls http://$NODE_IP:2380 \
                              --initial-cluster-token $CLUSTER_TOKEN \
                              --initial-cluster '$INITIAL_CLUSTER' \
                              --initial-cluster-state new \
                              --log-level error \
                              --data-dir=$ITERATION_DATA_DIR \
                              $SNAPSHOT_FLAG \
                              $QUOTA_BACKEND_FLAG > $NODE_LOG 2>&1 &" || { echo "ERROR: Failed to start etcd on VM $NODE_IP"; exit 1; }

                            echo "etcd started on $NODE_NAME ($NODE_IP). Logs at $NODE_LOG"
                        done

                        sleep 10  # Wait for etcd cluster to stabilize

                        echo "Running warmup with $warmup_requests requests..."
                        benchmark_cmd="put --endpoints=$endpoints --clients=$client_count --val-size=$val_size --sequential-keys --conns=100 --rate=$rate"
                        $benchmark_tool $benchmark_cmd --total=$warmup_requests

                        output_file="${branch},${snap_enabled},${node_count},${val_size},${client_count},${benchmark_requests}-${i}.out"
                        echo "Running benchmark with $benchmark_requests requests, output to $output_file..."
                        $benchmark_tool $benchmark_cmd --total=$benchmark_requests > "$output_dir/$output_file"

                        # Stop etcd on each instance after the benchmark run
                        echo "Stopping etcd on all VMs after benchmark run $benchmark_counter/$total_benchmarks (iteration $i)..."
                        for ip in "${IP_ADDRESSES[@]}"; do
                            ssh "$USERNAME@$ip" "killall etcd" || { echo "ERROR: Failed to stop etcd on VM $ip"; exit 1; }
                        done

                        echo "Sleeping for $sleep_time seconds to allow the cluster to stabilize..."
                        sleep "$sleep_time"
                        ssh "$USERNAME@$ip" "sudo rm -rf $ITERATION_DATA_DIR || { echo 'WARNING: Failed to remove some files in $ITERATION_DATA_DIR on VM $ip'; }"
                    done
                done
            done
        done
    done
done

echo "Cloud benchmarking complete."
