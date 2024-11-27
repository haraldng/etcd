#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# Variables
CLUSTER_SIZE=3
NODE_TO_RECOVER="etcd2"
DATA_DIR="./local_test"
MERGED_WAL_DIR="./merged_wal"
WAL_MERGE_PROGRAM="./metro_recovery/mergewal/mergewal"     # Path to your WAL merging program
WAL_FILTER_PROGRAM="./metro_recovery/filterwal/filterwal"  # Path to your WAL filtering program
FILTER_FACTOR=2                                            # Used to filter every Nth entry
LOG_DIR="./local_test"

# Specify the etcd and etcdctl commands (update these if necessary)
ETCD_CMD="./bin/etcd"
ETCDCTL_CMD="./bin/etcdctl"

# Clean up any existing data
rm -rf ${DATA_DIR} ${LOG_DIR} ${MERGED_WAL_DIR}
mkdir -p ${DATA_DIR} ${LOG_DIR}

# Declare an associative array to store etcd process PIDs
declare -a ETCD_PIDS

# Function to generate the initial cluster string
generate_initial_cluster() {
  local initial_cluster=""
  for i in $(seq 1 ${CLUSTER_SIZE}); do
    name="etcd${i}"
    peer_port=$(( (i - 1) * 10000 + 2380 )) # Dynamic peer port: 2380, 12380, 22380, ...
    if [ $i -gt 1 ]; then
      initial_cluster="${initial_cluster},"
    fi
    initial_cluster="${initial_cluster}${name}=http://localhost:${peer_port}"
  done
  echo "${initial_cluster}"
}

# Function to start etcd nodes
start_etcd_cluster() {
  echo "Starting etcd cluster with ${CLUSTER_SIZE} nodes..."

  initial_cluster=$(generate_initial_cluster)

  for i in $(seq 1 ${CLUSTER_SIZE}); do
    name="etcd${i}"
    client_port=$(( (i - 1) * 10000 + 2379 )) # Dynamic client port: 2379, 12379, 22379, ...
    peer_port=$(( (i - 1) * 10000 + 2380 ))   # Dynamic peer port: 2380, 12380, 22380, ...
    data_dir="${DATA_DIR}/${name}"
    log_file="${LOG_DIR}/${name}.log"

    mkdir -p ${data_dir}

    ${ETCD_CMD} --name ${name} \
      --data-dir ${data_dir} \
      --initial-advertise-peer-urls http://localhost:${peer_port} \
      --listen-peer-urls http://localhost:${peer_port} \
      --advertise-client-urls http://localhost:${client_port} \
      --listen-client-urls http://localhost:${client_port} \
      --initial-cluster-token etcd-cluster-1 \
      --initial-cluster "${initial_cluster}" \
      --initial-cluster-state new \
      --logger=zap \
      --log-level error \
      --log-outputs=${log_file} &

    # Capture the PID
    ETCD_PIDS[${name}]=$!

    echo "Started ${name} in the background, logging to ${log_file}."
  done

  # Give the cluster some time to start
  sleep 3
  echo "Etcd cluster started."
}

# Function to perform 100 put operations
populate_cluster() {
  echo "Populating etcd cluster with 100 key-value pairs..."

  for i in $(seq 1 100); do
    ${ETCDCTL_CMD} --endpoints=http://localhost:2379 put "key${i}" "value${i}"
  done

  echo "Cluster population complete."
}

# Function to stop a node
stop_etcd_node() {
  local node_name=$1
  pid=${ETCD_PIDS[${node_name}]}
  echo "Stopping node ${node_name} with PID: ${pid}..."
  if [ -n "${pid}" ]; then
    kill ${pid}
    wait ${pid} 2>/dev/null || true
    unset ETCD_PIDS[${node_name}]
    echo "Node ${node_name} stopped."
  else
    echo "PID for node ${node_name} not found."
  fi
}

