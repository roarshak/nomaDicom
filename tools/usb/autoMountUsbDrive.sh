#!/bin/bash

LOGFILE="/var/log/usb_auto_mount.log"
MOUNT_POINT="/mnt/usbdrive"

while true; do
    # Check if the USB drive is connected
    DEVICE=$(ls -l /dev/disk/by-id/ | grep usb | awk '{print $NF}' | sed 's|\.\./\.\./||')

    if [[ -n "$DEVICE" ]]; then
        echo "$(date) - USB Device detected: /dev/$DEVICE" | tee -a "$LOGFILE"

        # Check if it's already mounted
        if mount | grep -q "/dev/$DEVICE"; then
            echo "$(date) - Already mounted." | tee -a "$LOGFILE"
        else
            # Try mounting as NTFS (modify based on your system)
            echo "$(date) - Attempting to mount /dev/$DEVICE..." | tee -a "$LOGFILE"

            mkdir -p "$MOUNT_POINT"
            mount -t ntfs-3g /dev/${DEVICE}1 "$MOUNT_POINT" 2>> "$LOGFILE"

            if [[ $? -eq 0 ]]; then
                echo "$(date) - Successfully mounted at $MOUNT_POINT" | tee -a "$LOGFILE"
            else
                echo "$(date) - Failed to mount /dev/$DEVICE. Check logs." | tee -a "$LOGFILE"
            fi
        fi
    fi
    
    # Sleep for 5 seconds before checking again
    sleep 5
done
