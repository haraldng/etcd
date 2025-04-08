#!/bin/bash

# ================================
# Constants
# ================================

# Sleep times in seconds
SLEEP_CLUSTER_START=2
SLEEP_CLUSTER_SHUTDOWN=0.1
SLEEP_CLUSTER_STOP=0.1

# Number of iterations for each workload
NUM_ITERATIONS=3

# Default etcd endpoints (Overwritten by config file)
ETCD_ENDPOINTS=""

# ================================
# Commands
# ================================

START_CLUSTER_CMD="./start_cloud_nodes.sh"
STOP_CLUSTER_CMD="./stop_cloud_nodes.sh"

# ================================
# Etcd Versions and Configs
# ================================

ETCD_VERSIONS=(
  "etcd"
  "metronome"
)
BENCH_CONFIG_FILES=(
  "etcd_bench_config.json"
  "metronome_bench_config.json"
)
FIELDLENGTHS=(
  "128"
  #"1600"
  "32768"
)
FIELDCOUNT=10
THREAD_COUNT=1024
OPERATION_COUNT=500000

BENCH_CMD="go run ./tools/benchmark mixed --clients $THREAD_COUNT  --sequential-keys --conns=100 --total $OPERATION_COUNT  --key-space-size $OPERATION_COUNT"
# Define workloads dynamically
WORKLOAD_BASE_CMDS=(
  "--read-percent 50"   # Workload A
  "--read-percent 95"   # Workload B
  "--read-percent 100"   # Workload C
)

WORKLOAD_NAMES=(
  "workload-a"
  "workload-b"
  "workload-c"
 )

# ================================
# Functions
# ================================

# Parse etcd endpoints from config file
parse_config() {
  local config_file="$1"

  if [ ! -f "$config_file" ]; then
    echo "ERROR: Config file '$config_file' not found!"
    exit 1
  fi

  # Read the file, skip the first line, append :2379 to each IP, and join with commas
  ETCD_ENDPOINTS=$(tail -n +2 "$config_file" | awk '{print $1":2379"}' | paste -sd "," -)

  if [ -z "$ETCD_ENDPOINTS" ]; then
    echo "ERROR: No valid etcd endpoints found in '$config_file'!"
    exit 1
  fi

  echo "Parsed etcd endpoints: $ETCD_ENDPOINTS"
}


# Function to restart the cluster
restart_cluster() {
  local config_file="$1"
  local ip_file="$2"
  local log_file="$3"
  local skip_build="$4"

  $STOP_CLUSTER_CMD $ip_file
  echo "Starting the cluster..."
  $START_CLUSTER_CMD "$config_file" "$ip_file" "$skip_build" > "$log_file"

  sleep $SLEEP_CLUSTER_START
}

# ================================
# Main Script Logic
# ================================

# Check if enough arguments are provided
if [ "$#" -lt 2 ]; then
  echo "Usage: $0 <ip_file> <output_directory>"
  exit 1
fi

IP_FILE="$1"
OUTPUT_DIR="$2"

# Validate if IP file exists
if ! [ -f "$IP_FILE" ]; then
  echo "IP file $IP_FILE not found!"
  exit 1
fi

# Parse etcd endpoints from the provided config file
parse_config "$IP_FILE"

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

for fieldlength in "${FIELDLENGTHS[@]}"; do
  for i in ${!ETCD_VERSIONS[@]}; do
    VERSION=${ETCD_VERSIONS[$i]}
    CONFIG_FILE=${BENCH_CONFIG_FILES[$i]}


    echo "Benchmarking version: $VERSION using config: $CONFIG_FILE"
    # Iterate through all workloads
    for j in ${!WORKLOAD_BASE_CMDS[@]}; do
      # Create version-specific output directory
      WORKLOAD_NAME=${WORKLOAD_NAMES[$j]}
      # Run workload multiple times
      for k in $(seq 1 $NUM_ITERATIONS); do
        if [ "$k" -gt 1 ]; then
          SKIP_BUILD="true"
        else
          SKIP_BUILD="false"
        fi

        VERSION_OUTPUT_DIR="$OUTPUT_DIR/${fieldlength}/$VERSION/$WORKLOAD_NAME/$k"
        mkdir -p "$VERSION_OUTPUT_DIR"
        CLUSTER_LOG_FILE="$VERSION_OUTPUT_DIR/cluster.log"
        WORKLOAD_CMD="$BENCH_CMD --endpoints=$ETCD_ENDPOINTS --val-size=$fieldlength --output-dir $VERSION_OUTPUT_DIR"

        # Restart cluster for clean test environment
        restart_cluster "$CONFIG_FILE" "$IP_FILE" "$CLUSTER_LOG_FILE" "$SKIP_BUILD"
        echo "Cluster restarted. Sleeping for $SLEEP_CLUSTER_START seconds..."
        sleep $SLEEP_CLUSTER_START

        echo "Running workload: $WORKLOAD_NAME (Iteration $k)..."
        # Run the workload command
        $WORKLOAD_CMD
        echo "Workload $WORKLOAD_NAME completed. Sleeping for 5 seconds before next iteration..."
        sleep 5
      done

      echo "Completed all iterations for workload: $WORKLOAD_NAME."
    done

    # Shutdown cluster after all workloads are completed
    echo "Benchmarking completed for $VERSION. Shutting down cluster..."
    $STOP_CLUSTER_CMD "$IP_FILE"
  done

done

# Loop through each etcd version

echo "All benchmarking completed for all versions."