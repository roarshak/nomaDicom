#!/bin/bash
#shellcheck disable=SC2207,SC1091,SC1090
# TODO:
#   - Add a 'force' option that bypasses minesweeper and other checks

# Set defaults in case cfg file is missing
    _INTERSTITIAL_SLEEP=5
    _SCRIPT_NAME="$(basename "$0")"
    _SCRIPT_CFG="${_SCRIPT_NAME%.*}.cfg"
    _SCRIPT_LOG="${_SCRIPT_NAME%.*}.log"
    _DATE_FMT="%Y%m%d-%H%M%S"
    _MYSQL_BIN="/home/medsrv/component/mysql/bin/mysql"
    _SECURITY_OPT="TCP" # Or TLS
    _TLS_OPT="+tls $SSL_SITE_KEY $SSL_SITE_CERT -ic"
    crm_case_number="MigrationsTeam"
    _VERBOSE_OPTS=""
    _DEBUG_OPTS=""
    _LIST="${_SCRIPT_NAME}_input-list.txt"
    _current_index=0
    # Initialize flags with False
    _QUIET=$False
    _DRY_RUN=$False
    TargetVerified=$False
    Force=$False
    # Define "Pythonic" boolean constants
    True=0
    False=1
    # Set rap for clean-up actions
    trap '[[ -f "${_SCRIPT_NAME}_input-list.txt" ]] && rm -f "${_SCRIPT_NAME}_input-list.txt"' EXIT

