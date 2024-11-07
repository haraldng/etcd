#!/bin/bash

# Configuration parameters
X_PUTS=1000   # Number of initial PUT requests
Y_KILLS=1     # Number of nodes to kill
Z_WAIT=3     # Wait time in seconds before recovery
ETCD_BINARY="./bin/etcd"
SERVER_BINARY="./metro_recovery/server/server"
BENCH_CMD="go run ./tools/benchmark"
DATA_DIR="/Users/haraldng/code/etcd/local_test"
LOG_DIR="local_test"
COPY_DIR="/Users/haraldng/code/etcd/copied_data"
METRICS_LOG="local_test/metrics.csv"
RECOVERY_MODE="recover" # Recovery mode argument
PEERS_FILE="/Users/haraldng/code/etcd/local_test/local_peers.txt"

# Cluster token for etcd
CLUSTER_TOKEN="etcd-cluster-1"

# Clean up old directories and metrics log
rm -rf $DATA_DIR $LOG_DIR $COPY_DIR $METRICS_LOG
mkdir -p $DATA_DIR $LOG_DIR $COPY_DIR

# Local IP addresses for testing
LOCAL_IP="127.0.0.1"
PORT_START=2380
CLIENT_PORT_START=2379

# Number of nodes
TOTAL_NODES=3

# Build the initial cluster string
INITIAL_CLUSTER=""
for i in $(seq 1 $TOTAL_NODES); do
  NODE_NAME="infra$i"
  peer_port=$((2380 + (i - 1) * 10000))
  INITIAL_CLUSTER+="$NODE_NAME=http://$LOCAL_IP:$peer_port"
  if [ "$i" -lt $TOTAL_NODES ]; then
    INITIAL_CLUSTER+=","
  fi
done

# Function to start etcd nodes
start_etcd_cluster() {
  echo "Starting etcd cluster with $TOTAL_NODES nodes..."
  for i in $(seq 1 $TOTAL_NODES); do
    NODE_NAME="infra$i"
    DATA_PATH="$DATA_DIR/$NODE_NAME"
    mkdir -p "$DATA_PATH"
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
      > "$LOG_DIR/$NODE_NAME.log" 2>&1 &
    echo $! > "$LOG_DIR/$NODE_NAME.pid"
  done

  sleep 5
  echo "Etcd cluster started."
}

# Function to stop specific number of etcd nodes
stop_etcd_nodes() {
  echo "Stopping $Y_KILLS nodes..."
  for i in $(seq 1 $Y_KILLS); do
    PID_FILE="$LOG_DIR/infra$i.pid"
    if [ -f "$PID_FILE" ]; then
      kill "$(cat $PID_FILE)"
      rm "$PID_FILE"
      echo "Stopped infra$i."
    fi
  done
}

# Function to perform PUT requests using etcdctl benchmark
perform_put_benchmark() {
  local total_puts=$1
  local log_file=$2

  echo "Performing $total_puts PUT requests using etcdctl benchmark..."
  nohup $BENCH_CMD put --endpoints=http://$LOCAL_IP:2379 --clients=1000 --conns=100 --key-size=16 --sequential-keys --total=$total_puts > "$LOG_DIR/$log_file" 2>&1
  echo "PUT benchmark completed."
}

# Function to copy the relevant directory structure and WAL
copy_data_directory() {
  local node_name=$1
  local source_dir="$DATA_DIR/$node_name"
  local target_dir="$COPY_DIR/$node_name"

  echo "Copying entire data directory for $node_name..."
  mkdir -p "$target_dir"

  # Copy the entire source directory to the target directory
  cp -r "$source_dir/" "$target_dir/"

  echo "Copied data directory for $node_name to $target_dir."
}


# Function to replace the original data directory with the merged WAL data
replace_data_dir_with_recovered_wal() {
  local node_name=$1
  local original_data_path="$DATA_DIR/infra$node_name"
  local recovered_data_path="$COPY_DIR/infra$node_name"

  echo "Replacing original data directory for $node_name with the recovered data..."

  # Backup the original data directory (optional)
#  if [ -d "$original_data_path" ]; then
#    mv "$original_data_path" "${original_data_path}_backup_$(date +%s)"
#    echo "Original data directory for $node_name backed up."
#  fi

  # Replace the original data directory with the recovered one
  cp -r "$recovered_data_path" "$original_data_path"
  echo "Replaced original data directory for $node_name."
}