# Function to filter the WAL of a node
filter_node_wal() {
  local node_name=$1
  echo "Filtering WAL of node ${node_name}..."

  local wal_dir="${DATA_DIR}/${node_name}/member/wal"
  local temp_wal_dir="${DATA_DIR}/${node_name}/member/wal_copy"
  local filtered_wal_dir="${DATA_DIR}/${node_name}/member/filtered_wal"

  # Copy the WAL directory to avoid locking issues
  cp -r "${wal_dir}" "${temp_wal_dir}"

  # Use the filtering program on the copied WAL
  ${WAL_FILTER_PROGRAM} --input "${temp_wal_dir}" --output "${filtered_wal_dir}" --interval "${FILTER_FACTOR}"

  # Replace the original WAL with the filtered one
  mv "${wal_dir}" "${wal_dir}_backup"
  mv "${filtered_wal_dir}" "${wal_dir}"

  # Clean up the temporary copy
  rm -rf "${temp_wal_dir}"

  echo "WAL of node ${node_name} filtered."
}

# Function to merge WALs
merge_wals() {
  local recovering_node=$1
  local provider_node=$2
  echo "Merging WAL of node ${recovering_node} with node ${provider_node}..."

  local recovering_wal="${DATA_DIR}/${recovering_node}/member/wal"
  local provider_wal="${DATA_DIR}/${provider_node}/member/wal"

  local temp_recovering_wal="${DATA_DIR}/${recovering_node}/member/wal_copy"
  local temp_provider_wal="${DATA_DIR}/${provider_node}/member/wal_copy"

  # Copy the WAL directories to avoid locking issues
  cp -r "${recovering_wal}" "${temp_recovering_wal}"

  # If provider node is still running, we need to copy its WAL safely
  echo "Copying provider node's WAL..."
  cp -r "${provider_wal}" "${temp_provider_wal}"

  # Use the WAL merging program on the copied WALs
  ${WAL_MERGE_PROGRAM} "${temp_provider_wal}" "${temp_recovering_wal}"

  # Replace the recovering node's WAL with the merged WAL
  mv "${recovering_wal}" "${recovering_wal}_before_merge"
  cp -r "${MERGED_WAL_DIR}" "${recovering_wal}"

  # Clean up temporary copies
  rm -rf "${temp_recovering_wal}" "${temp_provider_wal}"

  echo "WALs merged and updated for node ${recovering_node}."
}

# Function to restart a node
restart_etcd_node() {
  local node_name=$1
  echo "Restarting node ${node_name}..."

  # Get existing node configuration
  node_index=${node_name:4}
  client_port=$(( (node_index - 1) * 10000 + 2379 ))
  peer_port=$(( (node_index - 1) * 10000 + 2380 ))
  data_dir="${DATA_DIR}/${node_name}"
  log_file="${LOG_DIR}/${node_name}.log"

  initial_cluster=$(generate_initial_cluster)

  ${ETCD_CMD} --name ${node_name} \
    --data-dir ${data_dir} \
    --initial-advertise-peer-urls http://localhost:${peer_port} \
    --listen-peer-urls http://localhost:${peer_port} \
    --advertise-client-urls http://localhost:${client_port} \
    --listen-client-urls http://localhost:${client_port} \
    --initial-cluster-token etcd-cluster-1 \
    --initial-cluster "${initial_cluster}" \
    --initial-cluster-state existing \
    --logger=zap \
    --log-outputs=${log_file} &

  # Capture the PID
  ETCD_PIDS[${node_name}]=$!
  echo "Node ${node_name} restarted, logging to ${log_file}."
}

# Main script execution

# Start the etcd cluster
start_etcd_cluster

# Perform 100 puts
populate_cluster

# Stop the node to recover
stop_etcd_node ${NODE_TO_RECOVER}

sleep 5  # Give the node time to fully stop

# Filter its WAL
filter_node_wal ${NODE_TO_RECOVER}

# Merge the filtered WAL with another node's WAL
merge_wals ${NODE_TO_RECOVER} "etcd1" # Assuming etcd1 is another node

# Restart the node with the merged WAL
restart_etcd_node ${NODE_TO_RECOVER}

echo "Recovery process complete."
