#!/usr/bin/env bash
set -euo pipefail

# Usage: ./generate_sot_and_import.sh path/to/case.cfg
# - Sources the provided cfg file for database and query configuration
# - Generates sot_dstudy (Dcstudy export) and sot_pbr (PbR counts)
# - Merges both files into a single sot_extract file, sorted by date descending
# - Generates suid_styloc by mapping study UIDs to filesystem locations
# - All output files are placed in a timestamped run directory for organization

usage_and_exit() {
  local exit_code=${1:-0}
  cat <<EOF
Usage: $0 <config-file>

Generate Source-of-Truth (SOT) data export and map studies to filesystem locations.

Arguments:
  <config-file>    Path to configuration file (e.g., case_93843_3.cfg)

The script will:
  1. Read database query configuration from the config file
  2. Extract Dcstudy records and PbR counts from the eRAD database
  3. Merge and sort results by date (descending)
  4. Map study UIDs to filesystem locations
  5. Place all output in a timestamped run directory

Output files are retained in: <work_dir>/sot_run_<timestamp>/
  - sot_dcstudy:<timestamp>.txt    (raw Dcstudy export for auditing)
  - Akumin-Hub1_SOT_StudyDemographics_<timestamp>.txt (merged SOT file)
  - suid-styloc_<timestamp>.txt    (study UID to filesystem location mapping)

EOF
  exit "$exit_code"
}

cfg_file=${1:-}
if [ -z "$cfg_file" ]; then
  usage_and_exit 2
fi

if [ ! -f "$cfg_file" ]; then
  echo "Error: Config file not found: $cfg_file" >&2
  usage_and_exit 3
fi

. "$cfg_file"

# Ensure required vars exist
: ${mysql_bin:?mysql_bin must be set in cfg}
: ${sot_extract_fn:?sot_extract_fn must be set in cfg}
: ${styloc_parallelism:?styloc_parallelism must be set in cfg}

# Choose run directory: prefer work_dir if set and writable, else current directory
if [ -n "${work_dir:-}" ] && [ -d "$work_dir" ] && [ -w "$work_dir" ]; then
  base_dir="$work_dir"
else
  base_dir="$(pwd)"
fi

run_dir="$base_dir/sot_run_${cur_datetime}"
mkdir -p "$run_dir"

# Copy configuration file to run directory for reproducibility
config_copy="$run_dir/$(basename "$cfg_file")"
cp "$cfg_file" "$config_copy"
echo "Configuration file copied to run directory: $config_copy"

# Log file for this run
log_file="$run_dir/execution.log"

# Temporary file names (created and deleted within this run)
sot_pbr_fn="sot_pbrcounts_$$.txt"
suid_list_fn="suid_list_$$.txt"

# Paths for this run (keep original filenames from cfg but place in run_dir)
sot_dstudy_path="$run_dir/$sot_dstudy_fn"
sot_pbr_path="$run_dir/$sot_pbr_fn"
sot_extract_path="$run_dir/$sot_extract_fn"
suid_list_path="$run_dir/$suid_list_fn"
suid_styloc_path="$run_dir/$suid_styloc_fn"

# Redirect all output to log file and stdout
exec > >(tee -a "$log_file")
exec 2>&1

echo "Configuration Summary:"
echo ""
echo "System Configuration:"
echo "  case_number: ${case_number:-}"
echo "  work_dir: ${work_dir:-}"
echo "  erad_db: ${erad_db:-}"
echo "  mysql_bin: ${mysql_bin:-}"
echo "  dateColumn: ${dateColumn:-}"
echo "  where_clause: ${where_clause:-}"
echo "  styloc_parallelism: ${styloc_parallelism:-}"
echo ""
echo "Output Files (will be created in: $run_dir):"
echo "  sot_dstudy: $sot_dstudy_path"
echo "  sot_extract: $sot_extract_path"
echo "  suid_styloc: $suid_styloc_path"

read -r -p "Proceed with these settings? [y/N] " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
  echo "Aborting."
  exit 1
