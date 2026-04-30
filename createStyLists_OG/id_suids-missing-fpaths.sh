#!/bin/sh
# Usage: find_missing_fspaths.sh <merged_demographics_file>
# Outputs STYIUIDs that are missing the last-column filesystem path to:
#   sty-demographics-missing-fspaths.txt

set -eu

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <merged_demographics_file>" >&2
  exit 2
fi

infile=$1
outfile="sty-demographics-missing-fspaths.txt"

# Missing path means: last field is empty (or whitespace) OR last field is literally "MISSING_PATH"
awk -F'|' '
  {
    last=$NF
    gsub(/[[:space:]]+/, "", last)
    if (last == "" || last == "MISSING_PATH") print $1
  }
' "$infile" > "$outfile"

