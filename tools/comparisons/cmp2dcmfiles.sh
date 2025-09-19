#!/bin/sh

# Check if the correct number of arguments is provided
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <dicom_file_1> <dicom_file_2>"
    exit 1
fi

# Assign the file paths to variables
FILE1=$1
FILE2=$2
DCMDUMP="/home/medsrv/component/dicom/bin/dcmdump"

# Check if the dcmdump utility exists
if [ ! -x "$DCMDUMP" ]; then
    echo "Error: dcmdump utility not found or not executable at $DCMDUMP"
    exit 1
fi

# Run dcmdump on both files and store output in temporary files
TMP1=$(mktemp)
TMP2=$(mktemp)

$DCMDUMP "$FILE1" > "$TMP1"
$DCMDUMP "$FILE2" > "$TMP2"

# Compare the outputs and show differences side by side, excluding identical lines
# diff -W 200 -y "$TMP1" "$TMP2"
# diff -W 200 -y --suppress-common-lines "$TMP1" "$TMP2"
sdiff -w 200 "$TMP1" "$TMP2"

# Clean up temporary files
rm -f "$TMP1" "$TMP2"

