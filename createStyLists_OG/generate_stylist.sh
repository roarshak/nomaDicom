#!/usr/bin/env bash
set -euo pipefail

# Usage: $0 path/to/case.cfg
# - Sources the provided cfg file for database and query configuration
# - Generates sot_dstudy (Dcstudy export) and sot_pbr (PbR counts)
# - Merges both files into a single sot_extract file, sorted by styiuid
# - All output files are placed in a timestamped run directory for organization

# ============================================================================
# VARIABLE DEFINITIONS
# ============================================================================
cfg_file="" # validate_config_file, source_config, setup_run_directory
base_dir="" # setup_run_directory
run_dir="" # setup_run_directory, setup_file_paths, display_config_summary, display_next_steps, display_summary
config_copy="" # setup_run_directory
log_file="" # setup_file_paths, setup_logging, display_summary
sot_pbr_fn="" # setup_file_paths
sot_dstudy_path="" # setup_file_paths, display_config_summary, generate_sot_dstudy, display_summary
sot_pbr_path="" # setup_file_paths, generate_sot_pbr, merge_sot_files, cleanup_temp_files
sot_extract_path="" # setup_file_paths, display_config_summary, merge_sot_files, display_summary
case_number="" # display_config_summary
work_dir="" # setup_run_directory, display_config_summary
erad_db="" # display_config_summary, generate_sot_dstudy, generate_sot_pbr
mysql_bin="" # source_config, display_config_summary, generate_sot_dstudy, generate_sot_pbr
dateColumn="" # display_config_summary
where_clause="" # display_config_summary
sot_extract_fn="" # source_config, setup_file_paths, display_config_summary, display_next_steps, display_summary
sot_dstudy_fn="" # setup_file_paths
sot_dstudy_columns="" # (sourced from config, not directly used in script)
sot_dstudy_sql="" # display_config_summary, generate_sot_dstudy
sot_pbr_sql="" # generate_sot_pbr
suid_styloc_fn="" # display_next_steps
cur_datetime="" # setup_run_directory
sot_extract_count="" # merge_sot_files, display_summary

# ============================================================================
# FUNCTION DEFINITIONS
# ============================================================================

usage_and_exit() {
  local exit_code=${1:-0}
  echo "Usage: $0 <config-file>"
  echo ""
  echo "Generate Source-of-Truth (SOT) data export and map studies to filesystem locations."
  echo ""
  echo "Arguments:"
  echo "  <config-file>    Path to configuration file (e.g., case_93843_3.cfg)"
  echo ""
  echo "The script will:"
  echo "  1. Read database query configuration from the config file"
  echo "  2. Extract Dcstudy records and PbR counts from the eRAD database"
  echo "  3. Merge and sort results by styiuid (ascending)"
  echo "  5. Place all output in a timestamped run directory"
  echo ""
  echo "Output files are retained in: <work_dir>/sot_run_<timestamp>/"
  echo "  - sot_dcstudy:<timestamp>.txt    (raw Dcstudy export for auditing)"
  echo "  - Akumin-Hub1_SOT_StudyDemographics_<timestamp>.txt (merged SOT file)"
  echo ""
  exit "$exit_code"
}

validate_config_file() {
  if [ -z "$cfg_file" ]; then
    usage_and_exit 2
  fi
  if [ ! -f "$cfg_file" ]; then
    echo "Error: Config file not found: $cfg_file" >&2
    usage_and_exit 3
  fi
}

source_config() {
  . "$cfg_file"
  : ${mysql_bin:?mysql_bin must be set in cfg}
  : ${sot_extract_fn:?sot_extract_fn must be set in cfg}
}

setup_run_directory() {
  if [ -n "${work_dir:-}" ] && [ -d "$work_dir" ] && [ -w "$work_dir" ]; then
    base_dir="$work_dir"
  else
    base_dir="$(pwd)"
  fi
  
  run_dir="$base_dir/sot_run_${cur_datetime}"
  mkdir -p "$run_dir"
  
  config_copy="$run_dir/$(basename "$cfg_file")"
  cp "$cfg_file" "$config_copy"
  echo "Configuration file copied to run directory: $config_copy"
}

