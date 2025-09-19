#!/bin/bash

# Log file to store device detection events
logfile="usb_device_info.log"

# Step 1: Capture relevant dmesg output
dmesg_output=$(dmesg | awk '/USB Mass Storage support registered/,/usb-storage: device scan complete/')
echo "=== Captured dmesg USB Event ===" | tee -a "$logfile"
echo "$dmesg_output" | tee -a "$logfile"

# Step 2: Extract assigned device (e.g., sdc)
device=$(echo "$dmesg_output" | awk '/Attached scsi disk/ {print $NF}')
if [[ -z "$device" ]]; then
    echo "No USB storage device found in dmesg output." | tee -a "$logfile"
    exit 1
fi
echo "Detected USB device: /dev/$device" | tee -a "$logfile"

# Step 3: Find SCSI host ID from dmesg output
scsi_host=$(echo "$dmesg_output" | awk '/Attached scsi disk/ {print $(NF-4)}' | cut -d: -f1)
if [[ -z "$scsi_host" ]]; then
    echo "Failed to determine SCSI host ID." | tee -a "$logfile"
    exit 1
fi
echo "Detected SCSI host: host$scsi_host" | tee -a "$logfile"

# Step 4: Check device state
device_STATE=$(cat /sys/block/$device/device/state 2>/dev/null)
if [[ -z "$device_STATE" ]]; then
    echo "Device state check failed. /dev/$device may not be present." | tee -a "$logfile"
else
    echo "Device state: $device_STATE" | tee -a "$logfile"
fi

# Step 5: Capture time and by-id link
usb_id_entry=$(ls -l /dev/disk/by-id/ | grep usb | grep "$device")
usb_timestamp=$(echo "$usb_id_entry" | awk '{print $6, $7, $8}')
echo "Detected at: $usb_timestamp" | tee -a "$logfile"

# Step 6: Force a rescan of the SCSI bus
if [[ -e /sys/class/scsi_host/host$scsi_host/scan ]]; then
    echo "Rescanning SCSI bus for host$scsi_host..." | tee -a "$logfile"
    echo "- - -" > /sys/class/scsi_host/host$scsi_host/scan
else
    echo "SCSI host$scsi_host scan file does not exist. Skipping rescan." | tee -a "$logfile"
fi

# Step 7: Print disk partition info using parted
echo "=== Disk Partition Information ===" | tee -a "$logfile"
parted /dev/$device print | tee -a "$logfile"

# Step 8: Print summary
echo -e "\n=== USB Storage Device Summary ===" | tee -a "$logfile"
echo "Device: /dev/$device" | tee -a "$logfile"
echo "SCSI Host: host$scsi_host" | tee -a "$logfile"
echo "Attached at: $usb_timestamp" | tee -a "$logfile"
echo "State: $device_STATE" | tee -a "$logfile"
echo "Partition Info:" | tee -a "$logfile"
parted /dev/$device print | tee -a "$logfile"
echo "===================================" | tee -a "$logfile"

exit 0
