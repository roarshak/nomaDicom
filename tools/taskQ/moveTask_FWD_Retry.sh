#!/bin/bash

# Ensure the script is run by the user 'medsrv'
if [[ "$(whoami)" != "medsrv" ]]; then
    echo "This script must be run as the 'medsrv' user."
    exit 1
fi

# Define necessary directories
RETRY_DIR="/home/medsrv/var/taskqueue/.retry"
SUSPENDED_DIR="/home/medsrv/var/taskqueue/.suspended"

# Stop the taskd service
echo "Stopping taskd service..."
~/component/taskd/ctrl stop

# Ensure the suspended directory exists
mkdir -p "$SUSPENDED_DIR"

# Find and move files older than 7 days
echo "Moving files older than 7 days..."
find "$RETRY_DIR" -type f -name "019*" -mtime +7 -exec mv {} "$SUSPENDED_DIR" \;

# Start the taskd service
echo "Starting taskd service..."
~/component/taskd/ctrl start

echo "Script execution completed."
