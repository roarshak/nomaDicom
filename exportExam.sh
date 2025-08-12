#!/bin/bash
#shellcheck disable=SC2207,SC1090,SC1091
_DATE_FMT="%Y-%m-%d %H:%M:%S"
output_log="exportExam.log"
migration_database="$MigDB"
study_tbl="studies"
admin_tbl="migadmin"
ss_tbl="studies_systems"
system_tbl="systems"
# TODO: Export_Directory?
# Define Functions
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
  getstudyDicomLocation() {
    "$HOME"/component/repositoryhandler/scripts/locateStudy.sh -d "$SUID"
  }
  getstudyDate() {
    local styiuid=$1
    sql.sh "use $migration_database; SELECT DATE(styDate) FROM $study_tbl WHERE styiuid='$styiuid' AND styDate IS NOT NULL;" -N
  }
  getPbRList() {
      local location=$1
      # ls -1tr "${location}" | grep PbR
      find "${location}" -maxdepth 1 -type f -name "*PbR*" -printf "%T@ %p\n" | sort -n | cut -d' ' -f2-
  }
  getNonPbRList() {
      local location=$1
      # ls -1tr "${location}"/ | grep -v PbR
      find "${location}" -maxdepth 1 -type f ! -name '*PbR*' -printf '%T@ %p\n' | sort -n | cut -d' ' -f2-
  }
  getNonPbRList_Export_Location() {
      local location=$1
      # ls -1tr "${location}"/ | grep -v PbR
      find "${location}" -maxdepth 1 -type f ! -name '*PbR*' -printf '%T@ %p\n' | sort -n | cut -d' ' -f2-
  }
  Zero_Object_Study_Check() {
    if [[ ${#Study_NonPbR_List[@]} -eq 0 ]] && [[ ${#Study_PbR_List[@]} -gt 0 ]]; then
      if [ "$executedByUser" = "True" ]; then
        printf "%s skipping %s PbR-Only. Skipping.\n" "$(date +"$_DATE_FMT")" "$Study_Directory"
      elif [ "$executedByUser" = "False" ]; then
        printf "%s skipping %s PbR-Only. Skipping.\n" "$(date +"$_DATE_FMT")" "$Study_Directory"  | tee -a "$output_log"
      fi
      sql.sh "USE $migration_database; UPDATE $admin_tbl SET skip='y', skip_reason='pbr_only' WHERE styiuid='$SUID';"
      return 1
    elif [[ ${#Study_NonPbR_List[@]} -eq 0 ]]; then
      if [ "$executedByUser" = "True" ]; then
        printf "%s skipping %s has no objects. Skipping.\n" "$(date +"$_DATE_FMT")" "$Study_Directory"
      elif [ "$executedByUser" = "False" ]; then
        printf "%s skipping %s has no objects. Skipping.\n" "$(date +"$_DATE_FMT")" "$Study_Directory"  | tee -a "$output_log"
      fi
      sql.sh "USE $migration_database; UPDATE $admin_tbl SET skip='y', skip_reason='no_obj' WHERE styiuid='$SUID';"
      return 1
    else
      return 0
    fi
  }
  getstudyStatus() {
    sql.sh "use imagemedical; SELECT mainst FROM Dcstudy WHERE styiuid='$SUID';" -N
  }
  Update_Exported_Exam_Info() {
    sql.sh "
        USE $migration_database;
        UPDATE    $admin_tbl
        SET       export_location='$Export_Directory',
                  transferred_datetime=NOW()
        WHERE     styiuid='$SUID';"
  }
  Create_Directory() {
    local directory
    directory="$1"
    [[ ! -d "$directory" ]] && mkdir -p "$directory"
  }
  CopyObjs_Without_PbR() {
    find "$Study_Directory" -maxdepth 1 -type f ! -name 'PbR*' -exec cp {} "$Export_Directory" \;
    for file in "${Export_Directory}"/*; do
      destination_file="${file}.dcm"
      if [[ ! -e "$destination_file" ]]; then
        mv "$file" "$destination_file"
      fi
    done
  }
  CopyObjs_With_PbR() {
    for obj in "${Study_NonPbR_List[@]}"; do
      destination_file="${Export_Directory}/$(basename "${obj}").dcm"
      if [[ ! -e "$destination_file" ]]; then
        if ! ~/component/utils/bin/convert --pbr-file "${Study_PbR_List[0]}" "${obj}" "$destination_file"; then
          cp "${obj}" "$destination_file"
        fi
      fi
    done
  }
  Study_Dir_Valid_Check() {
    if [[ ! -d "$Study_Directory" ]]; then
      if [ "$executedByUser" = "True" ]; then
        printf "%s skipping %s is not a directory. Skipping.\n" "$(date +"$_DATE_FMT")" "$Study_Directory"
      elif [ "$executedByUser" = "False" ]; then
        printf "%s skipping %s is not a directory. Skipping.\n" "$(date +"$_DATE_FMT")" "$Study_Directory"  | tee -a "$output_log"
      fi
      # TODO: Change hard-coded DB name to variable.
      sql.sh "USE $migration_database; UPDATE $admin_tbl SET skip='y', skip_reason='bad_dir' WHERE styiuid='$SUID';"
      return 1
    else
      return 0
    fi
  }
  Multiple_PbR_Check() {
    # If it has mpbr, attempt to fix it first
    # if [[ ${#Study_PbR_List[@]} -gt 1 ]]; then
    #   if [ "$executedByUser" = "True" ]; then
    #     printf "%s mpbr %s attempting fix (has %i PbR files).\n" "$(date +"$_DATE_FMT")" "$SUID" "${#Study_PbR_List[@]}"
    #   elif [ "$executedByUser" = "False" ]; then
    #     printf "%s mpbr %s attempting fix (has %i PbR files).\n" "$(date +"$_DATE_FMT")" "$SUID" "${#Study_PbR_List[@]}" | tee -a "$output_log"
    #   fi
    #   ./fixDupPbR.sh "$SUID" >/dev/null
    #   Study_PbR_List=($(getPbRList "$Study_Directory"))
    # fi
    # The $Study_PbR_List is updated, so check again
    if [[ ${#Study_PbR_List[@]} -gt 1 ]]; then
      if [ "$executedByUser" = "True" ]; then
        printf "%s skipping %s fix attempt failed (has %i PbR files).\n" "$(date +"$_DATE_FMT")" "$SUID" "${#Study_PbR_List[@]}"
      elif [ "$executedByUser" = "False" ]; then
        printf "%s skipping %s fix attempt failed (has %i PbR files).\n" "$(date +"$_DATE_FMT")" "$SUID" "${#Study_PbR_List[@]}" | tee -a "$output_log"
      fi
      sql.sh "USE $migration_database; UPDATE $admin_tbl SET skip='y', skip_reason='mpbr' WHERE styiuid='$SUID';"
      return 1
    else
      return 0
    fi
  }
  Study_Status_Check() {
    study_status=$(getstudyStatus "$SUID")
    if (( study_status < 0 )); then
      if [ "$executedByUser" = "True" ]; then
        printf "%s skipping %s is not a valid status. Skipping.\n" "$(date +"$_DATE_FMT")" "$Study_Directory"
      elif [ "$executedByUser" = "False" ]; then
        printf "%s skipping %s is not a valid status. Skipping.\n" "$(date +"$_DATE_FMT")" "$Study_Directory"  | tee -a "$output_log"
      fi
      # TODO: Change hard-coded DB name to variable.
      sql.sh "USE $migration_database; UPDATE $admin_tbl SET skip='y', skip_reason='bad_status' WHERE styiuid='$SUID';"
      return 1
    else
      return 0
    fi
  }
  Set_Export_Fullpath() {
    if [[ -z "$Study_Date" ]]; then
      Export_Directory="${Export_Root_Dir}/dateless/${SUID}"
    else
      # Export_Directory="${Export_Root_Dir}/${Study_Date:0:4}/${Study_Date:4:2}/${Study_Date:6:2}/${SUID}"
      Export_Directory="${Export_Root_Dir}/${Study_Date:0:4}/${Study_Date:5:2}/${Study_Date:8:2}/${SUID}"
    fi
  }
  Export_Study() {
    if [ "$executedByUser" = "True" ]; then
      printf "%s exporting %s\n" "$(date +"$_DATE_FMT")" "$SUID"
    elif [ "$executedByUser" = "False" ]; then
      printf "%s exporting %s\n" "$(date +"$_DATE_FMT")" "$SUID" | tee -a "$output_log"
    fi

    if [[ ${#Study_PbR_List[@]} -eq 0 ]]; then # NO PBR
      Create_Directory "$Export_Directory"
      CopyObjs_Without_PbR
      Update_Exported_Exam_Info
    elif [[ ${#Study_PbR_List[@]} -ge 1 ]]; then  # HAS PBR
      Create_Directory "$Export_Directory"
      CopyObjs_With_PbR
      Update_Exported_Exam_Info
    fi
  }
  Verify_Exported_Study() {
    Study_NonPbR_List_Exported=($(getNonPbRList "$Export_Directory" | awk -F'/' '{ print $NF }'))
    Study_NonPbR_List_StudyDir=($(getNonPbRList "$Study_Directory" | awk -F'/' '{ print $NF }'))
    # Remove the .dcm extension from the elements in the Study_NonPbR_List_Exported array
    for (( i=0; i<${#Study_NonPbR_List_Exported[@]}; i++ )); do
      #shellcheck disable=SC2004
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

    # Log the missing elements to a text file if arrays do not match
      if ! "$arrays_match"; then
        if [ "$executedByUser" = "True" ]; then
          printf "%s %s failed verification.\n" "$(date +"$_DATE_FMT")" "$SUID"
        elif [ "$executedByUser" = "False" ]; then
          printf "%s %s failed verification.\n" "$(date +"$_DATE_FMT")" "$SUID" | tee -a "$output_log"
        fi
        sql.sh "USE $migration_database; UPDATE $admin_tbl SET verification='failed', skip='y', skip_reason='vfail' WHERE styiuid='$SUID';"
        missing_file="vfail_missing_objects.log"
        printf "Missing elements: %s\n" "$SUID" >> "$missing_file"
        printf "%s\n" "${missing_elements[@]}" >> "$missing_file"
      else
        sql.sh "USE $migration_database; UPDATE $admin_tbl SET verification='passed' WHERE styiuid='$SUID';"
      fi
  }
  Export_Study_To_Disk() {
    # Exit if SUID is not set
      [ -z "$SUID" ] && return 1
    # Gather study information
      Study_Directory="$(getstudyDicomLocation "$SUID")"
      Study_Date="$(getstudyDate "$SUID")"
      Study_PbR_List=($(getPbRList "$Study_Directory"))
      Study_NonPbR_List=($(getNonPbRList "$Study_Directory"))
    # Prelim Checks / Exit Conditions
      Study_Dir_Valid_Check || return 1
      Zero_Object_Study_Check || return 1
      Multiple_PbR_Check || return 1
      if [ "$executedByUser" = "True" ]; then
        Study_Status_Check || return 1
      fi
    # Derive export location
      Set_Export_Fullpath
    # Export the study
      Export_Study
    # Verify the study was exported successfully
      Verify_Exported_Study
    # UPDATE DATABASE
  }
  DisplayUsage() {
    echo "Usage: $(basename "$0") [OPTIONS]"
    echo "Options:"
    echo "  --help, -h          Display this help message and exit."
    echo "  --script            Run in non-interactive mode for automated tasks."
    echo "  --target [dir]      Specify the root directory for exports."
    echo "  --study [SUID]      Specify the Study Unique ID to process."
    echo "  -S [SUID]           Short option for specifying Study Unique ID."
    echo "  -s [SUID]           Another short option for specifying Study Unique ID."
    echo ""
    echo "Example:"
    echo "  $(basename "$0") --target /path/to/export --study 123456"
    echo ""
    echo "This script facilitates the export and verification of DICOM studies."
    echo "Ensure all required environment variables and configurations are set before running."
    echo "Refer to the script documentation or contact your system administrator for more details."
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

executedByUser=True
[ $# -eq 0 ] && DisplayUsage
while [ -n "$1" ]; do
	case $1 in
    --help)   DisplayUsage ;;
    -h)       DisplayUsage ;;
    --script) executedByUser=False ;;
    --target) Export_Root_Dir="$2"; shift ;;
    --study)  SUID="$2"; shift ;;
    -S)       SUID="$2"; shift ;;
    -s)       SUID="$2"; shift ;;
    *)        printf "Unknown option (ignored): %s" "$1"; DisplayUsage ;;
  esac
  shift
done

check_and_source_config  "universal.lib" "migration.cfg"
if [ "$executedByUser" = "True" ]; then
  # Check_Required_Variables MYSQL_BIN crm_case_number migration_database Export_Root_Dir
  Check_Required_Variables MYSQL_BIN migration_database Export_Root_Dir
fi
Export_Study_To_Disk
