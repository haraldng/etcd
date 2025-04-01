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

GO_YCSB_CMD="./../go-ycsb"
START_CLUSTER_CMD="./start_cloud_nodes.sh"
STOP_CLUSTER_CMD="./stop_cloud_nodes.sh"

# ================================
# Etcd Versions and Configs
# ================================

ETCD_VERSIONS=("etcd" "metronome")
BENCH_CONFIG_FILES=("etcd_bench_config.json" "metronome_bench_config.json")

YCSB_RUN_CMD="run etcd -p etcd.endpoints=$ETCD_ENDPOINTS -p recordcount=20000 -p operationcount=500000 -p fieldcount=10 -p fieldlength=1024 -p threadcount=16 -p target=15000"

# Define workloads dynamically
WORKLOAD_BASE_CMDS=(
  "-p readproportion=1.0 -p updateproportion=0.0"   # Workload C
  "-p readproportion=0.0 -p updateproportion=1.0"
  "-p readproportion=0.5 -p updateproportion=0.5"   # Workload A
  "-p readproportion=0.95 -p updateproportion=0.05" # Workload B
  "-p readproportion=0.95 -p insertproportion=0.05" # Workload D
)

WORKLOAD_NAMES=("workload-c" "write" "workload-a" "workload-b" "workload-d")

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

  # Run the workload command normally and pipe the output directly to awk
  # Save the result of awk's pattern match directly to the output file
  $workload_command 2>&1 | awk '/Run finished, takes/{flag=1} flag' > "$output_file"
}

# Function to restart the cluster
restart_cluster() {
  local config_file="$1"
  local ip_file="$2"
  local log_file="$3"

  echo "Shutting down the cluster..."
  kill -SIGINT $CLUSTER_PID
  sleep $SLEEP_CLUSTER_SHUTDOWN
  kill -SIGINT $CLUSTER_PID

  echo "Starting the cluster..."
  $START_CLUSTER_CMD "$config_file" "$ip_file" "true" | tee "$log_file" &
  CLUSTER_PID=$!
  echo "Cluster PID: $CLUSTER_PID"

  sleep $SLEEP_CLUSTER_START
}

# Function to load initial data into etcd
load_data() {
  local log_file="$1"

  echo "Loading initial data into etcd..."
  $GO_YCSB_CMD load etcd -p etcd.endpoints="$ETCD_ENDPOINTS" \
    -p recordcount=20000 \
    -p insertcount=20000 \
    -p fieldcount=10 \
    -p fieldlength=1024 | tee -a "$log_file"
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

# Loop through each etcd version
for i in ${!ETCD_VERSIONS[@]}; do
  VERSION=${ETCD_VERSIONS[$i]}
  CONFIG_FILE=${BENCH_CONFIG_FILES[$i]}

  # Create version-specific output directory
  VERSION_OUTPUT_DIR="$OUTPUT_DIR/$VERSION"
  mkdir -p "$VERSION_OUTPUT_DIR"
  CLUSTER_LOG_FILE="$VERSION_OUTPUT_DIR/cluster.log"

  echo "Benchmarking version: $VERSION using config: $CONFIG_FILE"

  # Iterate through all workloads
  for j in ${!WORKLOAD_BASE_CMDS[@]}; do
    WORKLOAD_NAME=${WORKLOAD_NAMES[$j]}
    WORKLOAD_CMD="$GO_YCSB_CMD $YCSB_RUN_CMD ${WORKLOAD_BASE_CMDS[$j]} -p etcd.serializable_reads=$SERIALIZABLE_READS"

    # Restart cluster for clean test environment
    restart_cluster "$CONFIG_FILE" "$IP_FILE" "$CLUSTER_LOG_FILE"

    # Load data before running the workload
    load_data "$VERSION_OUTPUT_DIR/load.log"

    # Run workload multiple times
    for k in $(seq 1 $NUM_ITERATIONS); do
      echo "Running workload: $WORKLOAD_NAME (Iteration $k)..."
      OUTPUT_FILE="$VERSION_OUTPUT_DIR/$WORKLOAD_NAME.txt"
      run_benchmark "$WORKLOAD_CMD" "$OUTPUT_FILE"
    done

    echo "Completed all iterations for workload: $WORKLOAD_NAME."
  done

  # Shutdown cluster after all workloads are completed
  echo "Benchmarking completed for $VERSION. Shutting down cluster..."
  STOP_CLUSTER_CMD "$IP_FILE"
done

echo "All benchmarking completed for all versions."