setup_file_paths() {
  log_file="$run_dir/execution.log"
  sot_pbr_fn="sot_pbrcounts_$$.txt"
  sot_dstudy_path="$run_dir/$sot_dstudy_fn"
  sot_pbr_path="$run_dir/$sot_pbr_fn"
  sot_extract_path="$run_dir/$sot_extract_fn"
}

setup_logging() {
  exec > >(tee -a "$log_file")
  exec 2>&1
}

display_config_summary() {
  echo "Configuration Summary:"
  echo ""
  echo "System Configuration:"
  echo "  case_number: ${case_number:-}"
  echo "  work_dir: ${work_dir:-}"
  echo "  erad_db: ${erad_db:-}"
  echo "  mysql_bin: ${mysql_bin:-}"
  echo "  dateColumn: ${dateColumn:-}"
  echo "  where_clause: ${where_clause:-}"
  echo ""
  echo "Output Files (will be created in: $run_dir):"
  echo "  sot_dstudy: $sot_dstudy_path"
  echo "  sot_extract: $sot_extract_path"
}

confirm_proceed() {
  read -r -p "Proceed with these settings? [y/N] " confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Aborting."
    exit 1
  fi
}

generate_sot_dstudy() {
  echo "Generating sot_dstudy (pass 1)..."
  echo "$sot_dstudy_sql" | "$mysql_bin" --default-character-set=utf8 --quick -N -s -r "$erad_db" | tr '\t' '|' > "$sot_dstudy_path"
}

generate_sot_pbr() {
  echo "Generating sot_pbr (pass 2)..."
  echo "$sot_pbr_sql" | "$mysql_bin" --default-character-set=utf8 --quick -N -s -r "$erad_db" | tr '\t' '|' > "$sot_pbr_path"
}

merge_sot_files() {
  echo "Merging sot_dstudy and sot_pbr into sot_extract..."
  join -t '|' -a1 -o 1.1,1.2,2.2,1.3,1.4,1.5,1.6,1.7,1.8,1.9,1.10,1.11 "$sot_dstudy_path" "$sot_pbr_path" \
    | awk -F '|' 'BEGIN{OFS="|"} {pbr=($3==""?0:$3); adj=$2-pbr; print $1, adj, $4, $5, $6, $7, $8, $9, $10, $11, $12}' \
    > "$sot_extract_path"
  
  sot_extract_count=$(wc -l < "$sot_extract_path")
  echo "sot_extract contains $sot_extract_count records"
}

cleanup_temp_files() {
  echo "Cleaning up temporary files (sot_pbr)..."
  rm -f "$sot_pbr_path"
}

display_next_steps() {
  echo "Note: suid->styloc generation is disabled by default for this run."
  echo "If you need study filesystem locations, run the standalone generator (pass the run directory):"
  echo ""
  echo "bash \"$(dirname "$0")/generate_suid_styloc.sh\" \"$run_dir\""
  echo ""
  echo "This will produce:"
  echo "  - ${suid_styloc_fn}    (in the run directory)"
  echo "  - ${sot_extract_fn%.txt}_with_styloc.txt  (merged SOT with filesystem paths)"
  echo ""
}

display_summary() {
  echo ""
  echo "============= Summary ============="
  echo "sot_dstudy records: $(wc -l < "$sot_dstudy_path")"
  echo "sot_extract records: $sot_extract_count"
  echo ""
  echo "Run directory: $run_dir"
  echo "Log file: $log_file"
  echo ""
  echo "Retained files:"
  echo "  - $sot_dstudy_path"
  echo "  - $sot_extract_path"
  echo "==================================="
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================
cfg_file=${1:-}
validate_config_file
source_config
setup_run_directory
setup_file_paths
setup_logging

display_config_summary
confirm_proceed
generate_sot_dstudy
generate_sot_pbr
merge_sot_files
cleanup_temp_files
display_next_steps
display_summary
