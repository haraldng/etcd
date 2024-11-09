#!/bin/bash

# Check if the user passed the number of nodes as an argument
if [ -z "$1" ]; then
  echo "Usage: $0 <number_of_nodes>"
  exit 1
fi

# Number of etcd nodes to create
N=$1
PROCFILE="Procfile"

# Initialize the cluster members list
cluster_members=""

# Create a fresh Procfile
echo "# Auto-generated Procfile for $N-node etcd cluster" > $PROCFILE

# Loop through to generate configuration for each node
for i in $(seq 1 $N); do
  # Calculate ports for client and peer connections based on index
  client_port=$((2379 + (i - 1) * 10000))
  peer_port=$((2380 + (i - 1) * 10000))

  # Set the infra name and data directory
  infra_name="infra${i}"
  data_dir="local_test/$infra_name"

  # Append this node to the cluster members list
  cluster_members+="${infra_name}=http://127.0.0.1:${peer_port},"

  # Append the node entry to the Procfile
  echo "${infra_name}: bin/etcd --name ${infra_name} --listen-client-urls http://127.0.0.1:${client_port} --advertise-client-urls http://127.0.0.1:${client_port} --listen-peer-urls http://127.0.0.1:${peer_port} --initial-advertise-peer-urls http://127.0.0.1:${peer_port} --initial-cluster-token etcd-cluster-1 --initial-cluster 'PLACEHOLDER_CLUSTER_MEMBERS' --initial-cluster-state new --logger=zap --log-outputs=stderr --data-dir ${data_dir} --log-level error --quota-backend-bytes=10737418240" >> $PROCFILE
done

# Remove the trailing comma from cluster members list
cluster_members="${cluster_members%,}"

# Read the Procfile into a variable, replace the placeholder, and write it back
procfile_content=$(<"$PROCFILE")
procfile_content="${procfile_content//PLACEHOLDER_CLUSTER_MEMBERS/$cluster_members}"
echo "$procfile_content" > "$PROCFILE"

echo "Generated Procfile with $N etcd nodes."
