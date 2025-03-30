#!/bin/bash

# Check if the configuration file is passed as an argument
if [ $# -lt 1 ]; then
  echo "Usage: $0 <config_file> <ip_file>"
  exit 1
fi

config_file=$1
ip_file=$2

# Validate if the configuration file exists
if ! [ -f "$config_file" ]; then
  echo "Configuration file $config_file not found!"
  exit 1
fi

# Validate if IP file exists
if ! [ -f "$ip_file" ]; then
  echo "IP file $ip_file not found!"
  exit 1
fi

USERNAME=$(head -n 1 "$ip_file")
IP_ADDRESSES=()
while IFS= read -r line; do
    IP_ADDRESSES+=("$line")
done < <(tail -n +2 "$ip_file")

use_snapshot=($(jq -r '.use_snapshot[]' "$config_file"))
base_data_dir=$(jq -r '.data_dir' "$config_file")
quota_backend_bytes=$(jq -r '.quota_backend_bytes' "$config_file")

# Validate base_data_dir
if [ -z "$base_data_dir" ] || [ "$base_data_dir" == "null" ]; then
  echo "ERROR: 'data_dir' must be specified in the configuration file."
  exit 1
fi

quota_limit=$((quota_backend_bytes * 90 / 100))

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

start_nodes() {
    ITERATION_DATA_DIR="$base_data_dir/1"
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
}

stop_nodes() {
    for ip in "${IP_ADDRESSES[@]}"; do
        ssh "$USERNAME@$ip" "killall etcd" || { echo "ERROR: Failed to stop etcd on VM $ip"; }
    done

    echo "Sleeping for $sleep_time seconds to allow the cluster to stabilize..."
    sleep "$sleep_time"
    ssh "$USERNAME@$ip" "sudo rm -rf $ITERATION_DATA_DIR || { echo 'WARNING: Failed to remove some files in $ITERATION_DATA_DIR on VM $ip'; }"
}

# Prepare data directory on VMs
for ip in "${IP_ADDRESSES[@]}"; do
    echo "Setting up base data directory on VM $ip"
    ssh "$USERNAME@$ip" "sudo mkdir -p $base_data_dir && sudo chown -R $(whoami) $base_data_dir && chmod -R u+rwx $base_data_dir" || { echo "ERROR: Failed to set up data directory on VM $ip"; exit 1; }
done

for branch in "${branches[@]}"; do
    echo "Checking out branch $branch and rebuilding on each VM..."
    for ip in "${IP_ADDRESSES[@]}"; do
        ssh "$USERNAME@$ip" "cd etcd && git checkout $branch && git pull && make build" || { echo "ERROR: Failed to build etcd on VM $ip"; exit 1; }
    done

    for node_count in "${nodes[@]}"; do
        for branch in "${branches[@]}"; do
            echo "Checking out branch $branch and rebuilding on each VM..."
            for ip in "${IP_ADDRESSES[@]}"; do
                ssh "$USERNAME@$ip" "cd etcd && git checkout $branch && git pull && make build" || { echo "ERROR: Failed to build etcd on VM $ip"; exit 1; }
            done
            echo "Stopping etcd processes and cleaning data directory on all VMs..."
            for ip in "${IP_ADDRESSES[@]}"; do
                ssh "$USERNAME@$ip" "killall etcd || true" || { echo "ERROR: Failed to stop etcd on VM $ip"; exit 1; }
                ssh "$USERNAME@$ip" "sudo rm -rf $base_data_dir/* || { echo 'WARNING: Failed to remove some files in $base_data_dir on VM $ip'; }"
            done

            echo "Starting etcd on all VMs..."
            start_nodes

            echo "Press Enter to stop VMs..."
            read

            echo "Are you sure? Press Enter again to confirm..."
            read

            # Stop etcd on each instance after the benchmark run
            echo "Stopping etcd on all VMs..."
            stop_nodes

        done
    done
done




