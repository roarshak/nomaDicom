#!/usr/bin/env bash
set -euo pipefail

LOCATE="/home/medsrv/component/repositoryhandler/scripts/locateStudy.sh"

usage() {
  cat <<EOF
Usage:
  $0 <run_dir> --update-cache [--sleep SEC] [--cache FILE] [--errors FILE]
  $0 <run_dir> --merge        [--cache FILE] [--out FILE]

What it does:
  --update-cache : Reads SUIDs from the run's *SOT_StudyDemographics* file (pipe-delimited),
                   and appends NEW SUID|FPATH rows to the cache.
                   Only SUIDs not already in cache trigger locateStudy.sh calls.
                   Applies --sleep after every locateStudy call.

  --merge        : Writes a merged demographics file with filesystem path appended as LAST column.
                   Uses cache; does NOT call locateStudy.

Defaults:
  cache  = <case_dir>/suid_fspath_cache.txt   (case_dir = parent of run_dir)
  errors = <run_dir>/uid_fspath_errors.txt
  out    = <run_dir>/<SOT_basename>_with_fspath.txt
  sleep  = 0

Examples:
  # First time (slow, builds cache incrementally, gentle on server):
  $0 /path/to/sot_run_... --update-cache --sleep 0.02

  # Later (fast, only new SUIDs call locateStudy):
  $0 /path/to/sot_run_... --update-cache --sleep 0.02

  # Merge whenever:
  $0 /path/to/sot_run_... --merge
EOF
  exit 2
}

[[ $# -ge 2 ]] || usage

RUN_DIR="$1"
shift

[[ -d "$RUN_DIR" ]] || { echo "Error: run dir not found: $RUN_DIR" >&2; exit 3; }
[[ -x "$LOCATE" ]] || { echo "Error: not executable: $LOCATE" >&2; exit 5; }

DO_UPDATE=0
DO_MERGE=0
SLEEP_SEC="0"
CACHE_FILE=""
ERROR_FILE=""
OUT_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --update-cache) DO_UPDATE=1; shift ;;
    --merge)        DO_MERGE=1; shift ;;
    --sleep)        SLEEP_SEC="${2:-}"; shift 2 ;;
    --cache)        CACHE_FILE="${2:-}"; shift 2 ;;
    --errors)       ERROR_FILE="${2:-}"; shift 2 ;;
    --out)          OUT_FILE="${2:-}"; shift 2 ;;
    -h|--help)      usage ;;
    *) echo "Unknown option: $1" >&2; usage ;;
  esac
done

[[ "$DO_UPDATE" -eq 1 || "$DO_MERGE" -eq 1 ]] || usage

# Locate the run’s SOT file
SOT_FILE="$(find "$RUN_DIR" -maxdepth 1 -type f -name "*SOT_StudyDemographics*" | head -1)"
[[ -n "$SOT_FILE" && -f "$SOT_FILE" ]] || { echo "Error: no *SOT_StudyDemographics* file found in $RUN_DIR" >&2; exit 4; }

CASE_DIR="$(dirname "$RUN_DIR")"
CACHE_FILE="${CACHE_FILE:-$CASE_DIR/suid_fspath_cache.txt}"
ERROR_FILE="${ERROR_FILE:-$RUN_DIR/uid_fspath_errors.txt}"
OUT_FILE="${OUT_FILE:-$RUN_DIR/$(basename "${SOT_FILE%.txt}")_with_fspath.txt}"

UID_LIST="$RUN_DIR/suid_list_from_sot.txt"
NEW_UIDS="$RUN_DIR/suid_list_new.txt"

# Extract SUIDs from column 1 (pipe-delimited)
cut -d'|' -f1 "$SOT_FILE" > "$UID_LIST"

# Ensure cache exists
touch "$CACHE_FILE"

if [[ "$DO_UPDATE" -eq 1 ]]; then
  : > "$ERROR_FILE"

  echo "Updating cache (append-only): $CACHE_FILE"
  echo "Errors file:                 $ERROR_FILE"
  echo "Sleep per call:              ${SLEEP_SEC}s"
  echo "SOT file:                    $SOT_FILE"

  # Build list of SUIDs not already in cache (loads cached keys into awk set; fast for ~1M)
  awk -F'|' '
    NR==FNR { seen[$1]=1; next }
    { if ($1 != "" && !seen[$1]) print $1 }
  ' "$CACHE_FILE" "$UID_LIST" > "$NEW_UIDS"

  new_count=$(wc -l < "$NEW_UIDS" | tr -d ' ')
  echo "New SUIDs needing locateStudy: $new_count"

  tmp="${TMPDIR:-/tmp}/locateStudy.$$"
  trap 'rm -f "$tmp"' EXIT

  i=0
  while IFS= read -r suid || [[ -n "$suid" ]]; do
    [[ -n "$suid" ]] || continue
    i=$((i+1))

    "$LOCATE" -d "$suid" >"$tmp" 2>&1 || true

    # Accept exactly ONE "pure path" line:
    # - starts with /
    # - contains NO whitespace (conflict lines have spaces)
    # - is NOT the echoed command line
    path="$(
      awk '
        $0 ~ /^\// &&
        $0 !~ /locateStudy\.sh/ &&
        $0 !~ /[[:space:]]/ { print; exit }
      ' "$tmp"
    )"

    # Count how many pure-path candidates we got
    npaths="$(
      awk '
        $0 ~ /^\// &&
        $0 !~ /locateStudy\.sh/ &&
        $0 !~ /[[:space:]]/ { c++ }
        END { print c+0 }
      ' "$tmp"
    )"

    if [[ "$npaths" -eq 1 && -n "$path" ]]; then
      # Optionally sanity check existence (comment out if you don't want the stat calls):
      if [[ -e "$path" ]]; then
        printf '%s|%s\n' "$suid" "$path" >> "$CACHE_FILE"
      else
        {
          printf 'SUID: %s\n' "$suid"
          printf '%s\n' '---- locateStudy output (path not found on filesystem) ----'
          cat "$tmp"
          printf '%s\n\n' '----------------------------------------------------------'
        } >> "$ERROR_FILE"
      fi
    else
      {
        printf 'SUID: %s\n' "$suid"
        printf '%s\n' '---- locateStudy output ----'
        cat "$tmp"
        printf '%s\n\n' '----------------------------'
      } >> "$ERROR_FILE"
    fi

    # Throttle every call (simple + predictable)
    if [[ "$SLEEP_SEC" != "0" && "$SLEEP_SEC" != "0.0" ]]; then
      sleep "$SLEEP_SEC"
    fi

    # Tiny progress ping every 10k (keeps sanity during long runs)
    if (( i % 10000 == 0 )); then
      echo "Progress: processed $i / $new_count new SUIDs..."
    fi
  done < "$NEW_UIDS"

  echo "Cache update complete."
fi

if [[ "$DO_MERGE" -eq 1 ]]; then
  echo "Merging cache into SOT (append path as LAST column)..."
  echo "Output: $OUT_FILE"

  # Order-preserving merge (streams SOT in original order)
  awk -F'|' -v OFS='|' '
    NR==FNR { if ($1 != "") map[$1]=$2; next }
    {
      uid=$1
      path=(uid in map ? map[uid] : "")
      print $0, path
    }
  ' "$CACHE_FILE" "$SOT_FILE" > "$OUT_FILE"

  echo "Merge complete."
fi

echo "Done."
