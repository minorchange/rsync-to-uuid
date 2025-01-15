#!/bin/bash

# Usage function
usage() {
  echo "Usage: $0 <STORAGE_UUID> <SOURCE_DIR> <TARGET_DIR_NAME>"
  echo
  echo "Arguments:"
  echo "  STORAGE_UUID   The UUID of the storage device to sync with."
  echo "  SOURCE_DIR     The local folder to sync from."
  echo "  TARGET_DIR_NAME The folder name on the storage device to sync to."
  echo
  exit 1
}

# Validate arguments
validate_arguments() {
  if [ $# -ne 3 ]; then
    echo "Error: Missing arguments."
    usage
  fi

  if [ ! -d "$SOURCE_DIR" ]; then
    echo "Error: Source directory does not exist: $SOURCE_DIR"
    exit 1
  fi
}

# Get device path from UUID
get_device_path() {
  DEVICE_PATH=$(blkid -U "$STORAGE_UUID")
  if [ -z "$DEVICE_PATH" ]; then
    echo "The specified storage device is not connected. Exiting."
    exit 1
  fi
}

# Mount storage device using udisksctl
mount_device() {
  MOUNT_POINT=$(lsblk -o UUID,MOUNTPOINT | grep "$STORAGE_UUID" | awk '{print $2}')
  WAS_ALREADY_MOUNTED=false

  if [ -z "$MOUNT_POINT" ]; then
    echo "Storage device detected but not mounted. Attempting to mount using udisksctl..."
    udisksctl_output=$(udisksctl mount --block-device "$DEVICE_PATH" --no-user-interaction 2>&1)
    if [ $? -ne 0 ]; then
      echo "Failed to mount the storage device using udisksctl. Exiting."
      echo "$udisksctl_output"
      exit 1
    fi

    MOUNT_POINT=$(echo "$udisksctl_output" | grep "Mounted /dev/" | awk '{print $4}' | tr -d '.')
    if [ -z "$MOUNT_POINT" ]; then
      echo "Could not determine the mount point from udisksctl output. Exiting."
      exit 1
    fi

    echo "Storage device mounted successfully at $MOUNT_POINT."
  else
    WAS_ALREADY_MOUNTED=true
    echo "Storage device is already mounted at $MOUNT_POINT."
  fi
}

# Ensure target directory exists
ensure_target_directory() {
  TARGET_DIR="$MOUNT_POINT/$TARGET_DIR_NAME"
  if [ ! -d "$TARGET_DIR" ]; then
    echo "Creating target directory: $TARGET_DIR"
    mkdir -p "$TARGET_DIR"
  fi
}

# Perform the rsync operation
perform_rsync() {
  echo "Starting rsync from $SOURCE_DIR to $TARGET_DIR..."
  rsync -av --progress "$SOURCE_DIR/" "$TARGET_DIR/"
  if [ $? -ne 0 ]; then
    echo "Error during rsync. Exiting."
    cleanup
    exit 1
  fi
  echo "Rsync completed successfully."
}

# Unmount the device if it was mounted by the script
cleanup() {
  if [ "$WAS_ALREADY_MOUNTED" = false ]; then
    echo "Unmounting the storage device..."
    udisksctl unmount --block-device "$DEVICE_PATH"
    if [ $? -ne 0 ]; then
      echo "Failed to unmount the storage device. Please check manually."
    else
      echo "Storage device unmounted successfully."
    fi
  else
    echo "Storage device was already mounted. Leaving it as-is."
  fi
}

# Main script logic
main() {
  STORAGE_UUID="$1"
  SOURCE_DIR="$2"
  TARGET_DIR_NAME="$3"

  validate_arguments "$@"
  get_device_path
  mount_device
  ensure_target_directory
  perform_rsync
  cleanup
}

# Entry point
main "$@"
