#!/bin/sh

show_popular_tags() {
  echo "Popular DICOM Tags:"
  echo "  (0002,0010) - Transfer Syntax UID (compression info)"
  echo "  (0008,0016) - SOP Class UID"
  echo "  (0008,0018) - SOP Instance UID"
  echo "  (0008,0020) - Study Date"
  echo "  (0008,0030) - Study Time"
  echo "  (0008,0050) - Accession Number"
  echo "  (0008,0060) - Modality"
  echo "  (0010,0010) - Patient Name"
  echo "  (0010,0020) - Patient ID"
  echo "  (0020,000D) - Study Instance UID"
  echo "  (0020,000E) - Series Instance UID"
  echo "  (0020,0010) - Study ID"
}

# Usage: $0 -s <StudyInstanceUID> -t <DICOMTag> [-f <filename>] [-h for help]
usage() {
  echo "Usage: $0 -s <StudyInstanceUID> -t <DICOMTag> [-f <filename>] [-h]" >&2
  echo "Options:" >&2
  echo "  -s : Study Instance UID" >&2
  echo "  -t : DICOM Tag to search for" >&2
  echo "  -f : Optional filename filter" >&2
  echo "  -h : Show this help message and popular DICOM tags" >&2
  show_popular_tags
  exit 1
}

suid=""
tag=""
filename_filter=""

while getopts "s:t:f:h" opt; do
  case "$opt" in
    s) suid="$OPTARG" ;;
    t) tag="$OPTARG" ;;
    f) filename_filter="$OPTARG" ;;
    h) usage ;;
    *) usage ;;
  esac
done

# Only check for required parameters if -h was not used
if [ "$OPTIND" -eq 1 ] || [ -z "$suid" ] || [ -z "$tag" ]; then
  usage
fi

tab=$(printf '\t')# locateStudy.sh must be executable and in this path
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