#!/bin/bash

# Input file containing full paths of DICOM files
input_file="$1"

# Configuration variables
_MYAET="PBUILDER"
# _IP_ADDR="localhost"
_IP_ADDR="10.4.11.130"
_TARGET_AET="MIGRATION"
_PORT="109"
_TS="-R -xs"
DEBUGFLAG="-v"
# DEBUGFLAG=""
SCUOPTS="$_TS -aet $_MYAET -aec $_TARGET_AET"
STORESCU_BIN="/home/medsrv/component/dicom/bin/storescu"

# Log files
LOGFILE="storescu_commands.log"
ERRORLOG="storescu_errors.log"

# Ensure the input file exists
if [[ ! -f "$input_file" ]]; then
    echo "Error: Input file '$input_file' not found."
    exit 1
fi

# Process each DICOM file in the input list
while IFS= read -r dicom_file; do
    # Check if dicom_file already exists in LOGFILE
    if grep -Fq "$dicom_file" "$LOGFILE"; then
        echo "Skipping $dicom_file; already processed."
        continue
    fi

    # Construct the storescu command
    CMD="$STORESCU_BIN $DEBUGFLAG $SCUOPTS $_IP_ADDR $_PORT $dicom_file"

    # Display and log the command being executed
    echo "Executing: $CMD"
    echo "$CMD" >> "$LOGFILE"

    # Execute the command
    eval $CMD
    if [[ $? -ne 0 ]]; then
        # Log the failed dicom_file path
        echo "$dicom_file" >> "$ERRORLOG"
    fi

    # Sleep for 1 second before the next iteration
    sleep 1
done < "$input_file"
