#!/bin/sh
# Usage: build_uid_fspath_map.sh <styuid_list_file> <out_map_file> [error_file]
#
# Reads StudyInstanceUIDs (one per line), runs:
#   /home/medsrv/component/repositoryhandler/scripts/locateStudy.sh -d <UID>
# Writes:
#   <UID>|<path>
# to out_map_file.
#
# If locateStudy.sh output is not exactly ONE absolute path line, writes details to error_file.

set -eu

LOCATE="/home/medsrv/component/repositoryhandler/scripts/locateStudy.sh"

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
  echo "Usage: $0 <styuid_list_file> <out_map_file> [error_file]" >&2
  exit 2
fi

infile=$1
outfile=$2
errfile=${3:-locateStudy-errors.txt}

: > "$outfile"
: > "$errfile"

tmp="${TMPDIR:-/tmp}/locateStudy.$$"
cleanup() { rm -f "$tmp"; }
trap cleanup EXIT HUP INT TERM

while IFS= read -r uid || [ -n "$uid" ]; do
  case "$uid" in
    ''|\#*) continue ;;
  esac

  "$LOCATE" -d "$uid" >"$tmp" 2>&1 || true

  paths=$(
    awk '
      $0 ~ /^\// && $0 !~ /locateStudy\.sh/ { print }
    ' "$tmp"
  )

  npaths=$(printf "%s\n" "$paths" | awk 'NF{c++} END{print c+0}')

  if [ "$npaths" -eq 1 ]; then
    path=$(printf "%s\n" "$paths" | awk 'NF{print; exit}')
    printf "%s|%s\n" "$uid" "$path" >> "$outfile"
  else
    {
      printf "UID: %s\n" "$uid"
      printf "%s\n" "---- locateStudy output ----"
      cat "$tmp"
      printf "%s\n" "----------------------------"
      printf "\n"
    } >> "$errfile"
  fi
done < "$infile"

