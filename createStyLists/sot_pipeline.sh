#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# VARIABLE DEFINITIONS
# ============================================================================
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

do_build_lists=0
do_build_sot=0
do_build_suid_fspath=0
do_merge=0

cfg_file=""
run_arg=""
sleep_sec="0"

run_dir_file=""
resolved_run_dir=""
sot_work_dir=""

component1_script="$script_dir/component1_build_lists.sh"
component2_script="$script_dir/component2_build_sot.sh"
component3_script="$script_dir/component3_build_suid_fspath.sh"
component4_script="$script_dir/component4_merge_sot_fspath.sh"

# ============================================================================
# FUNCTION DEFINITIONS
# ============================================================================

usage_and_exit() {
  local exit_code="${1:-0}"
  cat <<EOF
Usage:
  $0 [switches]

Named switches:
  --build-lists                 Run component 1 (requires --cfg)
  --build-sot                   Run component 2 (requires --run unless --build-lists also used)
  --build-suid-fspath           Run component 3 (requires --run unless --build-lists also used)
  --merge                       Run component 4 (requires --run unless --build-lists also used)
  --all                         Run components 1 -> 2 -> 3 -> 4 in order

Arguments:
  --cfg <config-file>           Required for --build-lists / --all (optional to help resolve --run)
  --run <run-name-or-path>      Required for component 2/3/4 if component 1 is not run in same command
  --sleep <seconds>             Optional for component 3 locateStudy throttle (default: 0)
  -h, --help                    Show this help

Examples:
  $0 --build-lists --cfg /path/to/case.cfg
  $0 --build-sot --run run_20260216_101010
  $0 --build-suid-fspath --run /work/createStyLists/run_20260216_101010 --sleep 0.02
  $0 --merge --run run_20260216_101010
  $0 --all --cfg /path/to/case.cfg --sleep 0.02
EOF
  exit "$exit_code"
}

validate_component_scripts() {
  [ -f "$component1_script" ] || { echo "Error: script not found: $component1_script" >&2; exit 3; }
  [ -f "$component2_script" ] || { echo "Error: script not found: $component2_script" >&2; exit 3; }
  [ -f "$component3_script" ] || { echo "Error: script not found: $component3_script" >&2; exit 3; }
  [ -f "$component4_script" ] || { echo "Error: script not found: $component4_script" >&2; exit 3; }
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --build-lists)
        do_build_lists=1
        shift
        ;;
      --build-sot)
        do_build_sot=1
        shift
        ;;
      --build-suid-fspath)
        do_build_suid_fspath=1
        shift
        ;;
      --merge)
        do_merge=1
        shift
        ;;
      --all)
        do_build_lists=1
        do_build_sot=1
        do_build_suid_fspath=1
        do_merge=1
        shift
        ;;
      --cfg)
        [ "$#" -ge 2 ] || { echo "Error: --cfg requires a value." >&2; usage_and_exit 2; }
        cfg_file="${2:-}"
        shift 2
        ;;
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
  if [ "$do_build_lists" -eq 0 ] && [ "$do_build_sot" -eq 0 ] && [ "$do_build_suid_fspath" -eq 0 ] && [ "$do_merge" -eq 0 ]; then
    echo "Error: no component switch provided." >&2
    usage_and_exit 2
  fi

  if [ "$do_build_lists" -eq 1 ] && [ -z "$cfg_file" ]; then
    echo "Error: --cfg is required when --build-lists is used." >&2
    exit 4
  fi
  if [ -n "$cfg_file" ] && [ ! -f "$cfg_file" ]; then
    echo "Error: cfg file not found: $cfg_file" >&2
    exit 4
  fi

  if [ "$do_build_lists" -eq 0 ] && { [ "$do_build_sot" -eq 1 ] || [ "$do_build_suid_fspath" -eq 1 ] || [ "$do_merge" -eq 1 ]; } && [ -z "$run_arg" ]; then
    echo "Error: --run is required for component 2/3/4 when --build-lists is not used." >&2
    exit 5
  fi

  if ! [[ "$sleep_sec" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    echo "Error: --sleep must be a non-negative number (seconds)." >&2
    exit 5
  fi
}

load_work_dir_from_cfg() {
  [ -n "$cfg_file" ] || return 0
  # shellcheck disable=SC1090
  . "$cfg_file"
  : "${work_dir:?work_dir must be set in cfg}"
  sot_work_dir="$(resolve_path "$script_dir" "$work_dir")"
}

run_component1() {
  run_dir_file="$(mktemp)"
  bash "$component1_script" --cfg "$cfg_file" --run-dir-file "$run_dir_file"
  resolved_run_dir="$(cat "$run_dir_file")"
  rm -f "$run_dir_file"

  [ -n "$resolved_run_dir" ] || { echo "Error: component 1 did not return run directory." >&2; exit 6; }
}

resolve_run_for_remaining_components() {
  if [ "$do_build_lists" -eq 1 ]; then
    run_arg="$resolved_run_dir"
  else
    if [ -n "$run_arg" ] && [ -d "$run_arg" ]; then
      run_arg="$(cd "$run_arg" && pwd)"
      return
    fi

    if [ -n "$run_arg" ] && [ -z "$sot_work_dir" ]; then
      load_work_dir_from_cfg
    fi

    if [ -n "$sot_work_dir" ] && [ -d "$sot_work_dir/$run_arg" ]; then
      run_arg="$(cd "$sot_work_dir/$run_arg" && pwd)"
    elif [ -d "$script_dir/$run_arg" ]; then
      run_arg="$(cd "$script_dir/$run_arg" && pwd)"
    fi
  fi
}

run_selected_components() {
  if [ "$do_build_lists" -eq 1 ]; then
    run_component1
  fi

  resolve_run_for_remaining_components

  if [ "$do_build_sot" -eq 1 ]; then
    if [ -n "$sot_work_dir" ]; then
      SOT_WORK_DIR="$sot_work_dir" bash "$component2_script" --run "$run_arg"
    else
      bash "$component2_script" --run "$run_arg"
    fi
  fi

  if [ "$do_build_suid_fspath" -eq 1 ]; then
    if [ -n "$sot_work_dir" ]; then
      SOT_WORK_DIR="$sot_work_dir" bash "$component3_script" --run "$run_arg" --sleep "$sleep_sec"
    else
      bash "$component3_script" --run "$run_arg" --sleep "$sleep_sec"
    fi
  fi

  if [ "$do_merge" -eq 1 ]; then
    if [ -n "$sot_work_dir" ]; then
      SOT_WORK_DIR="$sot_work_dir" bash "$component4_script" --run "$run_arg"
    else
      bash "$component4_script" --run "$run_arg"
    fi
  fi
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================
parse_args "$@"
validate_args
validate_component_scripts
run_selected_components
