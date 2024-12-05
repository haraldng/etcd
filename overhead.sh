#!/bin/bash

# Parameters passed to the script
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --node-name) NODE_NAME="$2"; shift ;;
        --ip) IP="$2"; shift ;;
        --port) PORT="$2"; shift ;;
        --data-dir) DATA_DIR="$2"; shift ;;
        --peers-file) PEERS_FILE="$2"; shift ;;
        --etcd-binary) ETCD_BINARY="$2"; shift ;;
        --server-binary) SERVER_BINARY="$2"; shift ;;
        --cluster-token) CLUSTER_TOKEN="$2"; shift ;;
        --initial-cluster) INITIAL_CLUSTER="$2"; shift ;;
        --output-dir) OUTPUT_DIR="$2"; shift ;;
        --results-file) RESULTS_FILE="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

LOG_FILE="$OUTPUT_DIR/recover_${NODE_NAME}.log"
RECOVERY_SUCCESS_MARKER="Recovery process completed"
ETCD_LOG="$OUTPUT_DIR/restarted_${NODE_NAME}.log"

start_etcd() {
  nohup $ETCD_BINARY --name $NODE_NAME \
      --listen-client-urls http://$IP:2379 \
      --advertise-client-urls http://$IP:2379 \
      --listen-peer-urls http://$IP:2380 \
      --initial-advertise-peer-urls http://$IP:2380 \
      --initial-cluster-token $CLUSTER_TOKEN \
      --initial-cluster "$INITIAL_CLUSTER" \
      --logger=zap \
      --data-dir=$DATA_DIR > "$ETCD_LOG" 2>&1 &
}

echo "Recovery args: $NODE_NAME, $PORT, $DATA_DIR, $PEERS_FILE, $ETCD_BINARY, $SERVER_BINARY, $CLUSTER_TOKEN, $INITIAL_CLUSTER, $OUTPUT_DIR"

START_TIME=$(date +%s%3N | sed 's/[^0-9]//g') # Record the start time in milliseconds
$SERVER_BINARY --mode=recover --ip=$IP --port=$PORT --data-dir=$DATA_DIR --peers-file=$PEERS_FILE > "$LOG_FILE"
END_TIME=$(date +%s%3N | sed 's/[^0-9]//g') # Record the end time in milliseconds
echo "Start time: $START_TIME, End time: $END_TIME"
echo  $((END_TIME - START_TIME)) > $RESULTS_FILE
  # Start the recovery server
#  if $
#    END_TIME=$(date +%s%3N | sed 's/[^0-9]//g') # Record the end time in milliseconds
#    echo "Start time: $START_TIME, End time: $END_TIME"
#    echo  $((END_TIME - START_TIME)) > "$DATA_DIR/recovery_time_${NODE_NAME}.out"
#    echo "Recovery process took $((END_TIME - START_TIME)) milliseconds"
#    echo "Recovery successful for $NODE_NAME. Restarting etcd node..."
#    start_etcd
#    echo "Etcd node $NODE_NAME restarted successfully."
#  else
#      echo "Recovery failed for $NODE_NAME. Check logs for details: $LOG_FILE"
#  fi
