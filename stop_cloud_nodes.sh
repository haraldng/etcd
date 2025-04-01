#!/bin/bash

# Check if the configuration file is passed as an argument
if [ $# -lt 1 ]; then
  echo "Usage: $0  <ip_file>"
  exit 1
fi

ip_file=$1

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

for ip in "${IP_ADDRESSES[@]}"; do
    ssh "$USERNAME@$ip" "killall etcd" || { echo "ERROR: Failed to stop etcd on VM $ip"; }
    sleep 1
    ssh "$USERNAME@$ip" "sudo rm -rf $ITERATION_DATA_DIR || { echo 'WARNING: Failed to remove some files in $ITERATION_DATA_DIR on VM $ip'; }"
done
