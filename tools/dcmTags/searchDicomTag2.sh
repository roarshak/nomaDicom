#!/bin/sh

# Usage: $0 -s <StudyInstanceUID> -t <DICOMTag> [-f <filename>]
usage() {
  echo "Usage: $0 -s <StudyInstanceUID> -t <DICOMTag> [-f <filename>]" >&2
  exit 1
}

suid=""
tag=""
filename_filter=""

while getopts "s:t:f:" opt; do
  case "$opt" in
    s) suid="$OPTARG" ;;
    t) tag="$OPTARG" ;;
    f) filename_filter="$OPTARG" ;;
    *) usage ;;
  esac
done

[ -z "$suid" ] || [ -z "$tag" ] && usage

tab=$(printf '\t')

# locateStudy.sh must be executable and in this path
stydir=$(/home/medsrv/component/repositoryhandler/scripts/locateStudy.sh -d "$suid") || {
  echo "Error: locateStudy.sh failed for UID $suid" >&2
  exit 1
}

find "$stydir" -maxdepth 1 -type f | while IFS= read -r filepath; do
  filename=$(basename "$filepath")
  # If filename_filter is set, skip files that don't match
  if [ -n "$filename_filter" ]; then
    case "$filename_filter" in
      /*) [ "$filepath" != "$filename_filter" ] && continue ;; # full path match
      *)  [ "$filename" != "$filename_filter" ] && continue ;; # base name match
    esac
  fi
  # Directly extract the DICOM tag using dcmdump or another suitable tool
  # value=$(/home/medsrv/component/dicom/bin/dcmdump +P "$tag" "$filepath" 2>/dev/null)
  value=$(/home/medsrv/component/dicom/bin/dcmdump +P "$tag" "$filepath" 2>/dev/null | awk -F'UI =' '/UI =/ {gsub(/^[ \t]+|[ \t]+$/, "", $2); split($2, a, " "); print a[1]}' )
  if [ -n "$value" ]; then
    printf "%s\t%s\n" "$filename" "$value"
  fi
done