#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# VARIABLE DEFINITIONS
# ============================================================================
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
component_id="COMP3"
run_arg=""
sleep_sec="0"

work_dir=""
run_dir=""
cfg_file=""
log_file=""

# Populated from cfg (do not edit here)
repository_handler_script=""
sot_file=""
cache_file=""
run_suid_fspath_file=""
current_suid_link=""
fail_file=""

all_uid_file=""
existing_uid_file=""
missing_uid_file=""
cache_hits_file=""
cache_miss_file=""
tmp_locate=""

total_sot_uids=""
existing_run_uids=""
missing_uids=""

# ============================================================================
# FUNCTION DEFINITIONS
# ============================================================================

usage_and_exit() {
  local exit_code="${1:-0}"
  cat <<EOF
Usage:
  $0 --run <run-dir-name-or-path> [--sleep <seconds>]

Description:
  Component 3 of the SOT pipeline.
  Creates/updates run-level suid_fspath by:
    1) Reading SUIDs from the run's SOT file
    2) Appending only missing SUID entries into <run_dir>/suid_fspath.txt
    3) Reusing global cache at <work_dir>/suid_fspath_cache.txt
    4) Calling locateStudy.sh only for SUIDs missing from cache

Behavior:
  - Global cache is append-only and never pruned automatically
  - Run file appends only missing entries on rerun
  - Updates current symlink: <work_dir>/current_suid_fspath.txt
  - Logs locateStudy failures to a work_dir failure file and continues

Options:
  --run <run-dir>           Required.
  --sleep <seconds>         Optional throttle between locateStudy calls (default: 0).
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
  : "${locate_study_bin:?locate_study_bin must be set in cfg}"
  : "${suid_fspath_cache_fn:?suid_fspath_cache_fn must be set in cfg}"
  : "${suid_fspath_fn:?suid_fspath_fn must be set in cfg}"
  : "${current_suid_fspath_link:?current_suid_fspath_link must be set in cfg}"

  work_dir="$(resolve_path "$script_dir" "$work_dir")"
  repository_handler_script="$(resolve_path "$work_dir" "$locate_study_bin")"
  cache_file="$(resolve_path "$work_dir" "$suid_fspath_cache_fn")"
  current_suid_link="$(resolve_path "$work_dir" "$current_suid_fspath_link")"
}

find_sot_file() {
  sot_file="$run_dir/$sot_extract_fn"
  [ -f "$sot_file" ] || { echo "Error: base SOT file not found in $run_dir" >&2; exit 5; }
}

validate_repository_handler() {
  [ -x "$repository_handler_script" ] || {
    echo "Error: locateStudy script not found or not executable: $repository_handler_script" >&2
    exit 6
  }
}

setup_paths() {
  run_suid_fspath_file="$run_dir/$suid_fspath_fn"
  fail_file="$work_dir/locateStudy_failures.txt"

  touch "$cache_file"
  touch "$run_suid_fspath_file"
  touch "$fail_file"

  all_uid_file="$run_dir/.tmp_all_uids.$$"
  existing_uid_file="$run_dir/.tmp_existing_uids.$$"
  missing_uid_file="$run_dir/.tmp_missing_uids.$$"
  cache_hits_file="$run_dir/.tmp_cache_hits.$$"
  cache_miss_file="$run_dir/.tmp_cache_miss.$$"
  tmp_locate="$run_dir/.tmp_locate.$$"
}

cleanup() {
  rm -f "$all_uid_file" "$existing_uid_file" "$missing_uid_file" "$cache_hits_file" "$cache_miss_file" "$tmp_locate"
}

build_missing_uid_list() {
  cut -d '|' -f1 "$sot_file" | awk 'NF' | LC_ALL=C sort -u > "$all_uid_file"
  cut -d '|' -f1 "$run_suid_fspath_file" | awk 'NF' | LC_ALL=C sort -u > "$existing_uid_file"
  comm -23 "$all_uid_file" "$existing_uid_file" > "$missing_uid_file"

  total_sot_uids="$(wc -l < "$all_uid_file" | tr -d ' ')"
  existing_run_uids="$(wc -l < "$existing_uid_file" | tr -d ' ')"
  missing_uids="$(wc -l < "$missing_uid_file" | tr -d ' ')"
}

