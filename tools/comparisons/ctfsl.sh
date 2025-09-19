#!/bin/bash
#shellcheck disable=SC2004

# TODO: Adjust DirectoryIsValid so it respects executedByUser output.

_DATE_FMT="%Y-%m-%d %H:%M:%S"

# Define Functions
  DirectoryIsValid() {
    if [ -d "$1" ]; then
      return 0
    else
      return 1
    fi
  }
  getNonPbRList() {
      local location=$1
      # ls -1tr "${location}"/ | grep -v PbR
      find "${location}" -maxdepth 1 -type f ! -name '*PbR*' -printf '%T@ %p\n' | sort -n | cut -d' ' -f2-
  }
  user_check () {
    # Exit if not running as medsrv user
    if [[ $USER != "medsrv" ]]; then 
      echo "This script must be run as medsrv!" 
      exit 1
    fi
  }
  Check_Required_Variables() {
    # Take a list of variables as arguments and check that they are all set
    # If any are not set, exit with an error
    local var
    for var in "$@"; do
        eval "value=\$$var"
        if [ -z "$value" ]; then
            printf "ERROR: %s is not set\n" "$var" >&2
            exit 1
        fi
    done
  }
  check_and_source_config() {
    while [ -n "$1" ]; do
      if [[ -f "$1" ]]; then
        . "$1"
      else
        echo "ERROR: Could not find $1. Exiting."
        exit 1
      fi
      shift
    done
  }
  
# GETOPS
executedByUser=true
[ $# -eq 0 ] && DisplayUsage
while [ -n "$1" ]; do
	case $1 in
    --help)   DisplayUsage ;;
    -h)       DisplayUsage ;;
    --script) executedByUser=false ;;
    --study)  SUID="$2"; shift ;;
    --loc1)  location_one="$2"; shift ;;
    --loc2)  location_two="$2"; shift ;;
    *)        printf "Unknown option (ignored): %s" "$1"; DisplayUsage ;;
  esac
  shift
done

# check_and_source_config "universal.lib"
user_check
Check_Required_Variables location_one location_two SUID
if $executedByUser; then
  if ! DirectoryIsValid "$location_one"; then
    printf "%s %s %s is not a valid directory.\n" "$(date +"$_DATE_FMT")" "$SUID" "$location_one"
    exit 1
  fi
  if ! DirectoryIsValid "$location_two"; then 
    printf "%s %s %s is not a valid directory.\n" "$(date +"$_DATE_FMT")" "$SUID" "$location_two"
    exit 1
  fi
elif ! $executedByUser; then
  if ! DirectoryIsValid "$location_one"; then
    printf "%s %s %s is not a valid directory.\n" "$(date +"$_DATE_FMT")" "$SUID" "$location_one" | tee -a ctfsl.log
    exit 1
  fi
  if ! DirectoryIsValid "$location_two"; then 
    printf "%s %s %s is not a valid directory.\n" "$(date +"$_DATE_FMT")" "$SUID" "$location_two" | tee -a ctfsl.log
    exit 1
  fi
else
  exit 2
fi

# MAIN
#shellcheck disable=SC2207
Study_NonPbR_List_StudyDir=($(getNonPbRList "$location_one" | awk -F'/' '{ print $NF }'))
#shellcheck disable=SC2207
Study_NonPbR_List_Exported=($(getNonPbRList "$location_two" | awk -F'/' '{ print $NF }'))

# Remove the .dcm extension from the elements in the Study_NonPbR_List_Exported array
  for (( i=0; i<${#Study_NonPbR_List_Exported[@]}; i++ )); do
    Study_NonPbR_List_Exported[$i]="${Study_NonPbR_List_Exported[$i]%.dcm}"
  done

# Initialize the arrays_match variable and the missing_elements array
  arrays_match=true
  missing_elements=()

# Compare each element in Study_NonPbR_List_StudyDir with all elements in Study_NonPbR_List_Exported
  for (( i=0; i<${#Study_NonPbR_List_StudyDir[@]}; i++ )); do
    found=false
    for (( j=0; j<${#Study_NonPbR_List_Exported[@]}; j++ )); do
      if [[ "${Study_NonPbR_List_StudyDir[$i]}" == "${Study_NonPbR_List_Exported[$j]}" ]]; then
        found=true
        break
      fi
    done
    
    if ! "$found"; then
      arrays_match=false
      missing_elements+=("StyDir ${Study_NonPbR_List_StudyDir[$i]}  ExportDir ${Study_NonPbR_List_Exported[$j]}")
    fi
  done

# When called directly by the user
  if $executedByUser && $arrays_match; then
    printf "%s %s passed verification.\n" "$(date +"$_DATE_FMT")" "$SUID"
  elif $executedByUser && ! $arrays_match; then
    printf "%s %s failed verification.\n" "$(date +"$_DATE_FMT")" "$SUID"
    printf "Missing elements: %s\n" "$SUID"
    printf "%s\n" "${missing_elements[@]}"
# When called by another script
  elif ! $executedByUser && $arrays_match; then
    printf "%s %s passed verification.\n" "$(date +"$_DATE_FMT")" "$SUID" >/dev/null
  elif ! $executedByUser && ! $arrays_match; then
    # printf "%s %s failed verification.\n" "$(date +"$_DATE_FMT")" "$SUID"
    printf "Missing elements: %s\n" "$SUID" | tee -a ctfsl.log
    printf "%s\n" "${missing_elements[@]}" | tee -a ctfsl.log
  fi

