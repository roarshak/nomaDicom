#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# VARIABLE DEFINITIONS
# ============================================================================
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
component_id="COMP1"
cfg_file=""
run_dir_file=""

work_dir=""
run_id=""
run_dir=""
cfg_copy=""
log_file=""

# Populated from cfg (do not edit here)
mysql_bin=""
erad_db=""
sot_dstudy_sql=""
sot_pbr_sql=""
sot_header=""
sot_dstudy_fn=""
sot_extract_fn=""
locate_study_bin=""
suid_fspath_cache_fn=""
suid_fspath_fn=""
current_sot_link=""
current_suid_fspath_link=""

dstudy_path=""
pbr_path=""
dstudy_count=""
pbr_count=""
resolved_cfg=""

# ============================================================================
# FUNCTION DEFINITIONS
# ============================================================================

usage_and_exit() {
  local exit_code="${1:-0}"
  cat <<EOF
Usage:
  $0 --cfg <config-file> [--run-dir-file <path>]

Description:
  Component 1 of the SOT pipeline.
  Creates a new run directory and generates:
    1) dstudy list
    2) pbr list

Behavior:
  - Always creates a new run directory: run_YYYYmmdd_HHMMSS
  - Copies the cfg file into the run directory
  - Appends component-tagged log entries to: <run_dir>/pipeline.log

Options:
  --cfg <config-file>       Required. Path to cfg file.
  --run-dir-file <path>     Optional. Writes the created run directory path.
  -h, --help                Show this help.
EOF
  exit "$exit_code"
}

log_msg() {
  local message="$1"
  printf '%s|%s|%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$component_id" "$message" | tee -a "$log_file"
}

to_abs_path() {
  local target="$1"
  if [ -d "$target" ]; then
    (cd "$target" && pwd)
  else
    printf '%s/%s\n' "$(cd "$(dirname "$target")" && pwd)" "$(basename "$target")"
  fi
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

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --cfg)
        cfg_file="${2:-}"
        shift 2
        ;;
      --run-dir-file)
        run_dir_file="${2:-}"
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

validate_inputs() {
  [ -n "$cfg_file" ] || { echo "Error: --cfg is required." >&2; usage_and_exit 2; }
  [ -f "$cfg_file" ] || { echo "Error: cfg file not found: $cfg_file" >&2; exit 3; }
  cfg_file="$(to_abs_path "$cfg_file")"
}

source_config() {
  # shellcheck disable=SC1090
  . "$cfg_file"
  : "${work_dir:?work_dir must be set in cfg}"
  : "${mysql_bin:?mysql_bin must be set in cfg}"
  : "${erad_db:?erad_db must be set in cfg}"
  : "${sot_dstudy_sql:?sot_dstudy_sql must be set in cfg}"
  : "${sot_pbr_sql:?sot_pbr_sql must be set in cfg}"
  : "${sot_dstudy_fn:?sot_dstudy_fn must be set in cfg}"
  : "${sot_extract_fn:?sot_extract_fn must be set in cfg}"
  : "${locate_study_bin:?locate_study_bin must be set in cfg}"
  : "${suid_fspath_cache_fn:?suid_fspath_cache_fn must be set in cfg}"
  : "${suid_fspath_fn:?suid_fspath_fn must be set in cfg}"
  : "${current_sot_link:?current_sot_link must be set in cfg}"
  : "${current_suid_fspath_link:?current_suid_fspath_link must be set in cfg}"

  work_dir="$(resolve_path "$script_dir" "$work_dir")"
}

create_run_directory() {
  run_id="$(date '+%Y%m%d_%H%M%S')"
  run_dir="$work_dir/run_${run_id}"
  while [ -d "$run_dir" ]; do
    sleep 1
    run_id="$(date '+%Y%m%d_%H%M%S')"
    run_dir="$work_dir/run_${run_id}"
  done

  mkdir -p "$run_dir"
  cfg_copy="$run_dir/$(basename "$cfg_file")"
  cp "$cfg_file" "$cfg_copy"

  log_file="$run_dir/pipeline.log"
  : > "$log_file"
}

emit_cfg_var() {
  local name="$1"
  local value="$2"
  printf '%s=%q\n' "$name" "$value"
}

write_resolved_config() {
  resolved_cfg="$run_dir/run_cfg_resolved.sh"
  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf '%s\n' '# Auto-generated. Do not edit.'
    emit_cfg_var "work_dir" "$work_dir"
    emit_cfg_var "cur_datetime" "${cur_datetime:-}"
    emit_cfg_var "mysql_bin" "$mysql_bin"
    emit_cfg_var "erad_db" "$erad_db"
    emit_cfg_var "sot_dstudy_sql" "$sot_dstudy_sql"
    emit_cfg_var "sot_pbr_sql" "$sot_pbr_sql"
    emit_cfg_var "sot_header" "$sot_header"
    emit_cfg_var "sot_dstudy_fn" "$sot_dstudy_fn"
    emit_cfg_var "sot_extract_fn" "$sot_extract_fn"
    emit_cfg_var "locate_study_bin" "$locate_study_bin"
    emit_cfg_var "suid_fspath_cache_fn" "$suid_fspath_cache_fn"
    emit_cfg_var "suid_fspath_fn" "$suid_fspath_fn"
    emit_cfg_var "current_sot_link" "$current_sot_link"
    emit_cfg_var "current_suid_fspath_link" "$current_suid_fspath_link"
    emit_cfg_var "fspath_strip_prefix" "$fspath_strip_prefix"
  } > "$resolved_cfg"
}

setup_output_paths() {
  dstudy_path="$run_dir/$sot_dstudy_fn"
  pbr_path="$run_dir/sot_pbrcounts_${run_id}.txt"
}

generate_dstudy_list() {
  log_msg "Generating dstudy list: $dstudy_path"
  echo "$sot_dstudy_sql" | "$mysql_bin" --default-character-set=utf8 --quick -N -s -r "$erad_db" | tr '\t' '|' > "$dstudy_path"
  LC_ALL=C sort -t '|' -k1,1 "$dstudy_path" -o "$dstudy_path"
  dstudy_count="$(wc -l < "$dstudy_path" | tr -d ' ')"
  log_msg "dstudy list complete (records=$dstudy_count)"
}

generate_pbr_list() {
  log_msg "Generating pbr list: $pbr_path"
  echo "$sot_pbr_sql" | "$mysql_bin" --default-character-set=utf8 --quick -N -s -r "$erad_db" | tr '\t' '|' > "$pbr_path"
  LC_ALL=C sort -t '|' -k1,1 "$pbr_path" -o "$pbr_path"
  pbr_count="$(wc -l < "$pbr_path" | tr -d ' ')"
  log_msg "pbr list complete (records=$pbr_count)"
}

write_run_dir_output() {
  if [ -n "$run_dir_file" ]; then
    printf '%s\n' "$run_dir" > "$run_dir_file"
  fi
}

print_summary() {
  log_msg "Run directory created: $run_dir"
  log_msg "cfg copy: $cfg_copy"
  log_msg "pipeline log: $log_file"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================
parse_args "$@"
validate_inputs
source_config
create_run_directory
write_resolved_config
setup_output_paths
log_msg "Starting component 1 (build-lists)"
generate_dstudy_list
generate_pbr_list
write_run_dir_output
print_summary
