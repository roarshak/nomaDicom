#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# VARIABLE DEFINITIONS
# ============================================================================
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
component_id="COMP2"
run_arg=""

work_dir=""
run_dir=""
cfg_file=""
log_file=""

# Populated from cfg (do not edit here)
sot_dstudy_fn=""
sot_extract_fn=""
dstudy_path=""
pbr_path=""
sot_path=""

tmp_dstudy_sorted=""
tmp_pbr_sorted=""
sot_count=""

# ============================================================================
# FUNCTION DEFINITIONS
# ============================================================================

usage_and_exit() {
  local exit_code="${1:-0}"
  cat <<EOF
Usage:
  $0 --run <run-dir-name-or-path>

Description:
  Component 2 of the SOT pipeline.
  Uses the run directory's dstudy + pbr files to create the SOT file with:
    adjusted_numofobj = numofobj - pbr_count

Behavior:
  - Accepts either full run directory path or run directory name relative to work dir
  - Appends component-tagged log entries to: <run_dir>/pipeline.log

Options:
  --run <run-dir>           Required.
  -h, --help                Show this help.
EOF
  exit "$exit_code"
}

log_msg() {
  local message="$1"
  printf '%s|%s|%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$component_id" "$message" | tee -a "$log_file"
}

resolve_run_dir() {
  if [ -d "$run_arg" ]; then
    run_dir="$(cd "$run_arg" && pwd)"
  elif [ -n "${SOT_WORK_DIR:-}" ] && [ -d "$SOT_WORK_DIR/$run_arg" ]; then
    run_dir="$(cd "$SOT_WORK_DIR/$run_arg" && pwd)"
  elif [ -n "${WORK_DIR:-}" ] && [ -d "$WORK_DIR/$run_arg" ]; then
    run_dir="$(cd "$WORK_DIR/$run_arg" && pwd)"
  elif [ -d "$script_dir/$run_arg" ]; then
    run_dir="$(cd "$script_dir/$run_arg" && pwd)"
  else
    echo "Error: run directory not found: $run_arg" >&2
    exit 3
  fi
}

find_config_file() {
  cfg_file="$(find "$run_dir" -maxdepth 1 -type f -name '*.cfg' | head -n 1)"
  [ -n "$cfg_file" ] || { echo "Error: no cfg file found in $run_dir" >&2; exit 4; }
}

source_config() {
  # shellcheck disable=SC1090
  if [ -f "$run_dir/run_cfg_resolved.sh" ]; then
    . "$run_dir/run_cfg_resolved.sh"
  else
    . "$cfg_file"
  fi
  : "${work_dir:?work_dir must be set in cfg}"
  : "${sot_dstudy_fn:?sot_dstudy_fn must be set in cfg}"
  : "${sot_extract_fn:?sot_extract_fn must be set in cfg}"

  work_dir="$(resolve_path "$script_dir" "$work_dir")"
}

find_input_files() {
  dstudy_path="$run_dir/$sot_dstudy_fn"
  pbr_path="$(find "$run_dir" -maxdepth 1 -type f -name 'sot_pbrcounts*.txt' | sort | head -n 1)"

  [ -n "$dstudy_path" ] || { echo "Error: dstudy file not found in $run_dir" >&2; exit 5; }
  [ -n "$pbr_path" ] || { echo "Error: pbr file not found in $run_dir" >&2; exit 6; }
}

setup_output_paths() {
  sot_path="$run_dir/$sot_extract_fn"

  tmp_dstudy_sorted="$run_dir/.tmp_dstudy_sorted.$$"
  tmp_pbr_sorted="$run_dir/.tmp_pbr_sorted.$$"
}

cleanup() {
  rm -f "$tmp_dstudy_sorted" "$tmp_pbr_sorted"
}

build_sot_file() {
  log_msg "Sorting input files for join"
  LC_ALL=C sort -t '|' -k1,1 "$dstudy_path" > "$tmp_dstudy_sorted"
  LC_ALL=C sort -t '|' -k1,1 "$pbr_path" > "$tmp_pbr_sorted"

  log_msg "Building SOT file: $sot_path"
  join -t '|' -a1 -o 1.1,1.2,2.2,1.3,1.4,1.5,1.6,1.7,1.8,1.9,1.10,1.11,1.12,1.13,1.14,1.15 \
    "$tmp_dstudy_sorted" "$tmp_pbr_sorted" \
    | awk -F '|' '
      BEGIN{OFS="|"}
      {
        pbr=($3==""?0:$3)
        adj=$2-pbr
        m=$16
        if (m=="") {
          label=""
        } else if (m=="-80") {
          label="Ordered"
        } else if (m=="-40") {
          label="Scheduled"
        } else if (m=="-20") {
          label="In Process"
        } else if (m=="-5") {
          label="Completed"
        } else if (m=="0") {
          label="Unviewed"
        } else if (m=="20") {
          label="Viewed"
        } else if (m=="50") {
          label="Read"
        } else if (m=="60") {
          label="Dictated"
        } else if (m=="80") {
          label="Preliminary"
        } else if (m=="100") {
          label="Final"
        } else {
          label=m
        }
        print $1, adj, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, label
      }' \
    > "$sot_path"

  [ -s "$sot_path" ] || { echo "Error: generated SOT file is empty: $sot_path" >&2; exit 7; }
  sot_count="$(wc -l < "$sot_path" | tr -d ' ')"
  log_msg "SOT build complete (records=$sot_count)"
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --run)
        run_arg="${2:-}"
        shift 2
        ;;
      -h|--help)
        usage_and_exit 0
        ;;
      *)
        echo "Unknown argument: $1" >&2
        usage_and_exit 2
        ;;
    esac
  done
}

resolve_path() {
  local base="$1"
  local target="$2"
  if [ -z "$target" ]; then
    printf '%s\n' "$target"
  elif [[ "$target" = /* ]]; then
    printf '%s\n' "$target"
  else
    printf '%s/%s\n' "$base" "$target"
  fi
}

validate_args() {
  [ -n "$run_arg" ] || { echo "Error: --run is required." >&2; usage_and_exit 2; }
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================
parse_args "$@"
validate_args
resolve_run_dir
find_config_file
source_config

log_file="$run_dir/pipeline.log"
touch "$log_file"

find_input_files
setup_output_paths
trap cleanup EXIT

log_msg "Starting component 2 (build-sot)"
build_sot_file
log_msg "SOT file path: $sot_path"
