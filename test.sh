#!/bin/bash

# Function to display usage information
usage() {
    echo "Usage: $0 /dev/sdX"
    exit 1
}

# Function to handle errors
error_exit() {
    echo "Error: $1"
    exit 1
}

# Check if drive is given
if [ -z "$1" ]; then
    usage
fi

DRIVE=$1

# Validate the drive identifier
if [[ ! $DRIVE =~ ^/dev/sd[a-z]$ ]]; then
    error_exit "Invalid drive identifier. Use format /dev/sdX."
fi

# Logging setup
LOGFILE="$(pwd)/partition_script.log"
exec > >(tee -i $LOGFILE)
exec 2>&1

# Enable debugging
set -x

echo "Starting partitioning and formatting of $DRIVE"

# Function to unmount partitions
unmount_partitions() {
    for PART in $(ls ${DRIVE}* 2>/dev/null | grep -E "${DRIVE}[0-9]+"); do
        umount $PART 2>/dev/null && echo "Unmounted $PART" || echo "Failed to unmount $PART"
    done
}

# Function to create partitions
create_partitions() {
    echo "Creating a new GPT partition table on $DRIVE"
    parted -s $DRIVE mklabel gpt || error_exit "Failed to create GPT partition table on $DRIVE"

    echo "Creating boot partition (2GB, FAT32)"
    parted -s -a optimal $DRIVE mkpart primary fat32 0% 2GB || error_exit "Failed to create boot partition"
    parted -s $DRIVE set 1 boot on || error_exit "Failed to set boot flag on boot partition"
    BOOT_PART="${DRIVE}1"

    echo "Creating root partition (80GB, ext4)"
    parted -s -a optimal $DRIVE mkpart primary ext4 2GB 82GB || error_exit "Failed to create root partition"
    ROOT_PART="${DRIVE}2"

    echo "Creating home partition (remaining space, ext4)"
    parted -s -a optimal $DRIVE mkpart primary ext4 82GB 100% || error_exit "Failed to create home partition"
    HOME_PART="${DRIVE}3"
}

# Function to format partitions
format_partitions() {
    echo "Formatting $BOOT_PART as FAT32 with label BOOT"
    mkfs.vfat -F 32 -n BOOT $BOOT_PART || error_exit "Failed to format boot partition as FAT32"

    echo "Formatting $ROOT_PART as ext4 with label ROOT"
    mkfs.ext4 -L ROOT $ROOT_PART || error_exit "Failed to format root partition as ext4"

    echo "Formatting $HOME_PART as ext4 with label HOME"
    mkfs.ext4 -L HOME $HOME_PART || error_exit "Failed to format home partition as ext4"
}

# Function to display the partition table
display_partition_table() {
    echo "Displaying partition table of $DRIVE"
    parted $DRIVE print || error_exit "Failed to display partition table of $DRIVE"
}

# Function to confirm action with the user
confirm_action() {
    echo "The script will perform the following actions on $DRIVE:"
    echo "1. Create a new GPT partition table."
    echo "2. Create a 2GB FAT32 boot partition with label BOOT."
    echo "3. Create an 80GB ext4 root partition with label ROOT."
    echo "4. Create an ext4 home partition using the remaining space with label HOME."
    echo "5. Format the partitions accordingly."
    read -p "Are you sure you want to proceed? (yes/no): " CONFIRM
    if [[ $CONFIRM != "yes" ]]; then
        error_exit "User aborted the operation."
    fi
}

# Execute functions
confirm_action
create_partitions
format_partitions
display_partition_table

# Disable debugging
set +x

echo "Partitioning and formatting of $DRIVE completed successfully."

exit 0
