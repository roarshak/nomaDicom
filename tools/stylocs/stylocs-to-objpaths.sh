#!/bin/bash

# Usage: ./script.sh <study_locations_file> <output_file>

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <study_locations_file> <output_file>"
  exit 1
fi

study_locations_file="$1"
output_file="$2"

# Ensure the input file exists
if [ ! -f "$study_locations_file" ]; then
  echo "Error: Study locations file '$study_locations_file' not found."
  exit 1
fi

# Clear or create the output file
> "$output_file"

# Process each study location
while IFS= read -r study_location; do
  if [ -d "$study_location" ]; then
    # List only immediate files, excluding subdirectories and their contents
    find "$study_location" -maxdepth 1 -type f >> "$output_file"
  else
    echo "Warning: '$study_location' is not a directory" >&2
  fi
done < "$study_locations_file"
