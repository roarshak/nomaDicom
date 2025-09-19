#!/bin/bash
# Added to GDrive

# General Configuration
_DATE_FMT="%Y%m%d-%H%M%S"          # Date format for logging and file naming.
_LOG_SELF="editStorestate.log"     # Log file for migration process.

function usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -d, --device device_name     : Specify the device name for --fwddevice (e.g., DISASTER_RECOVERY)"
    echo "  -s study_uid                : Specify a single Study Instance UID to process"
    echo "  -f filename                 : Specify a file containing a list of Study Instance UIDs"
    exit 1
}

# Verify that the DeviceName variable is set.
function verifyDeviceName() {
    local dev="$1"
    if [[ -z "$dev" ]]; then
        echo "Error: Option -d or --device is required to set the value for --fwddevice."
        usage
    fi
}

# Verify that the provided device exists and is configured as a storage provider ("StrP").
function verifyStorageProvider() {
    local dev="$1"
    local count
    local query="
        SELECT COUNT(*)
        FROM Target LEFT JOIN DevServ
            ON Target.id = DevServ.DEVICE
        WHERE Target.id = '${dev}' AND
        DevServ.SERVICE LIKE '%StrP%';"
    count=$(echo "$query" | /home/medsrv/component/mysql/bin/mysql -N imagemedical)
    if [[ "$count" -eq 0 ]]; then
        echo "Error: Device '$dev' does not exist or is not configured as a storage provider (StrP)."
        exit 1
    fi
}

function processStudy() {
    local suid=$1

    # Check if suid is already processed by looking for it in the log file.
    if grep -Fq "$suid" "$_LOG_SELF"; then
        printf "%s Study UID %s already processed. Skipping.\n" "$(date "+$_DATE_FMT")" "$suid" | tee -a "$_LOG_SELF"
        return
    fi

    if [[ -n "$suid" ]]; then
        printf "%s Editing storestate of %s --fwddevice=%s\n" "$(date "+$_DATE_FMT")" "$suid" "$DeviceName" | tee -a "$_LOG_SELF"
        local ss_output
        ss_output="$(/home/medsrv/component/utils/bin/storestate -S "$suid" --fwddevice="$DeviceName" 2>&1)"
        
        if [[ -n "$ss_output" ]]; then
            while read -r line; do
                printf "%s %s\n" "$(date "+$_DATE_FMT")" "$line" | tee -a "$_LOG_SELF"
            done <<< "$ss_output"
        fi
    else
        printf "%s Error: Empty Study UID provided, skipping.\n" "$(date "+$_DATE_FMT")" | tee -a "$_LOG_SELF"
    fi
}

# Option parser
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--device) DeviceName="$2"; shift 2;;
        -s) single_suid="$2"; shift 2;;
        -f) filename="$2"; shift 2;;
        *) usage;;
    esac
done

# Perform device name verification and storage provider check.
verifyDeviceName "$DeviceName"
verifyStorageProvider "$DeviceName"

if [[ -n "$single_suid" ]]; then
    processStudy "$single_suid"
elif [[ -n "$filename" ]]; then
    if [[ -f "$filename" ]]; then
        while IFS= read -r suid; do
            processStudy "$suid"
        done < "$filename"
    else
        echo "Error: File '$filename' not found!" | tee -a "$_LOG_SELF"
        exit 1
    fi
else
    usage
fi
