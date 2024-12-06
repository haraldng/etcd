#!/bin/bash

LOCAL_MODE=false
for arg in "$@"; do
  if [ "$arg" == "--local" ]; then
    LOCAL_MODE=true
    break
  fi
done

echo "running in local mode: $LOCAL_MODE"

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

ETCD_BINARY="./bin/etcd"
BENCHMARK_TOOL="go run ./tools/benchmark"
RECOVERY_SCRIPT="./overhead.sh"
SERVER_BINARY="./metro_recovery/server/server"
IP_FILE="cloud_bench_config.txt"
WAL_SERVER_PORT=50051
SLEEP=3

# Parse configurations using jq
branches=($(jq -r '.branches[]' "$CONFIG_FILE"))
nodes=($(jq -r '.nodes[]' "$CONFIG_FILE"))
value_rate_pairs=($(jq -c '.value_rate_pairs[]' "$CONFIG_FILE"))
proposals=($(jq -r '.proposals[]' "$CONFIG_FILE"))
output_dir=$(jq -r '.output_dir' "$CONFIG_FILE")
iterations=$(jq -r '.iterations' "$CONFIG_FILE")
base_data_dir=$(jq -r '.data_dir' "$CONFIG_FILE")
num_to_stop=$(jq -r '.nodes_to_stop' "$CONFIG_FILE")
quorum_size=($(jq -r '.quorum_size[]' "$CONFIG_FILE"))
# local constants
LOCAL_LOG_DIR="local_test"
LOCAL_DATA_DIR="local_test"
LOCAL_COPY_DIR="/Users/haraldng/code/etcd/copied_data"
LOCAL_SERVER_BINARY="./metro_recovery/server/server"
LOCAL_IP="127.0.0.1"

mkdir -p "$output_dir"
cp "$CONFIG_FILE" "$output_dir/"

if ! $LOCAL_MODE; then
  if ! [ -f "$IP_FILE" ]; then
    echo "SSH configuration file $IP_FILE not found!"
    exit 1
  fi
fi

USERNAME=$(head -n 1 "$IP_FILE")
readarray -t IP_ADDRESSES < <(tail -n +2 "$IP_FILE")