fi

echo "Generating sot_dstudy (pass 1)..."
echo "$sot_dstudy_sql" | "$mysql_bin" --quick -N -s -r "$erad_db" | tr '\t' '|' > "$sot_dstudy_path"

echo "Generating sot_pbr (pass 2)..."
echo "$sot_pbr_sql" | "$mysql_bin" --quick -N -s -r "$erad_db" | tr '\t' '|' > "$sot_pbr_path"

echo "Merging sot_dstudy and sot_pbr into sot_extract..."
join -t '|' -a1 -e 0 -o 1.1,1.2,2.2,1.3,1.4,1.5,1.6,1.7,1.8,1.9,1.10,1.11 "$sot_dstudy_path" "$sot_pbr_path" \
  | awk -F '|' 'BEGIN{OFS="|"} {
    pbr=($3==""?0:$3); adj=$2-pbr;
    pid=($5==""?"NULL":$5)
    pbdate=($6==""?"NULL":$6)
    accno=($7==""?"NULL":$7)
    modality=($8==""?"NULL":$8)
    stydescr=($10==""?"NULL":$10)
    print $1, adj, $4, pid, pbdate, accno, modality, $9, stydescr, $11, $12
  }' \
  > "$sot_extract_path"

echo "Sorting sot_extract by ${dateColumn} (column 8) descending..."
tmp_sort="${sot_extract_path}.sorted.$$"
LC_ALL=C sort -t '|' -k8,8r "$sot_extract_path" > "$tmp_sort"
mv "$tmp_sort" "$sot_extract_path"

# Validate sot_extract has content
if [ ! -s "$sot_extract_path" ]; then
  echo "Error: sot_extract file is empty. Check database query and where_clause." >&2
  exit 6
fi

sot_extract_count=$(wc -l < "$sot_extract_path")
echo "sot_extract contains $sot_extract_count records"

echo "Cleaning up temporary files (sot_pbr)..."
rm -f "$sot_pbr_path"

echo "\nTo generate filesystem locations (suid-styloc), run the following command in a shell:\n"
cat <<'CMD'
cut -d '|' -f1 "<SOT_EXTRACT>" | xargs -P <PARALLEL> -I {} bash -c '
  suid="{}"
  styloc="$('/home/medsrv/component/repositoryhandler/scripts/locateStudy.sh' -d "$suid")"
  echo -e "${suid}|${styloc}"
' > "<SUID_STYLOC>"
CMD

echo "Replace <SOT_EXTRACT> with: $sot_extract_path"
echo "Replace <SUID_STYLOC> with: $suid_styloc_path"
echo "Replace <PARALLEL> with: $styloc_parallelism (set in config)"

echo "If your environment lacks GNU xargs, run sequentially:
while read -r suid; do
  /home/medsrv/component/repositoryhandler/scripts/locateStudy.sh -d "$suid" | awk -v s="$suid" '{print s"\t"$0}'
done < "$sot_extract_path" | cut -f1 > "$suid_styloc_path"
"

echo "Note: the script did NOT run styloc generation automatically; run the above command when ready."

if [ ! -f "$suid_styloc_path" ]; then
  echo "Error: Expected suid-styloc file not found: $suid_styloc_path" >&2
  exit 5
fi

suid_styloc_count=$(wc -l < "$suid_styloc_path")
echo "suid-styloc file contains $suid_styloc_count records"

echo "Cleaning up temporary files (suid_list)..."
rm -f "$suid_list_path"

echo ""
echo "============= Summary ============="
echo "sot_dstudy records: $(wc -l < "$sot_dstudy_path")"
echo "sot_extract records: $sot_extract_count"
echo "suid_styloc records: $suid_styloc_count"
echo ""
echo "Run directory: $run_dir"
echo "Log file: $log_file"
echo ""
echo "Retained files:"
echo "  - $sot_dstudy_path"
echo "  - $sot_extract_path"
echo "  - $suid_styloc_path"
echo "==================================="
