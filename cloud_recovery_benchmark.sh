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
nodes_stop_pairs=($(jq -c '.nodes[]' "$config_file"))
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

    for node_stop in "${nodes[@]}"; do
        node_count=$(echo "$value_rate" | jq -r '.nodes')
        stop_count=$(echo "$value_rate" | jq -r '.stop')
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

                        stop_nodes

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

stop_nodes() {
  if ! $LOCAL_MODE; then
    for i in $(seq 1 "$num_to_stop"); do
      NODE_IP="${IP_ADDRESSES[$((i - 1))]}"
      ssh "$USERNAME@$NODE_IP" "pkill etcd || true"
    done
  else
    for i in $(seq 1 "$num_to_stop"); do
      NODE_IP="${IP_ADDRESSES[$((i - 1))]}"
      pkill etcd || true
    done
  fi
}

start_healthy_servers() {
    for i in $(seq $((num_to_stop + 1)) "$nodes"); do
      NODE_NAME="infra$i"
      if ! $LOCAL_MODE; then
        NODE_IP="${IP_ADDRESSES[$((i - 1))]}"
        server_log="$output_dir/server_${NODE_NAME}.log"
        data_dir="$base_data_dir/$NODE_NAME"
        copy_dir="$base_data_dir/copied_$NODE_NAME"

        echo "Preparing healthy server $NODE_NAME on $NODE_IP..."

        # Ensure the data directory is copied to a separate location
        ssh "$USERNAME@$NODE_IP" "
          mkdir -p $copy_dir && \
          cp -r $data_dir/* $copy_dir/ && \
          echo 'Copied data directory for $NODE_NAME to $copy_dir.'
        "

        # Start the server in "server" mode using the copied data directory
        echo "Starting server program for healthy server $NODE_NAME..."
        ssh "$USERNAME@$NODE_IP" "
          nohup $SERVER_BIN --mode=server --port=$WAL_SERVER_PORT \
            --data-dir=$copy_dir --peers-file=$base_data_dir/peers.txt \
            > $server_log 2>&1 &
        "
        echo "Healthy server $NODE_NAME started with logs at $server_log."
      else
        local port=$((50050 + i))
        local log_file="$LOCAL_LOG_DIR/recovery_${node_name}.log"

        # Copy the data directory to LOCAL_COPY_DIR for normal server mode
        local_copy_data_directory "$NODE_NAME"
        data_dir="$LOCAL_COPY_DIR/$NODE_NAME"

        $LOCAL_SERVER_BINARY --mode="$mode" --ip="$LOCAL_IP" --port="$port" --data-dir="$data_dir/member/wal" --peers-file="$peers" > "$log_file" 2>&1;
      fi
    done
}

start_faulty_servers() {
  for i in $(seq 1 "$num_to_stop"); do
    NODE_NAME="infra$i"
    if ! $LOCAL_MODE; then
      NODE_IP="${IP_ADDRESSES[$((i - 1))]}"
      recovery_log="$output_dir/recover_${NODE_NAME}.log"

      echo "Starting recovery script for faulty server $NODE_NAME on $NODE_IP..."

      # Execute the recovery script in the background
      ssh "$USERNAME@$NODE_IP" "nohup $RECOVERY_SCRIPT --node-name $NODE_NAME --port $WAL_SERVER_PORT \
        --data-dir $base_data_dir/$NODE_NAME --peers-file $base_data_dir/peers.txt \
        --etcd-binary $etcd_binary --server-binary $SERVER_BIN \
        --cluster-token $CLUSTER_TOKEN --initial-cluster '$INITIAL_CLUSTER' \
        --output-dir $output_dir > $recovery_log 2>&1 &"

      echo "Recovery script started for $NODE_NAME."
    else
      local port=$((50050 + i))
      local log_file="$LOCAL_LOG_DIR/recovery_${node_name}.log"

      data_dir="$LOCAL_DATA_DIR/$NODE_NAME"

      if $SERVER_BINARY --mode="$mode" --ip="$LOCAL_IP" --port="$port" --data-dir="$data_dir/member/wal" --peers-file="$peers" > "$log_file" 2>&1; then
        echo "Recovery successful for $node_name. Restarting with recovered WAL..."
        local_restart_etcd_with_recovered_wal "$i"
      fi
    fi
  done
}

# Function to copy the relevant directory structure and WAL
local_copy_data_directory() {
  local node_name=$1
  local source_dir="$DATA_DIR/$node_name"
  local target_dir="$LOCAL_COPY_DIR/$node_name"

  echo "Copying entire data directory for $node_name..."
  mkdir -p "$target_dir"

  # Copy the entire source directory to the target directory
  cp -r "$source_dir/" "$target_dir/"

  echo "Copied data directory for $node_name to $target_dir."
}

# Function to restart an etcd node with the recovered data directory
local_restart_etcd_with_recovered_wal() {
  local i=$1

  echo "Preparing to restart etcd node $node_name with recovered WAL..."

  NODE_NAME="infra$i"
  DATA_PATH="$DATA_DIR/$NODE_NAME"

  # Calculate ports for client and peer connections based on index
  client_port=$((2379 + (i - 1) * 10000))
  peer_port=$((2380 + (i - 1) * 10000))
  cluster_members+="${infra_name}=http://$LOCAL_IP:${peer_port},"

  nohup $ETCD_BINARY --name $NODE_NAME \
    --listen-client-urls http://$LOCAL_IP:$client_port \
    --advertise-client-urls http://$LOCAL_IP:$client_port \
    --listen-peer-urls http://$LOCAL_IP:$peer_port \
    --initial-advertise-peer-urls http://$LOCAL_IP:$peer_port \
    --initial-cluster-token $CLUSTER_TOKEN \
    --initial-cluster "$INITIAL_CLUSTER" \
    --initial-cluster-state new \
    --data-dir="$DATA_PATH" \
    --logger=zap \
    --metrics=extensive \
    > "$LOG_DIR/$NODE_NAME-recovered.log" 2>&1 &

  echo $! > "$LOG_DIR/$NODE_NAME.pid"
  echo "Restarted node $node_name."
}