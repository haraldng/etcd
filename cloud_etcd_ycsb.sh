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
  "100"
  "1000"
  "1600"
  "3200"
)
FIELDCOUNT=10
THREAD_COUNT=1024
OPERATION_COUNT=2000000
INSERT_COUNT=20000
RECORD_COUNT=20000

GO_YCSB_CMD="./../go-ycsb"
YCSB_LOAD_CMD="load etcd -p recordcount=$RECORD_COUNT -p insertcount=$INSERT_COUNT -p threadcount=$THREAD_COUNT"
YCSB_RUN_CMD="run etcd -p recordcount=$RECORD_COUNT -p operationcount=$OPERATION_COUNT -p threadcount=$THREAD_COUNT"
# Define workloads dynamically
WORKLOAD_BASE_CMDS=(
  "-p readproportion=0.0 -p updateproportion=1.0"   # Write
  "-p readproportion=0.5 -p updateproportion=0.5"   # Workload A
  "-p readproportion=0.95 -p updateproportion=0.05" # Workload B
  "-p readproportion=1.0 -p updateproportion=0.0"   # Workload C
  "-p readproportion=0.95 -p insertproportion=0.05" # Workload D
)

WORKLOAD_NAMES=(
  "write"
  "workload-a"
  "workload-b"
  "workload-c"
  "workload-d"
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

# Function to run the benchmark
run_benchmark() {
  local workload_command="$1"
  local output_file="$2"
  local log_file="$3"

  # Run the workload command normally and pipe the output directly to awk
  # Save the result of awk's pattern match directly to the output file
#  eval "$workload_command" 2>&1 | tee >(awk '/Run finished, takes/{flag=1} flag' >> "$output_file") | tee -a "$log_file"
  eval "$workload_command" 2>&1 | tee "$log_file" | awk '/Run finished, takes/{flag=1} flag' >> "$output_file"
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
if [ "$#" -lt 3 ]; then
  echo "Usage: $0 <ip_file> <output_directory> <serializable_reads (true/false)>"
  exit 1
fi

IP_FILE="$1"
OUTPUT_DIR="$2"
SERIALIZABLE_READS="$3"

# Validate if IP file exists
if ! [ -f "$IP_FILE" ]; then
  echo "IP file $IP_FILE not found!"
  exit 1
fi

# Validate serializable_reads flag
if [ "$SERIALIZABLE_READS" != "true" ] && [ "$SERIALIZABLE_READS" != "false" ]; then
  echo "Error: Please provide 'true' or 'false' for the serializable_reads flag."
  exit 1
fi

# Parse etcd endpoints from the provided config file
parse_config "$IP_FILE"

echo "Serializable reads flag set to: $SERIALIZABLE_READS"

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

LOAD_CMD="$GO_YCSB_CMD $YCSB_LOAD_CMD -p etcd.endpoints=$ETCD_ENDPOINTS"

for fieldlength in "${FIELDLENGTHS[@]}"; do
  LOAD_CMD+=" -p fieldlength=$fieldlength -p fieldcount=$FIELDCOUNT"
  for i in ${!ETCD_VERSIONS[@]}; do
    VERSION=${ETCD_VERSIONS[$i]}
    CONFIG_FILE=${BENCH_CONFIG_FILES[$i]}

    # Create version-specific output directory
    VERSION_OUTPUT_DIR="$OUTPUT_DIR/${fieldlength}/$VERSION"
    mkdir -p "$VERSION_OUTPUT_DIR"
    CLUSTER_LOG_FILE="$VERSION_OUTPUT_DIR/cluster.log"

    echo "Benchmarking version: $VERSION using config: $CONFIG_FILE"
    # Iterate through all workloads
    for j in ${!WORKLOAD_BASE_CMDS[@]}; do
      WORKLOAD_NAME=${WORKLOAD_NAMES[$j]}
      WORKLOAD_CMD="$GO_YCSB_CMD $YCSB_RUN_CMD ${WORKLOAD_BASE_CMDS[$j]} -p etcd.serializable_reads=$SERIALIZABLE_READS -p etcd.endpoints=$ETCD_ENDPOINTS -p fieldlength=$fieldlength -p fieldcount=$FIELDCOUNT"

      # Run workload multiple times
      for k in $(seq 1 $NUM_ITERATIONS); do
        if [ "$k" -gt 1 ]; then
          SKIP_BUILD="true"
        else
          SKIP_BUILD="false"
        fi

        # Restart cluster for clean test environment
        restart_cluster "$CONFIG_FILE" "$IP_FILE" "$CLUSTER_LOG_FILE" "$SKIP_BUILD"
        echo "Cluster restarted. Sleeping for $SLEEP_CLUSTER_START seconds..."
        sleep $SLEEP_CLUSTER_START
        # Load data before running the workload
        echo "Loading initial data into etcd: $LOAD_CMD"
        $LOAD_CMD | tee -a "$VERSION_OUTPUT_DIR/load.log"
        echo "Load completed. Sleeping for 10 seconds..."
        sleep 10

        echo "Running workload: $WORKLOAD_NAME (Iteration $k)..."
        OUTPUT_FILE="$VERSION_OUTPUT_DIR/$WORKLOAD_NAME.txt"
        RUN_LOG_FILE="$VERSION_OUTPUT_DIR/$WORKLOAD_NAME-${k}.log"
        run_benchmark "$WORKLOAD_CMD" "$OUTPUT_FILE" "$RUN_LOG_FILE"
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