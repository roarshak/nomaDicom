#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# VARIABLE DEFINITIONS
# ============================================================================
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
component_id="COMP4"
run_arg=""

work_dir=""
run_dir=""
cfg_file=""
log_file=""

# Populated from cfg (do not edit here)
sot_file=""
suid_fspath_file=""
merged_sot_file=""
current_sot_link=""
sot_header=""
fspath_strip_prefix=""
merged_count=""

# ============================================================================
# FUNCTION DEFINITIONS
# ============================================================================

usage_and_exit() {
  local exit_code="${1:-0}"
  cat <<EOF
Usage:
  $0 --run <run-dir-name-or-path>

Description:
  Component 4 of the SOT pipeline.
  Merges run-level suid_fspath into SOT and writes a NEW merged file.

Behavior:
  - Accepts either full run directory path or run directory name relative to work dir
  - Does not overwrite base SOT
  - Updates current symlink: <work_dir>/current_sot.txt
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
  : "${sot_extract_fn:?sot_extract_fn must be set in cfg}"
  : "${suid_fspath_fn:?suid_fspath_fn must be set in cfg}"
  : "${current_sot_link:?current_sot_link must be set in cfg}"
  : "${fspath_strip_prefix:=}"

  work_dir="$(resolve_path "$script_dir" "$work_dir")"
  current_sot_link="$(resolve_path "$work_dir" "$current_sot_link")"
}

find_files() {
  local merged_stamp
  local base_name

  sot_file="$run_dir/$sot_extract_fn"
  suid_fspath_file="$run_dir/$suid_fspath_fn"

  [ -f "$sot_file" ] || { echo "Error: base SOT file not found in $run_dir" >&2; exit 5; }
  [ -f "$suid_fspath_file" ] || { echo "Error: suid_fspath file not found: $suid_fspath_file" >&2; exit 6; }

  merged_stamp="$(date '+%Y%m%d_%H%M%S')"
  base_name="$(basename "${sot_file%.txt}")"
  merged_sot_file="$run_dir/${base_name}_with_fspath_${merged_stamp}.txt"
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

merge_files() {
  log_msg "Merging SOT with suid_fspath into: $merged_sot_file"
  if [ -n "$sot_header" ]; then
    {
      printf '%s|FSPATH\n' "$sot_header"
      awk -F'|' -v OFS='|' -v strip="$fspath_strip_prefix" '
        NR==FNR { map[$1]=$2; next }
        {
          uid=$1
          path=(uid in map ? map[uid] : "")
          if (strip != "" && index(path, strip) == 1) {
            path = substr(path, length(strip) + 1)
          }
          print $0, path
        }
      ' "$suid_fspath_file" "$sot_file"
    } > "$merged_sot_file"
  else
    awk -F'|' -v OFS='|' -v strip="$fspath_strip_prefix" '
      NR==FNR { map[$1]=$2; next }
      {
        uid=$1
        path=(uid in map ? map[uid] : "")
        if (strip != "" && index(path, strip) == 1) {
          path = substr(path, length(strip) + 1)
        }
        print $0, path
      }
    ' "$suid_fspath_file" "$sot_file" > "$merged_sot_file"
  fi

  [ -s "$merged_sot_file" ] || { echo "Error: merged SOT file is empty: $merged_sot_file" >&2; exit 7; }
  merged_count="$(wc -l < "$merged_sot_file" | tr -d ' ')"
}

refresh_current_symlink() {
  ln -sfn "$merged_sot_file" "$current_sot_link"
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

find_files
log_msg "Starting component 4 (merge)"
merge_files
refresh_current_symlink
log_msg "Merged SOT records: $merged_count"
log_msg "Merged SOT file: $merged_sot_file"
log_msg "Current SOT symlink: $current_sot_link"
