#!/bin/sh
# Usage: merge_styuid_path.sh <uid_path_file> <demographics_file> > merged.txt
# Appends filesystem path as the LAST column: ...|PATH

set -eu

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <uid_path_file> <demographics_file>" >&2
  exit 2
fi

uid_path_file=$1
demog_file=$2

awk -F'|' '
  NR==FNR { map[$1]=$2; next }
  {
    uid=$1
    path=(uid in map ? map[uid] : "")
    print $0 "|" path
  }
' "$uid_path_file" "$demog_file"
