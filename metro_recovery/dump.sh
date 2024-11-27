#!/bin/bash

# Define the main data directory containing subdirectories for each node
AFFECTED_DATA_DIR="main-wal1000"
OUTPUT_DIR="wal_dumps"
DIFF_OUTPUT="wal_differences"

# Create output directories for WAL dumps and diffs
mkdir -p "$OUTPUT_DIR"
mkdir -p "$DIFF_OUTPUT"

# Iterate over each subdirectory in the affected data directory
for NODE_DIR in "$AFFECTED_DATA_DIR"/*; do
    # Check if the item is a directory
    if [ -d "$NODE_DIR" ]; then
        # Extract the node name from the directory path
        NODE_NAME=$(basename "$NODE_DIR")

        # Define the WAL directory for the node
        WAL_DIR="$NODE_DIR/member/wal"
        OUTPUT_FILE="$OUTPUT_DIR/${NODE_NAME}_wal_dump.txt"

        # Check if the WAL directory exists
        if [ -d "$WAL_DIR" ]; then
            echo "Dumping WAL entries for node $NODE_NAME located in $WAL_DIR..."

            # Run etcd-dump-logs with NODE_DIR as the path
            go run ../tools/etcd-dump-logs "$NODE_DIR" > "$OUTPUT_FILE"

            if [ $? -eq 0 ]; then
                echo "WAL entries for $NODE_NAME dumped to $OUTPUT_FILE"
            else
                echo "Failed to dump WAL entries for $NODE_NAME"
            fi
        else
            echo "WAL directory $WAL_DIR not found for node $NODE_NAME"
        fi
    fi
done

# Compare WAL dumps between nodes
echo "Comparing WAL dumps between nodes..."
for FILE1 in "$OUTPUT_DIR"/*.txt; do
    for FILE2 in "$OUTPUT_DIR"/*.txt; do
        if [ "$FILE1" != "$FILE2" ]; then
            NODE1=$(basename "$FILE1" .txt)
            NODE2=$(basename "$FILE2" .txt)
            DIFF_FILE="$DIFF_OUTPUT/${NODE1}_vs_${NODE2}_diff.txt"

            # Compare the two WAL dumps
            echo "Comparing $NODE1 and $NODE2..."
            diff "$FILE1" "$FILE2" > "$DIFF_FILE"

            if [ $? -eq 0 ]; then
                echo "No differences between $NODE1 and $NODE2"
                rm "$DIFF_FILE"  # Clean up empty diff files
            else
                echo "Differences found between $NODE1 and $NODE2, see $DIFF_FILE"
            fi
        fi
    done
done

echo "WAL dump and comparison completed."
