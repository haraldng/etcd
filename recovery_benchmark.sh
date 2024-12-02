#!/bin/bash

# Check if the configuration file is passed as an argument
if [ $# -lt 1 ]; then
  echo "Usage: $0 <config_file>"
  exit 1
fi

CONFIG_FILE=$1

# Validate if the configuration file exists
if ! [ -f "$CONFIG_FILE" ]; then
  echo "Configuration file $CONFIG_FILE not found!"
  exit 1
fi

BENCHMARK_TOOL="go run ./tools/benchmark"
RECOVERY_SCRIPT="./recovery.sh"
SERVER_BIN="./metro_recovery/server/server"
IP_FILE="cloud_bench_config.txt"
WAL_SERVER_PORT=50051
SLEEP=10

# Parse configurations using jq
branches=($(jq -r '.branches[]' "$CONFIG_FILE"))
nodes=($(jq -r '.nodes[]' "$CONFIG_FILE"))
value_rate_pairs=($(jq -c '.value_rate_pairs[]' "$CONFIG_FILE"))
proposals=($(jq -r '.proposals[]' "$CONFIG_FILE"))
output_dir=$(jq -r '.output_dir' "$CONFIG_FILE")
iterations=$(jq -r '.iterations' "$CONFIG_FILE")
base_data_dir=$(jq -r '.data_dir' "$CONFIG_FILE")
etcd_binary=$(jq -r '.etcd_binary' "$CONFIG_FILE")
num_to_stop=$(jq -r '.nodes_to_stop' "$CONFIG_FILE")

mkdir -p "$output_dir"
cp "$CONFIG_FILE" "$output_dir/"

if ! [ -f "$IP_FILE" ]; then
  echo "SSH configuration file $IP_FILE not found!"
  exit 1
fi

USERNAME=$(head -n 1 "$IP_FILE")
readarray -t IP_ADDRESSES < <(tail -n +2 "$IP_FILE")

TOTAL_NODES=${#IP_ADDRESSES[@]}
CLUSTER_TOKEN="etcd-cluster-1"

# Generate peers.txt file in the base directory
PEERS_FILE="peers.txt"
> "$PEERS_FILE" # Truncate the file if it exists

for ip in "${IP_ADDRESSES[@]}"; do
  echo ":$WAL_SERVER_PORT" >> "$PEERS_FILE"
done

# Synchronize peers.txt to all nodes
for ip in "${IP_ADDRESSES[@]}"; do
  scp "$PEERS_FILE" "$USERNAME@$ip:~/etcd/"
done

# Cluster initialization string
INITIAL_CLUSTER=""
for i in "${!IP_ADDRESSES[@]}"; do
  NODE_NAME="infra$((i + 1))"
  NODE_IP="${IP_ADDRESSES[i]}"
  INITIAL_CLUSTER+="$NODE_NAME=http://$NODE_IP:2380"
  if [ "$i" -lt $((${#IP_ADDRESSES[@]} - 1)) ]; then
    INITIAL_CLUSTER+=","
  fi
done

endpoints=$(IFS=, ; echo "${IP_ADDRESSES[*]/%/:2379}")

# SSH functions
prepare_data_dirs() {
  for ip in "${IP_ADDRESSES[@]}"; do
    ssh "$USERNAME@$ip" "mkdir -p $base_data_dir && chmod -R u+rwx $base_data_dir" || { echo "ERROR: Failed to prepare directories on VM $ip"; exit 1; }
  done
}

stop_nodes() {
  for i in $(seq 1 "$num_to_stop"); do
    NODE_IP="${IP_ADDRESSES[$((i - 1))]}"
    ssh "$USERNAME@$NODE_IP" "pkill etcd || true"
  done
}

start_etcd_cluster() {
  for i in "${!IP_ADDRESSES[@]}"; do
    NODE_NAME="infra$((i + 1))"
    NODE_IP="${IP_ADDRESSES[i]}"
    ssh "$USERNAME@$NODE_IP" "nohup $etcd_binary --name $NODE_NAME \
      --listen-client-urls http://$NODE_IP:2379 \
      --advertise-client-urls http://$NODE_IP:2379 \
      --listen-peer-urls http://$NODE_IP:2380 \
      --initial-advertise-peer-urls http://$NODE_IP:2380 \
      --initial-cluster-token $CLUSTER_TOKEN \
      --initial-cluster '$INITIAL_CLUSTER' \
      --data-dir=$base_data_dir/$NODE_NAME > $output_dir/$NODE_NAME.log 2>&1 &"
  done
  sleep 10
}

start_healthy_servers() {
  for i in $(seq $((num_to_stop + 1)) "$num_nodes"); do
    NODE_NAME="infra$i"
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
  done
}

start_faulty_servers() {
  for i in $(seq 1 "$num_to_stop"); do
    NODE_NAME="infra$i"
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
  done
}

run_benchmark() {
  local mode=$1
  local total_requests=$2
  local log_file=$3
  $BENCHMARK_TOOL put --endpoints=$endpoints --clients=100 --val-size=16 --sequential-keys --conns=100 --total=$total_requests > "$log_file"
}

start_collecting_metrics() {
  while true; do
    TIMESTAMP=$(date +%s)
    for i in "${!IP_ADDRESSES[@]}"; do
      NODE_IP="${IP_ADDRESSES[i]}"
      metrics=$(ssh "$USERNAME@$NODE_IP" "curl -s http://$NODE_IP:2379/metrics")
      echo "$TIMESTAMP,infra$((i + 1)),$metrics" >> "$output_dir/metrics.csv"
    done
    sleep 5
  done &
  echo $! > "$output_dir/metrics_collector.pid"
}

stop_collecting_metrics() {
  if [ -f "$output_dir/metrics_collector.pid" ]; then
    kill "$(cat $output_dir/metrics_collector.pid)" || true
    rm "$output_dir/metrics_collector.pid"
  fi
}

# Main script logic
prepare_data_dirs
start_collecting_metrics

for branch in "${branches[@]}"; do
  echo "Checking out branch $branch..."
  for ip in "${IP_ADDRESSES[@]}"; do
    ssh "$USERNAME@$ip" "cd etcd && git checkout $branch && git pull && make build"
  done

  for value_rate in "${value_rate_pairs[@]}"; do
    val_size=$(echo "$value_rate" | jq -r '.value_size')
    rate=$(echo "$value_rate" | jq -r '.rate')

    for proposal_count in "${proposals[@]}"; do
      for i in $(seq 1 "$iterations"); do
        echo "Starting iteration $i for branch $branch..."
        start_etcd_cluster
        sleep 3
        start_collecting_metrics

        run_benchmark $proposal_count "$output_dir/${branch}_warmup_${i}.log"

        echo "Simulating node failures..."
        stop_nodes

        start_healthy_servers

        sleep $SLEEP

        echo "Starting faulty servers..."
        start_faulty_servers

        sleep $SLEEP
        run_benchmark $proposal_count "$output_dir/${branch}_benchmark_${i}_proposals_${proposal_count}.log"

        echo "Iteration $i completed for branch $branch."
      done
    done
  done
done

stop_collecting_metrics
echo "Cloud benchmarking complete."