# Define Functions
  DisplayUsage() {
      printf "Usage: %s [OPTION]... [SUID]...\n" "$_SCRIPT_NAME"
      printf "Forward an exam using runjavacmd.\n"
      printf "\n"
      printf "Options:\n"
      printf "  -h, --help\t\t\tDisplay this help and exit\n"
      printf "  -S, -s, --study\t\tSpecify the SUID of the study to forward\n"
      printf "  --list, -l\t\t\tSpecify a file containing a list of SUIDs\n"
      printf "  --target VALUE\t\tSpecify the target device to forward to\n"
      printf "  --target-verified\t\tMark the target as verified\n"
      printf "  --whatif\t\t\tEnable dry-run mode (no changes made)\n"
      printf "  --quiet\t\t\tSuppress output\n"
      exit 0
  }
  Message() {
      local quiet_mode=$False
      local display_only=$False
      local log_level="INFO"
      local log_file="$_SCRIPT_LOG"
      local log_message
      local log_options=()
      local timestamp
      timestamp=$(date +"$_DATE_FMT")

      # Parse arguments
      for arg in "$@"; do
          case "$arg" in
              --quiet) quiet_mode=$True ;;
              --display-only) display_only=$True; shift ;;
              --log-level) log_level="$2"; shift ;;
              --log-file) log_file="$2"; shift ;;
              *) log_options+=("$arg") ;;
          esac
      done

      # Join the remaining arguments as the message
      log_message="${log_options[*]}" 
      [[ $_DRY_RUN -eq $True ]] && log_message="DRY-RUN $log_message"
      log_message="${timestamp} [${log_level}] ${_Customer_Name:-UNKNOWN-CUSTOMER} ${log_message}"

      # Handle display-only, quiet, and default modes
      if [[ $display_only -eq $True ]]; then
          printf "%s\n" "$log_message"
      elif [[ $quiet_mode -eq $True ]]; then
          printf "%s\n" "$log_message" >> "$log_file"
      else
          printf "%s\n" "$log_message" | tee -a "$log_file"
      fi
  }
  verifyTargetDevice() {
      if [[ $TargetVerified -eq $False ]]; then
          if [[ -n $(sql.sh "SELECT id FROM Target WHERE id='$_TARGET'" -N) ]]; then
              TargetVerified=$True
          else
              return 1
          fi
      fi
  }
  getstudyStatus() {
    local _suid="$1"
    sql.sh "use imagemedical; SELECT mainst FROM Dcstudy WHERE styiuid='$_suid';" -N
  }
  getstudyDicomLocation() {
    local _suid="$1"
    "$HOME"/component/repositoryhandler/scripts/locateStudy.sh -d "$_suid"
  }
  getPbRList() {
      local _location=$1
      # ls -1tr "${_location}" | grep PbR
      find "${_location}" -maxdepth 1 -type f -name "*PbR*" -printf "%T@ %p\n" | sort -n | cut -d' ' -f2-
  }
  getNonPbRList() {
      local _location=$1
      # ls -1tr "${_location}"/ | grep -v PbR
      find "${_location}" -maxdepth 1 -type f ! -name '*PbR*' -printf '%T@ %p\n' | sort -n | cut -d' ' -f2-
  }
  Multiple_PbR_Check() {
      local _suid="$1"
      # Check for multiple PbR files and indicate failure if there are more than one
      if [[ ${#Study_PbR_List[@]} -gt 1 ]]; then
          Message --log-level "WARN" "skipping $_suid (has ${#Study_PbR_List[@]} PbR files)."
          # sql.sh "USE $migration_database; UPDATE LocalExams SET skip='y', skip_reason='mpbr' WHERE styiuid='$_suid';"
          return 1
      fi

      # If only one or no PbR files exist, continue
      return 0
  }
  Zero_Object_Study_Check() {
      if [[ ${#Study_NonPbR_List[@]} -eq 0 ]] && [[ ${#Study_PbR_List[@]} -gt 0 ]]; then
          Message --log-level "INFO" "skipping $Study_Directory PbR-Only. Skipping."
          # sql.sh "USE $migration_database; UPDATE LocalExams SET skip='y', skip_reason='pbr_only' WHERE styiuid='$SUID';"
          return 1
      elif [[ ${#Study_NonPbR_List[@]} -eq 0 ]]; then
          Message --log-level "INFO" "skipping $Study_Directory has no objects. Skipping."
          # sql.sh "USE $migration_database; UPDATE LocalExams SET skip='y', skip_reason='no_obj' WHERE styiuid='$SUID';"
          return 1
      else
          return 0
      fi
  }
  Study_Status_Check() {
      local _suid="$1"
      study_status=$(getstudyStatus "$_suid")
      if (( study_status < 0 )); then
          Message --log-level "WARN" "skipping $Study_Directory is not a valid status. Skipping."
          # TODO: Change hard-coded DB name to variable.
          # sql.sh "USE $migration_database; UPDATE LocalExams SET skip='y', skip_reason='bad_status' WHERE styiuid='$_suid';"
          return 1
      else
          return 0
      fi
  }
  PreExecutionChecks() {
    _TOTAL_SUIDS=$(wc -l < "$_LIST")
    
    if ! verifyTargetDevice; then
        Message --log-level "ERROR" "Target device not specified or does not exist."
        exit 1
    fi
    
    if [[ ! -f "$_LIST" ]]; then
        Message --log-level "ERROR" "Specified list file '$_LIST' does not exist."
        exit 1
    fi

    if [[ $_TOTAL_SUIDS -eq 0 ]]; then
        Message --log-level "ERROR" "The specified list file '$_LIST' is empty. Exiting."
        exit 1
    fi
  }
  Check_Log_For_SUID() {
      local _suid="$1"

      # Check if _suid exists in the log file
      if grep -q "$_suid" "$_SCRIPT_LOG"; then
        #   Message --display-only --log-level "INFO" "SUID $_suid already found in log file. Skipping."
          return 1 # Indicate that the _suid should be skipped
      fi

      return 0 # Indicate that the _suid is not in the log file and should be processed
  }
  Minesweeper() {
      local _suid="$1"
      Study_Directory="$(getstudyDicomLocation "$_suid")"
      Study_PbR_List=($(getPbRList "$Study_Directory"))
      Study_NonPbR_List=($(getNonPbRList "$Study_Directory"))

        if ! Check_Log_For_SUID "$_suid"; then
            Message --display-only --log-level "INFO" "SUID $_suid already found in log file. Skipping."
            return 1 # Indicate that the SUID should be skipped
            # continue # Skip to the next SUID if already found in log
        fi
      
        if ! Multiple_PbR_Check "$_suid"; then
            Message --log-level "WARN" "Minesweeper: Multiple PbR check failed for $_suid."
            return 1
        fi

        if ! Zero_Object_Study_Check; then
            Message --log-level "WARN" "Minesweeper: Zero object check failed for $_suid."
            return 1
        fi

        if ! Study_Status_Check "$_suid"; then
            Message --log-level "WARN" "Minesweeper: Study status check failed for $_suid."
            return 1
        fi

      Message --display-only --log-level "INFO" "Minesweeper: All checks passed for $_suid."
      return 0
  }
  Migrate_Suid() {
      local _suid="$1"
      _date="$(date "+$_DATE_FMT")"
      
      if [[ $_DRY_RUN -eq $True ]]; then
          _date="${_date} DRY_RUN"
      fi

      if [[ $_SECURITY_OPT == "TLS" ]]; then
          Message --log-level "INFO" "TLS controlled by device table configuration when using runjavacmd. Proceeding."
      fi

      if [[ $TargetVerified -eq $True ]]; then
          if [[ $_DRY_RUN -eq $False ]]; then
              Message --log-level "INFO" "Executing $_current_index of $_TOTAL_SUIDS: runjavacmd -c \"0 cases.Forward -s $_suid -H $_TARGET -u $crm_case_number\""
              /home/medsrv/component/taskd/runjavacmd -c "0 cases.Forward -s $_suid -H $_TARGET -u $crm_case_number"
          else
              Message --log-level "INFO" "Dry-run enabled. Command not executed: runjavacmd -c \"0 cases.Forward -s $_suid -H $_TARGET -u $crm_case_number\""
          fi
      else
          Message --log-level "ERROR" "Target device $_TARGET is not verified. Skipping migration for $_suid."
          return 1
      fi
  }
  Check_Required_Variables() {
      # Take a list of variables as arguments and check that they are all set
      # If any are not set, log an error and exit
      local var
      for var in "$@"; do
          eval "value=\$$var"
          if [ -z "$value" ]; then
              Message --log-level "ERROR" "Required variable '$var' is not set. Exiting."
              exit 1
          fi
      done
  }
  process_list() {
    # local _current_index=0

    Message --log-level "INFO" "Starting to process list of $_TOTAL_SUIDS SUIDs from file: $_LIST"

    while IFS= read -r suid || [[ -n "$suid" ]]; do
        source_file_if_checksum_has_changed_new "${_SCRIPT_CFG:?}" true
        [[ -z "$suid" ]] && continue # Skip empty lines
        ((_current_index++))

        if [[ $Force -eq $False ]] && ! Minesweeper "$suid"; then
            continue
        fi

        ./checkLoad.sh

        # Message --log-level "INFO" "Processing SUID $_current_index of $_TOTAL_SUIDS: $suid"
        Migrate_Suid "$suid"
        sleep $_INTERSTITIAL_SLEEP
    done < "$_LIST"

    Message --log-level "INFO" "Finished processing list of SUIDs from file: $_LIST"
  }
  source_file_if_checksum_has_changed_new() {
      calculate_checksum() {
          md5sum "$1" | awk '{print $1}'
      }

      local file_path="$1"
      local new_checksum
      local ask_confirmation="$2"  # New argument to control user confirmation
      local checksum_var="checksum_${file_path//\//_}"  # Create a safe variable name by replacing '/' with '_'
      checksum_var="${checksum_var//./_}"  # New addition to replace '.' with '_'
      local current_checksum
      eval current_checksum="\$${checksum_var}"  # Indirect variable reference
      new_checksum=$(calculate_checksum "${file_path}")

      if [ -z "$current_checksum" ]; then
          . "$file_path"
          eval "$checksum_var=\"$new_checksum\""  # Set the variable globally
          return 0
      elif [ "$new_checksum" != "$current_checksum" ]; then
          Message --log-file "MigAdmin.log" "Configuration file modification detected. File=$1"
          if [[ "${ask_confirmation:=true}" == "true" ]]; then
              printf "Do you want to reload the file? ([y]/n) "
              read -r response </dev/tty
              if [[ "$response" =~ ^[Nn] ]]; then
                  Message --log-file "MigAdmin.log" "User chose not to reload the file [$file_path]."
                  return 1
              fi
          fi
          . "$file_path"
          eval "$checksum_var=\"$new_checksum\""  # Update the global variable
          Message --log-file "MigAdmin.log" "File reloaded [$file_path]."
          return 0
      else
          return 1
      fi
  }

# [ $# -eq 0 ] && DisplayUsage

# Load cfg file in case some script options (like _TARGET, etc) are set there
source_file_if_checksum_has_changed_new "${_SCRIPT_CFG:?}" false

while [ -n "$1" ]; do
    case $1 in
        --help|-h) DisplayUsage ;;
        --whatif) _DRY_RUN=$True ;;
        --target) _TARGET="$2"; shift ;;
        --target-verified) TargetVerified=$True ;;
        --force|-F) Force=$True ;;
        --study|-S|-s) SUID="$2"; shift ;;
        --list|-l|-L) _suid_list="$2"; shift ;;
        --case) crm_case_number="$2"; shift ;;
        --quiet) _QUIET=$True ;;
        *) printf "Unknown option (ignored): %s\n" "$1"; DisplayUsage ;;
    esac
    shift
done

Check_Required_Variables _TARGET

if [[ -n "$_suid_list" ]]; then
    _LIST=$_suid_list
elif [[ -n "$SUID" ]]; then
    echo "$SUID" > "$_LIST"
else
    Message --log-level "ERROR" "Either --study or --list must be specified."
    exit 1
fi

PreExecutionChecks
process_list
