#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# VARIABLE DEFINITIONS
# ============================================================================
run_dir="" # validate_run_directory, find_sot_file, find_config_file, validate_config_file, create_suid_list, generate_suid_styloc, merge_with_sot, cleanup_temp_files, display_summary
sot_extract_path="" # find_sot_file, validate_sot_file, create_suid_list, merge_with_sot, display_summary
cfg_file="" # find_config_file, validate_config_file, source_config
suid_styloc_fn="" # source_config, generate_suid_styloc, display_summary
suid_styloc_path="" # generate_suid_styloc, merge_with_sot, display_summary
tmp_suid_list="" # create_suid_list, generate_suid_styloc, cleanup_temp_files
repository_handler_script="" # validate_repository_handler, generate_suid_styloc
suid_styloc_count="" # generate_suid_styloc, display_summary
sot_extract_with_styloc_path="" # merge_with_sot, display_summary

# ============================================================================
# FUNCTION DEFINITIONS
# ============================================================================

usage_and_exit() {
  echo "Usage: $0 <run-directory>"
  echo ""
  echo "Generate suid-styloc mapping file and merge with SOT."
  echo ""
  echo "The provided run directory must:"
  echo "  - Contain a *SOT_StudyDemographics* file (created by generate_stylist.sh)"
  echo "  - Contain a *.cfg file with required configuration variables"
  echo ""
  echo "Example:"
  echo "  $0 /home/medsrv/work/case_93843/sot_run_20260201"
  echo ""
  exit 2
}

validate_run_directory() {
  if [ -z "$run_dir" ] || [ ! -d "$run_dir" ]; then
    echo "Error: missing or invalid run directory." >&2
    usage_and_exit
  fi
}

find_sot_file() {
  sot_extract_path=$(find "$run_dir" -maxdepth 1 -name "*SOT_StudyDemographics*" -type f | head -1)
}

validate_sot_file() {
  if [ -z "$sot_extract_path" ] || [ ! -f "$sot_extract_path" ]; then
    echo "Error: no *SOT_StudyDemographics* file found in: $run_dir" >&2
    exit 3
  fi
}

find_config_file() {
  cfg_file=$(find "$run_dir" -maxdepth 1 -name "*.cfg" -type f | head -1)
}

validate_config_file() {
  if [ -z "$cfg_file" ] || [ ! -f "$cfg_file" ]; then
    echo "Error: no *.cfg file found in: $run_dir" >&2
    exit 4
  fi
}

source_config() {
  . "$cfg_file"
  : ${suid_styloc_fn:?suid_styloc_fn must be set in cfg}
}

setup_paths() {
  suid_styloc_path="$run_dir/${suid_styloc_fn}"
  tmp_suid_list="$run_dir/suid_list_from_sot.txt"
  sot_extract_with_styloc_path="${sot_extract_path%.txt}_with_styloc.txt"
}

create_suid_list() {
  echo "Creating SUID list from sot_extract..."
  cut -d '|' -f1 "$sot_extract_path" > "$tmp_suid_list"
}

validate_repository_handler() {
  repository_handler_script="/home/medsrv/component/repositoryhandler/scripts/locateStudy.sh"
  if [ ! -x "$repository_handler_script" ]; then
    echo "Error: repository handler script not found or not executable: $repository_handler_script" >&2
    exit 5
  fi
}

generate_suid_styloc() {
  echo "Generating suid-styloc (sequential)..."
  rm -f "$suid_styloc_path"
  while read -r suid; do
    styloc="$("$repository_handler_script" -d "$suid")"
    printf '%s|%s\n' "$suid" "$styloc"
  done < "$tmp_suid_list" > "$suid_styloc_path"
  
  if [ ! -f "$suid_styloc_path" ]; then
    echo "Error: failed to create suid-styloc file." >&2
    exit 6
  fi
  
  suid_styloc_count=$(wc -l < "$suid_styloc_path")
  echo "suid-styloc: $suid_styloc_path ($suid_styloc_count records)"
}

merge_with_sot() {
  echo "Creating merged SOT with styloc appended as last column..."
  join -t '|' -a1 -e '' -o 1.1,1.2,1.3,1.4,1.5,1.6,1.7,1.8,1.9,1.10,1.11,2.2 \
    "$sot_extract_path" "$suid_styloc_path" > "$sot_extract_with_styloc_path"
}

cleanup_temp_files() {
  rm -f "$tmp_suid_list"
}

display_summary() {
  echo "Merged SOT written to: $sot_extract_with_styloc_path"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================
run_dir=${1:-}
validate_run_directory
find_sot_file
validate_sot_file
find_config_file
validate_config_file
source_config
setup_paths
create_suid_list
validate_repository_handler
generate_suid_styloc
merge_with_sot
cleanup_temp_files
display_summary

exit 0