TOTAL_NODES=${#IP_ADDRESSES[@]}
CLUSTER_TOKEN="etcd-cluster-1"

# Generate peers.txt file in the base directory
PEERS_FILE="peers.txt"
> "$PEERS_FILE" # Truncate the file if it exists

if ! $LOCAL_MODE; then
  for ip in "${IP_ADDRESSES[@]}"; do
    echo "$ip:$WAL_SERVER_PORT" >> "$PEERS_FILE"
  done
else
  for i in $(seq 1 $nodes); do
    echo "$LOCAL_IP:$((WAL_SERVER_PORT + (i-1)))" >> "$PEERS_FILE"
  done
fi

if ! $LOCAL_MODE; then
  # Synchronize peers.txt to all nodes
  for ip in "${IP_ADDRESSES[@]}"; do
    scp "$PEERS_FILE" "$USERNAME@$ip:~/etcd/"
  done
fi

# Cluster initialization string
INITIAL_CLUSTER=""

if ! $LOCAL_MODE; then
  for i in "${!IP_ADDRESSES[@]}"; do
    NODE_NAME="infra$((i + 1))"
    NODE_IP="${IP_ADDRESSES[i]}"
    INITIAL_CLUSTER+="$NODE_NAME=http://$NODE_IP:2380"
    if [ "$i" -lt $((${#IP_ADDRESSES[@]} - 1)) ]; then
      INITIAL_CLUSTER+=","
    fi
  done
else
  for i in $(seq 1 $nodes); do
    NODE_NAME="infra$i"
    peer_port=$((2380 + (i - 1) * 10000))
    INITIAL_CLUSTER+="$NODE_NAME=http://$LOCAL_IP:$peer_port"
    if [ "$i" -lt $nodes ]; then
      INITIAL_CLUSTER+=","
    fi
  done
fi

if ! $LOCAL_MODE; then
  endpoints=$(IFS=, ; echo "${IP_ADDRESSES[*]/%/:2379}")
else
  for i in $(seq 1 $nodes); do
    endpoints+="http://$LOCAL_IP:$((2379 + (i - 1) * 10000)) "
  done
fi

# SSH functions
prepare_data_dirs() {
  if ! $LOCAL_MODE; then
    for ip in "${IP_ADDRESSES[@]}"; do
      ssh "$USERNAME@$ip" "mkdir -p $base_data_dir && chmod -R u+rwx $base_data_dir" || { echo "ERROR: Failed to prepare directories on VM $ip"; exit 1; }
      ssh "$USERNAME@$ip" "sudo rm -rf $base_data_dir/* || { echo 'WARNING: Failed to remove some files in $base_data_dir on VM $ip'; }"
      ssh "$USERNAME@$ip" "mkdir -p $output_dir && chmod -R u+rwx $output_dir" || { echo "ERROR: Failed to prepare directories on VM $ip"; exit 1; }

    done
  fi
}

stop_nodes() {
  if ! $LOCAL_MODE; then
    for i in $(seq 1 "$nodes"); do
      NODE_IP="${IP_ADDRESSES[$((i - 1))]}"
      echo "Stopping etcd on node $NODE_IP..."
      ssh "$USERNAME@$NODE_IP" "
        while pgrep etcd > /dev/null; do
          pkill etcd
          sleep 1
        done
        echo 'Etcd process terminated on $NODE_IP.'
      " || {
        echo "Failed to stop etcd on $NODE_IP. Exiting."
        exit 1
      }
    done
  else
    for i in $(seq 1 "$nodes"); do
      PID_FILE="$LOCAL_DATA_DIR/infra$i.pid"
      if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        echo "Attempting to stop etcd process with PID $PID for infra$i..."

        while kill -9 "$PID" 2>/dev/null; do
          kill "$PID"
          sleep 1
        done

        echo "Process $PID for infra$i has been successfully terminated."
        rm "$PID_FILE"
      else
        echo "PID file not found for infra$i. Skipping."
      fi
    done
  fi
}

start_etcd_cluster() {
  local benchmark_counter=$1
  local j=$2
  ITERATION_DATA_DIR="$base_data_dir/${benchmark_counter}-${j}"
  NODE_LOG="$ITERATION_DATA_DIR/etcd.log"
  if ! $LOCAL_MODE; then
    for i in "${!IP_ADDRESSES[@]}"; do
      NODE_NAME="infra$((i + 1))"
      NODE_IP="${IP_ADDRESSES[i]}"
      ssh "$USERNAME@$NODE_IP" "mkdir -p $ITERATION_DATA_DIR ; cd etcd ; nohup $ETCD_BINARY --name $NODE_NAME \
        --listen-client-urls http://$NODE_IP:2379 \
        --advertise-client-urls http://$NODE_IP:2379 \
        --listen-peer-urls http://$NODE_IP:2380 \
        --initial-advertise-peer-urls http://$NODE_IP:2380 \
        --initial-cluster-token $CLUSTER_TOKEN \
        --initial-cluster '$INITIAL_CLUSTER' \
        --initial-cluster-state new \
        --log-level error \
        --snapshot-count=20000000 \
        --data-dir=$ITERATION_DATA_DIR > $NODE_LOG 2>&1 &"
    done
  else
    for i in $(seq 1 $nodes); do
    NODE_NAME="infra$i"
    DATA_PATH="$LOCAL_DATA_DIR/$NODE_NAME"
    mkdir -p "$DATA_PATH"
    # Calculate ports for client and peer connections based on index
    client_port=$((2379 + (i - 1) * 10000))
    peer_port=$((2380 + (i - 1) * 10000))
    echo $client_port
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
      > "$LOCAL_LOG_DIR/$NODE_NAME.log" 2>&1 &
    echo $! > "$LOCAL_LOG_DIR/$NODE_NAME.pid"
  done

  echo "Local etcd cluster started."
  fi
}

start_healthy_servers() {
  local iteration_data_dir=$1
  local q=$2
    for i in $(seq $((num_to_stop + 1)) "$nodes"); do
      NODE_NAME="infra$i"
      echo "Starting server program for healthy server $NODE_NAME..."
      if ! $LOCAL_MODE; then
        NODE_IP="${IP_ADDRESSES[$((i - 1))]}"
        server_log="$iteration_data_dir/server_${NODE_NAME}.log"

        echo "Preparing healthy server $NODE_NAME on $NODE_IP..."

        # Start the server in "server" mode using the copied data directory
        ssh "$USERNAME@$NODE_IP" "cd etcd ;
          nohup $SERVER_BINARY --mode server --ip $NODE_IP --port $WAL_SERVER_PORT \
            --data-dir $iteration_data_dir/member/wal --peers-file peers.txt \
            > $server_log 2>&1 &
        "
        echo "Healthy server $NODE_NAME started with logs at $server_log."
      else
        local port=$((50050 + i))
        local log_file="$LOCAL_LOG_DIR/recovery_${NODE_NAME}.log"

        data_dir="$LOCAL_COPY_DIR/$NODE_NAME"

        nohup $LOCAL_SERVER_BINARY --mode server --ip "$LOCAL_IP" --port "$port" --data-dir "$data_dir/member/wal" --peers-file $PEERS_FILE --quorum_size "$q" > "$log_file" 2>&1 &
      fi
    done
}

# Function to copy the relevant directory structure and WAL
local_copy_data_directory() {
  local node_name=$1
  local source_dir="$LOCAL_DATA_DIR/$node_name"
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

  NODE_NAME="infra$i"
  echo "Preparing to restart etcd node $NODE_NAME with recovered WAL..."

  DATA_PATH="$LOCAL_DATA_DIR/$NODE_NAME"

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
    > "$LOCAL_LOG_DIR/$NODE_NAME-recovered.log" 2>&1 &

  echo $! > "$LOCAL_LOG_DIR/$NODE_NAME.pid"
  echo "Restarted node $NODE_NAME."
}

start_faulty_servers() {
  local results_file=$1
  local iteration_data_dir=$2
  for i in $(seq 1 "$num_to_stop"); do
    NODE_NAME="infra$i"

    if ! $LOCAL_MODE; then
      NODE_IP="${IP_ADDRESSES[$((i - 1))]}"
      local recovery_log="$base_data_dir/recover_${NODE_NAME}.log"

      echo "Starting recovery script for faulty server $NODE_NAME on $NODE_IP..."

      # Execute the recovery script in the background
      ssh "$USERNAME@$NODE_IP" "cd etcd ; nohup $RECOVERY_SCRIPT --node-name $NODE_NAME --ip $NODE_IP --port $WAL_SERVER_PORT \
        --data-dir $iteration_data_dir/member/wal --peers-file peers.txt \
        --etcd-binary $ETCD_BINARY --server-binary $SERVER_BINARY \
        --cluster-token $CLUSTER_TOKEN --initial-cluster $INITIAL_CLUSTER \
        --output-dir $iteration_data_dir --results-file $results_file > $recovery_log 2>&1 &"

      echo "Recovery script started for $NODE_NAME."
    else
      local port=$((50050 + i))
      local data_dir="$LOCAL_DATA_DIR/$NODE_NAME"
      local recovery_log="$LOCAL_LOG_DIR/recover_${NODE_NAME}.log"
      OVERHEAD_FILE="$results_file-$NODE_NAME"

      nohup $RECOVERY_SCRIPT --node-name $NODE_NAME --ip $LOCAL_IP --port $port \
        --data-dir $data_dir/member/wal --peers-file $PEERS_FILE \
        --etcd-binary $ETCD_BINARY --server-binary $SERVER_BINARY \
        --cluster-token $CLUSTER_TOKEN --initial-cluster $INITIAL_CLUSTER \
        --quorum-size $q \
        --output-dir $data_dir --results-file $OVERHEAD_FILE > $recovery_log 2>&1 &

#      if $SERVER_BINARY --mode="$mode" --ip="$LOCAL_IP" --port="$port" --data-dir="$data_dir/member/wal" --peers-file="$PEERS_FILE" > "$log_file" 2>&1; then
#        echo "Recovery successful for $NODE_NAME. Restarting with recovered WAL..."
#        local_restart_etcd_with_recovered_wal "$i"
#      fi
    fi
  done
}

run_benchmark() {
  local val_size=$1
  local total_requests=$2
  local rate=$3
  local log_file=$4

  echo "endpoints: $endpoints"
  echo "Running benchmark with value size $val_size and total requests $total_requests..."
  $BENCHMARK_TOOL put --endpoints=$endpoints --clients=1024 --val-size=$val_size --sequential-keys --conns=100 --total=$total_requests --rate=$rate > "$log_file"
}

start_collecting_metrics() {
  local output_file=$1
  echo "TS,Node,Committed,Applied" > "$output_dir/$output_file"
  if ! $LOCAL_MODE; then
    while true; do
      TIMESTAMP=$(date +%s)
        for i in "${!IP_ADDRESSES[@]}"; do
          NODE_IP="${IP_ADDRESSES[i]}"
          METRICS=$(curl -s "http://$NODE_IP:2379/metrics" | grep -E '^etcd_server_proposals_(committed|applied)_total ')
          COMMITTED_TOTAL=$(echo "$METRICS" | grep '^etcd_server_proposals_committed_total ' | awk '{print $2}')
          APPLIED_TOTAL=$(echo "$METRICS" | grep '^etcd_server_proposals_applied_total ' | awk '{print $2}')
          if [[ -z "$COMMITTED_TOTAL" || ! "$COMMITTED_TOTAL" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            COMMITTED_TOTAL=0
          fi
          if [[ -z "$APPLIED_TOTAL" || ! "$APPLIED_TOTAL" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            APPLIED_TOTAL=0
          fi
        done
        sleep 1
        done &
        echo $! > "$output_dir/metrics_collector.pid"
  else
    while true; do
      TIMESTAMP=$(date +%s)
      for i in $(seq 1 $nodes); do
        client_port=$((2379 + (i - 1) * 10000))
        # Fetch both committed and applied metrics
        METRICS=$(curl -s "http://$LOCAL_IP:$client_port/metrics" | grep -E '^etcd_server_proposals_(committed|applied)_total ')
        COMMITTED_TOTAL=$(echo "$METRICS" | grep '^etcd_server_proposals_committed_total ' | awk '{print $2}')
        APPLIED_TOTAL=$(echo "$METRICS" | grep '^etcd_server_proposals_applied_total ' | awk '{print $2}')
        if [[ -z "$COMMITTED_TOTAL" || ! "$COMMITTED_TOTAL" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
          COMMITTED_TOTAL=0
        fi
        if [[ -z "$APPLIED_TOTAL" || ! "$APPLIED_TOTAL" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
          APPLIED_TOTAL=0
        fi
        echo "$TIMESTAMP,infra$i,$COMMITTED_TOTAL,$APPLIED_TOTAL" >> "$output_dir/$output_file"
      done
      sleep 1
    done &
    echo $! > "$LOCAL_LOG_DIR/metrics_collector.pid"
  fi
}

stop_collecting_metrics() {
  if ! $LOCAL_MODE; then
    if [ -f "$output_dir/metrics_collector.pid" ]; then
      kill "$(cat $output_dir/metrics_collector.pid)" || true
      rm "$output_dir/metrics_collector.pid"
    fi
  else
    kill "$(cat $LOCAL_LOG_DIR/metrics_collector.pid)"
    rm "$LOCAL_LOG_DIR/metrics_collector.pid"
  fi
}


local_cleanup() {
  killall etcd
  rm -rf $LOCAL_COPY_DIR
  pkill -f metro_recovery ; pkill -f recovery_benchmark
  sleep 3
  killall etcd
  pkill -f metro_recovery ; pkill -f recovery_benchmark
}

# Main script logic
prepare_data_dirs

benchmark_counter=0

for branch in "${branches[@]}"; do
  echo "Checking out branch $branch..."
  for ip in "${IP_ADDRESSES[@]}"; do
    ssh "$USERNAME@$ip" "cd etcd && git checkout $branch && git pull && make build"
    ssh "$USERNAME@$ip" "cd etcd/metro_recovery/server ; go build -o server "
  done

  for value_rate in "${value_rate_pairs[@]}"; do
    val_size=$(echo "$value_rate" | jq -r '.value_size')
    rate=$(echo "$value_rate" | jq -r '.rate')

    for proposal_count in "${proposals[@]}"; do
      benchmark_counter=$((benchmark_counter + 1))
      for q in "${quorum_size[@]}"; do
        for i in $(seq 1 "$iterations"); do
          echo "Benchmark $benchmark_counter: Branch=$branch, Nodes=$nodes, Value Size=$val_size, Rate=$rate, Proposal Count=$proposal_count, Quorum Size=$q"
          ITERATION_DATA_DIR="$base_data_dir/${benchmark_counter}-${i}"
          output_file="${output_dir}/${branch},${nodes}-${q},${num_to_stop},${val_size},${rate},${proposal_count}-${i}.out"

          echo "Stopping etcd processes and cleaning data directory on all VMs..."
          for ip in "${IP_ADDRESSES[@]}"; do
              ssh "$USERNAME@$ip" "killall etcd || true" || { echo "ERROR: Failed to stop etcd on VM $ip"; exit 1; }
              ssh "$USERNAME@$ip" "sudo rm -rf $base_data_dir/* || { echo 'WARNING: Failed to remove some files in $base_data_dir on VM $ip'; }"
          done

          echo "Starting iteration $i for branch $branch..."
          start_etcd_cluster $benchmark_counter $i
          sleep $SLEEP
  #        start_collecting_metrics $output_file

          run_benchmark $val_size $proposal_count $rate "$output_dir/${branch}_warmup_${i}.log"

          echo "Stopping all nodes"
          stop_nodes
          sleep $SLEEP

          echo "Starting recovery servers..."
          start_healthy_servers $ITERATION_DATA_DIR $q
          echo "ok"
          sleep $SLEEP

          echo "Starting faulty servers..."
          start_faulty_servers $output_file $ITERATION_DATA_DIR $q

          sleep $SLEEP

  #        run_benchmark $val_size $proposal_count $rate "$output_dir/${branch}_benchmark_${i}_proposals_${proposal_count}.log"
  #        stop_collecting_metrics
          echo "Iteration $i completed for branch $branch."
          # Stop etcd on each instance after the benchmark run

          echo "Sleeping for $SLEEP seconds to allow the cluster to stabilize..."
          sleep "$SLEEP"

          echo "Stopping etcd on all VMs after benchmark run $benchmark_counter (iteration $i)..."
          if ! $LOCAL_MODE; then
            for j in $(seq 1 "$num_to_stop"); do
              NODE_NAME="infra$j"
              NODE_IP="${IP_ADDRESSES[$((j - 1))]}"
              scp "$USERNAME@$NODE_IP:$output_file" "$output_dir/${branch},${nodes},${q},${num_to_stop},${val_size},${rate},${proposal_count},$NODE_NAME-${i}.out"
            done

            for ip in "${IP_ADDRESSES[@]}"; do
                ssh "$USERNAME@$ip" "killall etcd" || { echo "ERROR: Failed to stop etcd on VM $ip"; }
  #              ssh "$USERNAME@$ip" "sudo rm -rf $ITERATION_DATA_DIR || { echo 'WARNING: Failed to remove some files in $ITERATION_DATA_DIR on VM $ip'; }"
            done
          else
            local_cleanup
          fi
        done
      done
    done
  done
done

trap local_cleanup EXIT
trap local_cleanup SIGINT SIGTERM

echo "Cloud benchmarking complete."