append_from_cache_or_lookup() {
  local suid="$1"
  local cached_line
  local path
  local path_count

  cached_line="$(awk -F '|' -v uid="$suid" '$1==uid {print $0; exit}' "$cache_file")"
  if [ -n "$cached_line" ]; then
    printf '%s\n' "$cached_line" >> "$run_suid_fspath_file"
    return
  fi

  "$repository_handler_script" -d "$suid" > "$tmp_locate" 2>&1 || true

  path="$(awk '$0 ~ /^\// && $0 !~ /locateStudy\.sh/ && $0 !~ /[[:space:]]/ {print; exit}' "$tmp_locate")"
  path_count="$(awk '$0 ~ /^\// && $0 !~ /locateStudy\.sh/ && $0 !~ /[[:space:]]/ {c++} END {print c+0}' "$tmp_locate")"

  if [ "$path_count" -ne 1 ] || [ -z "$path" ]; then
    log_msg "locateStudy lookup failed for SUID=$suid (continuing)"
    printf '%s|%s|%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$suid" "lookup_failed" >> "$fail_file"
    cat "$tmp_locate" >> "$fail_file"
    printf '\n' >> "$fail_file"
    return
  fi

  if [ ! -e "$path" ]; then
    log_msg "locateStudy returned missing path for SUID=$suid path=$path (continuing)"
    printf '%s|%s|%s|%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$suid" "path_missing" "$path" >> "$fail_file"
    cat "$tmp_locate" >> "$fail_file"
    printf '\n' >> "$fail_file"
    return
  fi

  printf '%s|%s\n' "$suid" "$path" >> "$cache_file"
  printf '%s|%s\n' "$suid" "$path" >> "$run_suid_fspath_file"
}

build_run_suid_fspath_file() {
  local processed=0
  local cache_hits=0
  local cache_miss=0
  local scan_start=0
  local scan_end=0
  local scan_elapsed=0
  local suid=""

  : > "$cache_hits_file"
  : > "$cache_miss_file"

  scan_start="$(date +%s)"

  if [ ! -s "$cache_file" ]; then
    log_msg "Cache is empty; treating all missing SUIDs as cache misses"
    cp "$missing_uid_file" "$cache_miss_file"
  else
    log_msg "Scanning cache in a single pass (fast path)"
    awk -F'|' -v hits="$cache_hits_file" -v miss="$cache_miss_file" -v total="$missing_uids" -v step=100000 '
      NR==FNR { cache[$1]=$0; next }
      {
        if ($1 in cache) {
          print cache[$1] > hits
        } else {
          print $1 > miss
        }
        if (++n % step == 0) {
          if (total > 0) {
            printf("Cache scan progress: %d/%d\n", n, total) > "/dev/stderr"
          } else {
            printf("Cache scan progress: %d\n", n) > "/dev/stderr"
          }
        }
      }
    ' "$cache_file" "$missing_uid_file" 2> >(while IFS= read -r line; do log_msg "$line"; done)
  fi

  cache_hits="$(wc -l < "$cache_hits_file" | tr -d ' ')"
  cache_miss="$(wc -l < "$cache_miss_file" | tr -d ' ')"
  scan_end="$(date +%s)"
  scan_elapsed=$((scan_end - scan_start))
  log_msg "Cache scan complete: hits=$cache_hits misses=$cache_miss elapsed=${scan_elapsed}s"

  if [ "$cache_hits" -gt 0 ]; then
    cat "$cache_hits_file" >> "$run_suid_fspath_file"
  fi

  if [ "$cache_miss" -eq 0 ]; then
    return
  fi

  while IFS= read -r suid || [ -n "$suid" ]; do
    [ -n "$suid" ] || continue
    append_from_cache_or_lookup "$suid"
    processed=$((processed + 1))

    if [ "$sleep_sec" != "0" ] && [ "$sleep_sec" != "0.0" ]; then
      sleep "$sleep_sec"
    fi

    if [ $((processed % 10000)) -eq 0 ]; then
      log_msg "Progress: locateStudy processed $processed/$cache_miss"
    fi
  done < "$cache_miss_file"
}

refresh_current_symlink() {
  ln -sfn "$run_suid_fspath_file" "$current_suid_link"
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --run)
        [ "$#" -ge 2 ] || { echo "Error: --run requires a value." >&2; usage_and_exit 2; }
        run_arg="${2:-}"
        shift 2
        ;;
      --sleep)
        [ "$#" -ge 2 ] || { echo "Error: --sleep requires a value." >&2; usage_and_exit 2; }
        sleep_sec="${2:-}"
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
  if ! [[ "$sleep_sec" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    echo "Error: --sleep must be a non-negative number (seconds)." >&2
    usage_and_exit 2
  fi
}

print_summary() {
  log_msg "SOT unique SUIDs: $total_sot_uids"
  log_msg "Run suid_fspath existing SUIDs before update: $existing_run_uids"
  log_msg "Run suid_fspath appended missing SUIDs: $missing_uids"
  log_msg "Run suid_fspath file: $run_suid_fspath_file"
  log_msg "Global cache file: $cache_file"
  log_msg "locateStudy failure file: $fail_file"
  log_msg "Current suid_fspath symlink: $current_suid_link"
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

find_sot_file
validate_repository_handler
setup_paths
trap cleanup EXIT

log_msg "Starting component 3 (build-suid-fspath)"
build_missing_uid_list
log_msg "Progress: processed $existing_run_uids/$total_sot_uids missing SUIDs (resume)"
log_msg "Remaining missing SUIDs to locate: $missing_uids"
build_run_suid_fspath_file
refresh_current_symlink
print_summary
