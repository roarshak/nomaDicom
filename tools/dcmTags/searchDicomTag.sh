#!/bin/sh

# Check if the correct number of arguments is provided
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <dicom_file_path> <dicom_tag>"
    exit 1
fi

DICOM_FILE="$1"
DICOM_TAG="$2"
DCMDUMP="/home/medsrv/component/dicom/bin/dcmdump"

# Check if the DICOM file exists
if [ ! -f "$DICOM_FILE" ]; then
    echo "Error: File '$DICOM_FILE' not found."
    exit 1
fi

# Run dcmdump and search for the DICOM tag
$DCMDUMP "$DICOM_FILE" | grep -E "$DICOM_TAG" | sed "s|^|$(basename "$DICOM_FILE"): |"

# Exit with the status of the grep command
exit $?