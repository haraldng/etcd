#!/bin/bash

# Variables (update as needed)
DEVICE_NAME="/dev/sdb"           # Replace with the disk's device name (e.g., /dev/sdb)
MOUNT_POINT="/mnt/etcd_data"        # Replace with your desired mount point
FILESYSTEM_TYPE="ext4"           # Replace with the desired filesystem type (e.g., ext4, xfs)
LABEL="etcd_data"                   # Optional: label for the disk (used in mounting)

# Step 1: Verify the device exists
if [ ! -b "$DEVICE_NAME" ]; then
    echo "Error: Device $DEVICE_NAME not found."
    exit 1
fi
echo "Device $DEVICE_NAME found."

# Step 2: Create the filesystem (optional, if not already formatted)
read -p "Do you want to format the disk (This will erase all data)? [y/N]: " FORMAT
if [[ "$FORMAT" =~ ^[Yy]$ ]]; then
    echo "Formatting $DEVICE_NAME with $FILESYSTEM_TYPE filesystem..."
    sudo mkfs."$FILESYSTEM_TYPE" -L "$LABEL" "$DEVICE_NAME"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to format $DEVICE_NAME."
        exit 1
    fi
    echo "Disk formatted successfully."
fi

# Step 3: Create the mount point
if [ ! -d "$MOUNT_POINT" ]; then
    echo "Creating mount point at $MOUNT_POINT..."
    sudo mkdir -p "$MOUNT_POINT"
else
    echo "Mount point already exists at $MOUNT_POINT."
fi

# Step 4: Mount the disk temporarily
echo "Mounting $DEVICE_NAME to $MOUNT_POINT..."
sudo mount "$DEVICE_NAME" "$MOUNT_POINT"
if [ $? -ne 0 ]; then
    echo "Error: Failed to mount $DEVICE_NAME to $MOUNT_POINT."
    exit 1
fi
echo "Disk mounted successfully."

# Step 5: Set ownership and permissions
echo "Setting ownership and permissions for $MOUNT_POINT..."
sudo chown "$USER":"$USER" "$MOUNT_POINT"
sudo chmod 777 "$MOUNT_POINT"
echo "Permissions set."

# Step 6: Get the UUID of the device
DISK_UUID=$(sudo blkid -s UUID -o value "$DEVICE_NAME")
if [ -z "$DISK_UUID" ]; then
    echo "Error: Unable to retrieve UUID for $DEVICE_NAME."
    exit 1
fi
echo "Found UUID for $DEVICE_NAME: $DISK_UUID"

# Step 7: Add the disk to /etc/fstab for persistence
FSTAB_ENTRY="UUID=$DISK_UUID $MOUNT_POINT $FILESYSTEM_TYPE defaults 0 2"
if grep -q "$DISK_UUID" /etc/fstab; then
    echo "UUID already exists in /etc/fstab. Skipping update."
else
    echo "Adding entry to /etc/fstab:"
    echo "$FSTAB_ENTRY"
    echo "$FSTAB_ENTRY" | sudo tee -a /etc/fstab
fi

echo "All steps completed successfully!"
