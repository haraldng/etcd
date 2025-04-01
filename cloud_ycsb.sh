#!/bin/bash

# ================================
# Constants
# ================================

# Sleep times in seconds
SLEEP_CLUSTER_START=2       # Time to wait (in seconds) for the cluster to start
SLEEP_CLUSTER_SHUTDOWN=0.1  # Time to wait (in seconds) between shutdown signals
SLEEP_CLUSTER_STOP=0.1      # Time to wait (in seconds) after sending shutdown signal

# Number of iterations for each workload
NUM_ITERATIONS=3

# Etcd endpoints
ETCD_ENDPOINTS="10.128.15.210:2379,10.128.15.211:2379,10.128.15.212:2379"

# ================================
# Commands
# ================================

# Define the path to the start and stop cluster script
START_CLUSTER_CMD="./start_cloud_nodes.sh"

# ================================
# Go-YCSB Command Definitions
# ================================

# Define Go-YCSB commands for different workloads
WRITE_CMD="./go-ycsb run etcd -p etcd.endpoints=\"$ETCD_ENDPOINTS\" -p recordcount=20000 -p operationcount=500000 -p fieldcount=10 -p fieldlength=1024 -p threadcount=16 -p target=15000"

WORKLOAD_A_CMD="./go-ycsb run etcd -p etcd.endpoints=\"$ETCD_ENDPOINTS\" -p recordcount=20000 -p operationcount=500000 -p fieldcount=10 -p fieldlength=1024 -p readproportion=0.5 -p updateproportion=0.5 -p threadcount=16 -p target=15000"

WORKLOAD_B_CMD="./go-ycsb run etcd -p etcd.endpoints=\"$ETCD_ENDPOINTS\" -p recordcount=20000 -p operationcount=500000 -p fieldcount=10 -p fieldlength=1024 -p readproportion=0.95 -p updateproportion=0.05 -p threadcount=16 -p target=15000"

WORKLOAD_C_CMD="./go-ycsb run etcd -p etcd.endpoints=\"$ETCD_ENDPOINTS\" -p recordcount=20000 -p operationcount=500000 -p fieldcount=10 -p fieldlength=1024 -p readproportion=1.0 -p updateproportion=0.0 -p threadcount=16 -p target=15000"

WORKLOAD_D_CMD="./go-ycsb run etcd -p etcd.endpoints=\"$ETCD_ENDPOINTS\" -p recordcount=20000 -p operationcount=500000 -p fieldcount=10 -p fieldlength=1024 -p readproportion=0.95 -p insertproportion=0.05 -p threadcount=16 -p target=15000"

# ================================
# Etcd Versions and Configs
# ================================

# List of etcd versions with their respective bench_config.json files
ETCD_VERSIONS=("metronome" "etcd")
BENCH_CONFIG_FILES=("metronome_bench_config.json" "etcd_bench_config.json")

# ================================
# Functions
# ================================

# Function to run the benchmark for a specific workload and capture the output from "Run finished, takes"
run_benchmark() {
  local workload_command="$1"
  local output_file="$2"

  # Run the YCSB command and capture output starting from "Run finished, takes"
  $workload_command | awk '/Run finished, takes/{flag=1} flag' >> "$output_file"
}

# Function to restart the cluster
restart_cluster() {
  echo "Shutting down the cluster..."
  # Send enter key twice to stop the cluster
  kill -SIGINT $CLUSTER_PID
  sleep $SLEEP_CLUSTER_SHUTDOWN
  kill -SIGINT $CLUSTER_PID

  # Optional: Wait for cluster to fully shut down
  wait $CLUSTER_PID

  echo "Starting the cluster..."
  $START_CLUSTER_CMD $1 $2 &
  CLUSTER_PID=$!

  # Wait for a few seconds to ensure the cluster is up and running
  sleep $SLEEP_CLUSTER_START
}

# ================================
# Main Script Logic
# ================================

# Check if an output directory argument was provided
if [ -z "$1" ]; then
  echo "Usage: $0 <output_directory> <serializable_reads (true/false)>"
  exit 1
fi

# Assign the input argument to the OUTPUT_DIR variable
OUTPUT_DIR="$1"

# Check if the serializable_reads flag is provided and if it is "true" or "false"
SERIALIZABLE_READS=$2

if [ "$SERIALIZABLE_READS" != "true" ] && [ "$SERIALIZABLE_READS" != "false" ]; then
  echo "Error: Please provide 'true' or 'false' for the serializable_reads flag."
  exit 1
fi

echo "Serializable reads flag set to: $SERIALIZABLE_READS"

# Create the output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# List of all workloads
WORKLOADS=(
  "$WRITE_CMD"
  "$WORKLOAD_A_CMD"
  "$WORKLOAD_B_CMD"
  "$WORKLOAD_C_CMD"
  "$WORKLOAD_D_CMD"
)

# Loop through each etcd version and benchmark
for i in ${!ETCD_VERSIONS[@]}; do
  VERSION=${ETCD_VERSIONS[$i]}
  CONFIG_FILE=${BENCH_CONFIG_FILES[$i]}

  # Create an output directory for the current version
  VERSION_OUTPUT_DIR="$OUTPUT_DIR/$VERSION"
  mkdir -p "$VERSION_OUTPUT_DIR"  # Create the version-specific folder

  echo "Benchmarking version: $VERSION using config: $CONFIG_FILE"

  # Start the cluster in the background
  echo "Starting the cluster for $VERSION..."
  $START_CLUSTER_CMD $CONFIG_FILE example_cloud_bench_config.txt &
  CLUSTER_PID=$!

  # Wait for a few seconds to ensure the cluster is up and running
  sleep $SLEEP_CLUSTER_START

  # Outer loop: Iterate through all the workloads
  for WORKLOAD_CMD in "${WORKLOADS[@]}"; do
    # Inner loop: Run each workload NUM_ITERATIONS times
    for i in $(seq 1 $NUM_ITERATIONS); do
      echo "Running workload: $WORKLOAD_CMD (Iteration $i)..."
      # Define the output file based on the workload
      WORKLOAD_NAME=$(echo $WORKLOAD_CMD | awk '{print $6}')
      OUTPUT_FILE="$VERSION_OUTPUT_DIR/$WORKLOAD_NAME.txt"
      run_benchmark "$WORKLOAD_CMD" "$OUTPUT_FILE"
    done

    # After completing all iterations for the current workload, restart the cluster
    echo "Completed all iterations for workload $WORKLOAD_CMD. Restarting the cluster..."
    restart_cluster $CONFIG_FILE example_cloud_bench_config.txt  # Restart the cluster after the current workload

  done

  # After completing all workloads for the current version, shutdown the cluster
  echo "Benchmarking completed for $VERSION."
  echo "Shutting down the cluster for $VERSION..."
  kill -SIGINT $CLUSTER_PID
  sleep $SLEEP_CLUSTER_STOP
  kill -SIGINT $CLUSTER_PID
  wait $CLUSTER_PID
done

echo "All benchmarking completed for all versions."