# Function to restart an etcd node with the recovered data directory
restart_etcd_with_recovered_wal() {
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

start_recovery_server() {
  local mode=$1
  local i=$2
  local peers=$3

  local node_name="infra$i"
  local port=$((50050 + i))
  local log_file="$LOG_DIR/recovery_${node_name}.log"
  local data_dir

  echo "Logging to $log_file"

  # Determine the data directory to use based on the mode
  if [ "$mode" = "recover" ]; then
    # Use the original data directory for recovery
    data_dir="$DATA_DIR/$node_name"
  else
    # Copy the data directory to COPY_DIR for normal server mode
    copy_data_directory "$node_name"
    data_dir="$COPY_DIR/$node_name"
  fi

  # Run the server binary with the determined data directory
  echo "Running server binary with mode: $mode, port: $port, data-dir: $data_dir, peers-file: $peers"
  if $SERVER_BINARY --mode="$mode" --ip="$LOCAL_IP" --port="$port" --data-dir="$data_dir/member/wal" --peers-file="$peers" > "$log_file" 2>&1; then
    if [ "$mode" = "recover" ]; then
      echo "Recovery successful for $node_name. Restarting with recovered WAL..."
      restart_etcd_with_recovered_wal "$i"
    fi
  fi
}

# Function to collect metrics continuously in the background
start_collecting_metrics() {
  echo "Starting metrics collection..."
  while true; do
    TIMESTAMP=$(date +%s)
    for i in $(seq 1 $TOTAL_NODES); do
      client_port=$((2379 + (i - 1) * 10000))
      METRIC_LINE=$(curl -s "http://$LOCAL_IP:$client_port/metrics" | grep '^etcd_server_proposals_committed_total ')
      METRIC_VALUE=$(echo "$METRIC_LINE" | awk '{print $2}')

      # Check if the metric fetch was successful and the value is numeric
      if [[ -z "$METRIC_VALUE" || ! "$METRIC_VALUE" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        METRIC_VALUE=0
      fi

      echo "$TIMESTAMP,infra$i,$METRIC_VALUE" >> $METRICS_LOG
    done
    sleep 2
  done &
  echo $! > "$LOG_DIR/metrics_collector.pid"
  echo "Metrics collection started in the background."
}

# Function to stop metrics collection
stop_collecting_metrics() {
  echo "Stopping metrics collection..."
  if [ -f "$LOG_DIR/metrics_collector.pid" ]; then
    kill "$(cat $LOG_DIR/metrics_collector.pid)"
    rm "$LOG_DIR/metrics_collector.pid"
    echo "Metrics collection stopped."
  else
    echo "Metrics collector PID file not found."
  fi
}

cleanup() {
  killall etcd
  rm -rf $COPY_DIR
  pkill -f metro_recovery ; pkill -f recovery_benchmark
  killall etcd
}

# Main execution
echo "Preparing benchmark environment..."
start_etcd_cluster

# Create the peers file for local test
for i in $(seq 1 $TOTAL_NODES); do
  echo "$LOCAL_IP:$((50050 + i))" >> $PEERS_FILE
done

start_collecting_metrics

# Perform initial PUT benchmark
perform_put_benchmark $X_PUTS "initial_put_benchmark.out"

# Stop nodes
stop_etcd_nodes

# Wait for recovery
echo "Waiting for $Z_WAIT seconds before recovery..."
sleep $Z_WAIT

# Start continuous PUT benchmark in the background
#perform_put_benchmark $X_PUTS "failure_put_benchmark.out"

echo "Starting recovery server on all nodes (both healthy and recovering)..."
declare -a RECOVERY_PIDS
declare -a SERVER_PIDS

for i in $(seq 1 $TOTAL_NODES); do
  if [ "$i" -le "$Y_KILLS" ]; then
    # Start recovery mode for killed nodes and run in the background
    start_recovery_server "recover" $i $PEERS_FILE &
    RECOVERY_PIDS[$i]=$! # Capture the PID for recover mode
  else
    # Start server mode for healthy nodes and run in the background
    start_recovery_server "server" $i $PEERS_FILE &
    SERVER_PIDS[$i]=$! # Capture the PID for server mode
  fi
done

for pid in "${RECOVERY_PIDS[@]}"; do
  if [ -n "$pid" ]; then
    wait $pid
    if [ $? -eq 0 ]; then
      echo "Recovery server process $pid completed successfully."
    else
      echo "Recovery server process $pid failed."
    fi
  fi
done

# Kill all recovery processes
echo "Killing recovery processes..."
for pid in "${RECOVERY_PIDS[@]}"; do
  if [ -n "$pid" ]; then
    kill "$pid" 2>/dev/null
    echo "Killed recovery process $pid."
  fi
done

# Kill all server mode processes
echo "Killing server mode processes..."
for pid in "${SERVER_PIDS[@]}"; do
  if [ -n "$pid" ]; then
    kill "$pid" 2>/dev/null
    echo "Killed server process $pid."
  fi
done

perform_put_benchmark $X_PUTS "recovery_put_benchmark.out"

stop_collecting_metrics

echo "Benchmark completed. Metrics logged in $METRICS_LOG."

trap cleanup EXIT
trap cleanup SIGINT SIGTERM