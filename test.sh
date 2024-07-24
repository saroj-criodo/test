#!/bin/bash

# Partition variables
BOOT_SIZE="2GB"
ROOT_SIZE="80GB"
BOOT_LABEL="BOOT"
ROOT_LABEL="ROOT"
HOME_LABEL="HOME"

# Function to display usage information
usage() {
    echo "Usage: $0 /dev/sdX [unmount|partition|format|verify|mount|all]"
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
ACTION=${2:-all}

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

BOOT_PART="${DRIVE}1"
ROOT_PART="${DRIVE}2"
HOME_PART="${DRIVE}3"

# Function to unmount partitions
unmount_partitions() {
    echo "Unmounting partitions on $DRIVE"
    for PART in $(ls ${DRIVE}* 2>/dev/null | grep -E "${DRIVE}[0-9]+"); do
        umount $PART 2>/dev/null && echo "Unmounted $PART" || echo "Failed to unmount $PART"
    done
}

# Function to create partitions
create_partitions() {
    echo "Creating a new GPT partition table on $DRIVE"
    parted -s $DRIVE mklabel gpt || error_exit "Failed to create GPT partition table on $DRIVE"

    echo "Creating boot partition (${BOOT_SIZE}, FAT32)"
    parted -s -a optimal $DRIVE mkpart primary fat32 0% ${BOOT_SIZE} || error_exit "Failed to create boot partition"
    parted -s $DRIVE set 1 boot on || error_exit "Failed to set boot flag on boot partition"

    echo "Creating root partition (${ROOT_SIZE}, ext4)"
    parted -s -a optimal $DRIVE mkpart primary ext4 ${BOOT_SIZE} $((${BOOT_SIZE%GB} + ${ROOT_SIZE%GB}))GB || error_exit "Failed to create root partition"

    echo "Creating home partition (remaining space, ext4)"
    parted -s -a optimal $DRIVE mkpart primary ext4 $((${BOOT_SIZE%GB} + ${ROOT_SIZE%GB}))GB 100% || error_exit "Failed to create home partition"
}

# Function to format partitions
format_partitions() {
    echo "Formatting $BOOT_PART as FAT32 with label $BOOT_LABEL"
    mkfs.vfat -F 32 -n $BOOT_LABEL $BOOT_PART || error_exit "Failed to format boot partition as FAT32"

    echo "Formatting $ROOT_PART as ext4 with label $ROOT_LABEL"
    mkfs.ext4 -L $ROOT_LABEL $ROOT_PART || error_exit "Failed to format root partition as ext4"

    echo "Formatting $HOME_PART as ext4 with label $HOME_LABEL"
    mkfs.ext4 -L $HOME_LABEL $HOME_PART || error_exit "Failed to format home partition as ext4"
}

# Function to display the partition table
display_partition_table() {
    echo "Displaying partition table of $DRIVE"
    parted $DRIVE print || error_exit "Failed to display partition table of $DRIVE"
}

# Function to verify partitions
verify_partitions() {
    echo "Verifying partitions"
    blkid $BOOT_PART | grep -q "TYPE=\"vfat\"" || error_exit "Boot partition is not FAT32"
    blkid $ROOT_PART | grep -q "TYPE=\"ext4\"" || error_exit "Root partition is not ext4"
    blkid $HOME_PART | grep -q "TYPE=\"ext4\"" || error_exit "Home partition is not ext4"
}

# Function to mount partitions
mount_partitions() {
    echo "Mounting partitions"
    mkdir -p /mnt /mnt/boot /mnt/home

    mount $ROOT_PART /mnt || (dmesg | tail -n 10 && error_exit "Failed to mount root partition")
    echo "Mounted $ROOT_PART at /mnt"

    mount $BOOT_PART /mnt/boot || (dmesg | tail -n 10 && error_exit "Failed to mount boot partition")
    echo "Mounted $BOOT_PART at /mnt/boot"

    mount $HOME_PART /mnt/home || (dmesg | tail -n 10 && error_exit "Failed to mount home partition")
    echo "Mounted $HOME_PART at /mnt/home"
}

# Function to confirm action with the user
confirm_action() {
    echo "The script will perform the following actions on $DRIVE:"
    echo "1. Create a new GPT partition table."
    echo "2. Create a ${BOOT_SIZE} FAT32 boot partition with label $BOOT_LABEL."
    echo "3. Create an ${ROOT_SIZE} ext4 root partition with label $ROOT_LABEL."
    echo "4. Create an ext4 home partition using the remaining space with label $HOME_LABEL."
    echo "5. Format the partitions accordingly."
    echo "6. Verify the partitions."
    echo "7. Mount the partitions to /mnt, /mnt/boot, and /mnt/home."
    read -p "Are you sure you want to proceed? (yes/no): " CONFIRM
    if [[ $CONFIRM != "yes" ]]; then
        error_exit "User aborted the operation."
    fi
}

# Execute functions based on the action
confirm_action

case $ACTION in
    unmount)
        unmount_partitions
        ;;
    partition)
        create_partitions
        ;;
    format)
        format_partitions
        ;;
    verify)
        verify_partitions
        ;;
    mount)
        mount_partitions
        ;;
    all)
        unmount_partitions
        create_partitions
        format_partitions
        display_partition_table
        verify_partitions
        mount_partitions
        ;;
    *)
        usage
        ;;
esac

# Disable debugging
set +x

echo "Partitioning, formatting, and mounting of $DRIVE completed successfully."

exit 0
