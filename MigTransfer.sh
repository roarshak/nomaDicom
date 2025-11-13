#!/bin/bash
#shellcheck disable=SC1090,SC1091,SC2155

[ "$USER" != "medsrv" ] && echo "This script must be run as medsrv! Exiting..." && exit 1
# =========================
# Configuration and Globals
# =========================
declare -a script_vars  # Array to hold environment variable names
declare -a pid_array=() # Array to hold the PIDs of execMovescu.sh
declare -a thread_slots   # Array to track thread slot usage (0=free, pid=in use)
_DEFAULT_CONFIG_FILE=".default.cfg"
_MIGRATION_CONFIG_FILE="migration.cfg"
_Concurrent_Threads=3
. /home/medsrv/var/dicom/pb-scp.cfg # Provides local server AE_TITLE

# =========================
# Utility Functions
# =========================
  manage_env() {
    # Example usage:
    # manage_env --add VAR1 VAR2
    # manage_env --export
    # manage_env --display
    # manage_env --verify
    # manage_env --export-config "path_to_config_file"
      local command="$1"  # Get the command option (--add, --export, etc.)
      shift               # Shift command line arguments to left

      case "$command" in
          --add)
              # Add variables to the environment list
              for var_name in "$@"; do
                  script_vars+=("$var_name")
                  # echo "Added $var_name to environment."
              done
              ;;
          --export)
              # Export all variables in the environment list
              for var_name in "${script_vars[@]}"; do
                  export "$var_name"
                  echo "Exported $var_name."
              done
              ;;
          --display)
              # Display the current environment contents
              echo "Current environment settings:"
              for var_name in "${script_vars[@]}"; do
                  echo "$var_name='${!var_name}'"
              done
              ;;
          --verify)
              # Verify that all required environmental variables are set and not empty
              local all_set=true
              for var_name in "${script_vars[@]}"; do
                  if [[ -z "${!var_name}" ]]; then
                      echo "Error: $var_name is not set or is empty."
                      all_set=false
                  fi
              done
              if $all_set; then
                  echo "All required variables are set and have non-empty values."
              else
                  echo "Some required variables are missing or empty."
                  return 1  # Return non-zero status to indicate failure
              fi
              ;;
          --export-config)
              # Dynamically export variables from a sourced configuration file
              local config_file="$1"
              local var_name
              local old_ifs="$IFS"  # Preserve the original IFS
              IFS=$'\n'  # Change IFS to handle new line as field separator
              # Iterate over lines that look like variable assignments
              # shellcheck disable=SC2013
              for line in $(grep '^[[:alnum:]_]*=.*' "$config_file"); do
                  var_name=$(echo "$line" | cut -d'=' -f1)
                  manage_env --add "$var_name"  # Add to script_vars array for tracking
              done
              IFS="$old_ifs"  # Restore the original IFS
              # manage_env --export
              ;;
          *)
              echo "Invalid option. Available options: --add, --export, --display, --verify, --export-config"
              return 2  # Return non-zero status to indicate invalid usage
              ;;
      esac
  }
  Message() {
      local quiet_mode=0
      local display_only=0
      local log_level="INFO"
      local log_file="$_LOG_MIGRATION"  # Updated to use the current log file
      local log_message
      local log_options=()
      local arg
      local timestamp=$(date +"$_DATE_FMT")

      # Parse arguments
      for arg in "$@"; do
          case "$arg" in
              -q|--quiet) quiet_mode=1 ;;
              -d|--display-only) display_only=1; shift ;;
              -l|--log-level) log_level="$2"; shift ;;
              -f|--log-file) log_file="$2"; shift ;;
              *) log_options+=("$arg") ;;
          esac
      done

      log_message="${log_options[*]}" # Join the remaining arguments as the message
      [[ "${_DRY_RUN:="n"}" == "y" ]] && log_message="DRY-RUN $log_message"
      log_message="${timestamp} [${log_level}] ${_Customer_Name:-UNKNOWN-CUSTOMER} ${log_message}"

      # Handle display-only, quiet, and default modes
      if   [[ $display_only -eq 1 ]]; then
          printf "%s\n" "$log_message"
      elif [[ $quiet_mode -eq 1 ]]; then
          printf "%s\n" "$log_message" >> "$log_file"
      else
          printf "%s\n" "$log_message" | tee -a "$log_file"
      fi
  }
  cleanup() {
      Message --display-only "Performing cleanup operations..."

      # Grace period for any remaining execMovescu.sh processes
      local grace_period=30  # Time in seconds to wait for processes to finish
      local check_interval=5  # Time in seconds between process checks
      local pid_found=false

      # Find any running execMovescu.sh processes
      for pid in "${pid_array[@]}"; do
          if kill -0 "$pid" 2>/dev/null; then
              pid_found=true
              Message --display-only "Waiting for execMovescu.sh process $pid to complete..."

              # Give the process some time to finish
              local elapsed_time=0
              while kill -0 "$pid" 2>/dev/null && [[ $elapsed_time -lt $grace_period ]]; do
                  sleep $check_interval
                  elapsed_time=$((elapsed_time + check_interval))
              done

              # If the process is still running after the grace period, kill it
              if kill -0 "$pid" 2>/dev/null; then
                  Message --display-only "Killing lingering execMovescu.sh process $pid..."
                  kill -9 "$pid"
              else
                  Message --display-only "execMovescu.sh process $pid completed gracefully."
              fi
          fi
      done

      # Proceed with other cleanup operations after dealing with lingering processes
      local temp_pattern="*.{tmp,temp}"
      find "${_WDIR}" -type f -name "${temp_pattern}" -exec rm -f {} + -exec echo "Removed temporary file: {}" \;

      if [[ "$pid_found" == false ]]; then
          Message --display-only "No lingering execMovescu.sh processes found."
      fi

      Message --display-only "Cleanup completed."
  }
  manage_queue() {
    # Wait for a process to finish if the queue has 3 running processes
    while [ ${#pid_array[@]} -ge $_Concurrent_Threads ]; do
      for i in "${!pid_array[@]}"; do
        # Check if the PID is still running and belongs to execMovescu.sh
        if ! kill -0 "${pid_array[i]}" 2>/dev/null; then
          # Find and clear the thread slot for this PID
          for slot in "${!thread_slots[@]}"; do
            if [[ "${thread_slots[slot]}" == "${pid_array[i]}" ]]; then
              unset 'thread_slots[slot]'
              break
            fi
          done
          unset 'pid_array[i]'
        else
          # Check if the process associated with this PID is execMovescu.sh
          cmd=$(ps -p "${pid_array[i]}" -o args= 2>/dev/null)
          if ! [[ "$cmd" =~ execMovescu.sh ]]; then
            # Find and clear the thread slot for this PID
            for slot in "${!thread_slots[@]}"; do
              if [[ "${thread_slots[slot]}" == "${pid_array[i]}" ]]; then
                unset 'thread_slots[slot]'
                break
              fi
            done
            unset 'pid_array[i]'
          fi
        fi
      done
      # Compact the array (remove any empty slots)
      pid_array=("${pid_array[@]}")

      # Sleep for a short while before checking again
      sleep 1
    done
  }
  CreateDirectories() {
      #shellcheck disable=SC2124
      local dirs="$@"
      for dir in $dirs; do
          if [ ! -d "$dir" ]; then
              mkdir -p "$dir" || {
                  Message --display-only "Failed to create directory: %s\n" "$dir" >&2
                  return 1
              }
          fi
      done
  }
  interrupt_check() {
    # Check if the interrupt flag is set
    if [ "${interrupted:-0}" -eq 1 ]; then
      Message --log-file "MigAdmin.log" "Interrupted, exiting loop."
      return 1
    fi
  }
  checkTime() {
    if [[ ! -f "$_WDIR/checkTime.sh" ]]; then
      Message --display-only "ERROR: checkTime.sh is not present. Exiting."
      cleanup
      exit 1
    else
      "$_WDIR/checkTime.sh"
    fi
  }
  checkLoad() {
    if [[ ! -f "$_WDIR/checkLoad.sh" ]]; then
      Message --display-only "ERROR: checkLoad.sh is not present. Exiting."
      cleanup
      exit 1
    else
      "$_WDIR/checkLoad.sh"
    fi
  }
  source_file_if_checksum_has_changed_new() {
      calculate_checksum() {
          md5sum "$1" | awk '{print $1}'
      }

      local file_path="$1"
      local ask_confirmation="$2"  # New argument to control user confirmation
      local checksum_var="checksum_${file_path//\//_}"  # Create a safe variable name by replacing '/' with '_'
      checksum_var="${checksum_var//./_}"  # New addition to replace '.' with '_'
      local current_checksum
      eval current_checksum="\$${checksum_var}"  # Indirect variable reference
      local new_checksum=$(calculate_checksum "${file_path}")

      if [ -z "$current_checksum" ]; then
          . "$file_path"
          eval "$checksum_var=\"$new_checksum\""  # Set the variable globally
          return 0
      elif [ "$new_checksum" != "$current_checksum" ]; then
          Message --log-file "MigAdmin.log" "Configuration file modification detected. File=$1"
          if [[ "${ask_confirmation:=true}" == "true" ]]; then
            printf "Do you want to reload the file? ([y]/n) "
            read -r -t 300 response </dev/tty
            if [[ -z "$response" || "$response" =~ ^[Yy] ]]; then
              # Default to "Y" if no response or user enters "y"
              :
            elif [[ "$response" =~ ^[Nn] ]]; then
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
  Usage() {
    {
      printf "Usage: %s [OPTION]... [METHOD]... [SUID]...\n" "$(basename "$0")"
      printf "\n"
      printf "  -h, --help\t\tDisplay this help and exit\n"
      printf "  -L, --list\tSpecify the file containing the list of SUIDs to transfer\n"
      printf "  -if, --whatif\t\tDry run, do not actually transfer\n"
      printf "  -v, --verbose\t\tVerbose output\n"
      printf "  -d, --debug\t\tDebug output\n"
      printf "  --script\t\tDo not log results to a file\n"
      printf "  --no-resume\t\tDo not resume from last checkpoint (start fresh)\n"
      printf "  --fresh-start\t\tAlias for --no-resume\n"
    } >&2 # Redirects all output of this block to stderr
    cleanup
    exit 0
  }
  #shellcheck disable=SC2034,SC2046
  initialize() {    
    # Load configuration files
    local config_files=("$_DEFAULT_CONFIG_FILE" "$_MIGRATION_CONFIG_FILE")
    for config_file in "${config_files[@]}"; do
        if [ ! -f "$config_file" ]; then
            Message --log-file "MigAdmin.log" --log-level "ERROR" "$config_file not found. Exiting."
            cleanup
            exit 1
        fi
        . "$config_file"
        manage_env --export-config "$config_file"
    done

    case "${_METHOD:="move"}" in
      move)
        local _file="execMovescu.sh"
        if ! check_file_executable "$_file"; then
          exit 1
        fi
        ;;
      export)
        local _file="exportExam.sh"
        if ! check_file_executable "$_file"; then
          exit 1
        fi
        ;;
    esac
    
    _Customer_Name=$(echo "$_Customer_Name" | tr '[:lower:]' '[:upper:]')
    manage_env --add _Customer_Name

    # TODO: Add variable for $_SECURITY_OPT so we can leverage TLS/2762 connections
    local targetSQL="SELECT proximity, label, primaryip, aet, port, iseradpacs, epMajorVersion, protocol FROM systems WHERE role='target';"
    local sourceSQL="SELECT proximity, label, primaryip, aet, port, iseradpacs, epMajorVersion, protocol FROM systems WHERE role='source';"
    read -r Target_Proximity Target_Label Target_IP Target_AET Target_Port Target_isErad Target_Version Target_Protocol <<< $("$MYSQL_BIN" -BN -u medsrv --database="${MigDB:?}" -e "$targetSQL")
    manage_env --add Target_Proximity Target_Label Target_IP Target_AET Target_Port Target_isErad Target_Version Target_Protocol
    read -r Source_Proximity Source_Label Source_IP Source_AET Source_Port Source_isErad Source_Version Source_Protocol <<< $("$MYSQL_BIN" -BN -u medsrv --database="${MigDB:?}" -e "$sourceSQL")
    manage_env --add Source_Proximity Source_Label Source_IP Source_AET Source_Port Source_isErad Source_Version Source_Protocol

    manage_env --export # export all variables so they are accessible to any child processes.
    # Set the trap
    trap 'interrupted=1; cleanup; exit 130' SIGINT
  }
  getOptions() {
    [ $# -eq 0 ] && Usage
    while [ -n "$1" ]; do
      case $1 in
        --help|-h) Usage ;;
        --verbose|-v) _VERBOSE_OPTS="--verbose" ;;
        --debug|-d) _DEBUG_OPTS="--debug" ;;
        --list|-L)
          if [ -n "$2" ] && [[ "$2" != -* ]]; then
            _INPUT_FILE="$2"
            shift
          else
            Message --display-only --log-level "ERROR" "--list option requires a file argument." >&2
            cleanup
            exit 1
          fi ;;
        --whatif|-if) _DRY_RUN="y" ;;
        --env) manage_env --display ; exit 0 ;;
        --no-resume|--fresh-start)
          resume="false"
          ;;
        *)
          Message --display-only --log-level "ERROR" "Unknown option (ignored): $1"
          Usage ;;
      esac
      shift
    done
  }
  check_file_executable() {
      local filename="$1"
      
      # Check if the file exists
      if [ ! -e "$filename" ]; then
          echo "File does not exist: $filename"
          return 1
      fi
      
      # Check if the file has execute permission
      if [ ! -x "$filename" ]; then
          echo "File exists but does not have execute permissions: $filename"
          return 2
      fi
      
      echo "File exists and has execute permissions: $filename"
      return 0
  }
  update_db_transfer_dt() {
    local transferred_datetime="$(date +"%Y-%m-%d %H:%M:%S")"
    local migration_database="$MigDB"
    local SUID="$1"
    sql.sh "
        USE $migration_database;
        UPDATE    migadmin
        SET       transferred_datetime='$transferred_datetime', exam_requested='y'
        WHERE     styiuid='$SUID';"
  }
  resume_processing() {
      local log_file="$1"
      local input_file="$2"

      # Extract the SUID from the last line of the log file (assumed to be the final field)
      local last_line
      last_line=$(tail -n 1 "$log_file")
      local suid
      # suid=$(echo "$last_line" | awk '{print $3}')
      suid=$(echo "$last_line" | grep -oP '0020,000d=\K\S+')

      # Find the line number in the input file where the SUID occurs (assumes it begins the line)
      local line_num
      line_num=$(grep -n "^$suid" "$input_file" | cut -d: -f1 | head -n 1)

      if [[ -z "$line_num" ]]; then
          # echo "SUID '$suid' not found in $input_file; processing from beginning."
          cat "$input_file"
      else
          # echo "Resuming processing from line $line_num (SUID: $suid) in $input_file."
          tail -n +"$line_num" "$input_file"
      fi
  }
  get_next_thread_slot() {
    for ((i=0; i<_Concurrent_Threads; i++)); do
      if [[ -z "${thread_slots[i]}" ]]; then
        echo "$i"
        return
      fi
    done
    echo "0"  # fallback if all are filled (should not happen)
  }
  threaded_move() {
    local thread_num="$1"

    ./execMovescu.sh "${movescu_opts[@]}" 2>/dev/null &

    local pid="$!"
    if ! kill -0 "$pid" 2>/dev/null; then
      echo "[!] Failed to start execMovescu.sh"
      return 1
    fi

    pid_array+=("$pid")
    thread_slots[thread_num]="$pid"

    update_db_transfer_dt "$SUID"
  }
  parse_suboperations() {
    local logfile="$1"
    local remaining=0
    local completed=0
    local final_remaining
    local final_completed
    
    # Read the logfile line by line
    while IFS= read -r line; do
      # Check for the line containing 'Remaining Suboperations'
      if [[ $line == *"Remaining Suboperations"* ]]; then
        # Extract the number of remaining suboperations
        final_remaining=$(echo "$line" | grep -oP '(?<=Remaining Suboperations       : )\d+')
      fi
      # Check for the line containing 'Completed Suboperations'
      if [[ $line == *"Completed Suboperations"* ]]; then
        # Extract the number of completed suboperations
        final_completed=$(echo "$line" | grep -oP '(?<=Completed Suboperations       : )\d+')
      fi
      # Check for the line indicating a success status message
      if [[ $line == *"0x0000: Success"* ]]; then
        # When success status is found, break out of the loop
        break
      fi
    done < "$logfile"
    
    # Calculate the total expected suboperations
    local total=$((final_remaining + final_completed))
    echo "$total" # Output only the numeric value
  }
  wait_for_images() {
    local expected_count="$1"
    local suid="$2"
    local received_count=0
    local previous_count=-1
    local percentage=0
    local sleep_duration=5
    local sleep_count=0
    local sleep_count_threshold=3
    local cmhmove_flag="false"
    # local threshold=$(( expected_count * 50 / 100 )) # Calculate 50% of expected images
    local threshold=$(( expected_count * 95 / 100 )) # Calculate 95% of expected images
    # local threshold=$expected_count
    # 10.240.14.161 = Precision WL
    count_unique_scp_stored() {
      # migration_log="$_LOG_MIGRATION"
      migration_log="moveExam.log"
      info_log="/home/medsrv/var/log/info.log"
      styiuid="$1"

      # Extract the latest timestamp for the given STYIUID from migration.log in a single pass
      latest_timestamp=$(awk -v styiuid="$styiuid" '$0 ~ styiuid {timestamp=$1} END{print timestamp}' "$migration_log")

      # Check if latest_timestamp is not empty and has a valid format
      if [[ -z "$latest_timestamp" ]] || ! [[ $latest_timestamp =~ ^[0-9]{8}-[0-9]{6}$ ]]; then
        # echo "Error: Invalid or missing timestamp for STYIUID $styiuid in $migration_log"
        echo "0"
        return 1 # Exit the function with an error status
      fi

      # Preprocess the date for comparison, converting to epoch for easier comparison
      epoch_latest=$(date -d "${latest_timestamp:0:4}-${latest_timestamp:4:2}-${latest_timestamp:6:2} ${latest_timestamp:9:2}:${latest_timestamp:11:2}:${latest_timestamp:13:2}" +%s)

      # Use awk to process info.log in a single pass, comparing dates and counting unique "SCP Stored" after the latest timestamp
      count=$(awk -v epoch_latest="$epoch_latest" -v styiuid="$styiuid" '
        $0 ~ styiuid && $0 ~ "SCP Stored" {
          # Assuming log_date is in format "Mon DD HH:MM:SS", which needs to be converted to epoch for comparison
          log_date=sprintf("%s %s %s %s", $1, $2, $3, substr($4,1,8));
          gsub(/Jan/, "01", log_date); gsub(/Feb/, "02", log_date); # Replace month abbreviations with numbers as needed
          # More replacements for months as needed...
          if ((mktime(log_date) -ge epoch_latest)) {
            print $8
          }
        }
      ' "$info_log" | sort -u | wc -l)

      # Output the count
      [[ -z "$count" ]] || [[ "$count" -eq 0 ]] && echo 0 || echo "$count"
    }

    # _ownerhub=$(ssh 10.240.14.161 "sql.sh \"SELECT OWNERHUB FROM Dcstudy WHERE STYIUID='$suid'\" -N")
    # Loop until the received count is at least 95% of the expected count
    while [ "$received_count" -lt "$threshold" ]; do
      if [[ $sleep_count -gt $sleep_count_threshold ]]; then
        echo "Received $received_count / $expected_count images ($percentage%). cmhmove=$cmhmove_flag. Proceeding with the next operation (${sleep_count_threshold}x retry timeoute)."
        break
      fi
      # Query the database for the current count of received images
      if [ "$cmhmove_flag" = "false" ]; then
          received_count=$(sql.sh "select numofobj from Dcstudy where styiuid='$suid'" -N)
      else
          received_count=$(ssh -n 10.240.14.161 "sql.sh \"select numofimg from Dcstudy where styiuid='$suid'\" -N")
      fi
      # set -x
      if [[ $sleep_count -ge 3 ]]; then
        # shellcheck disable=SC2086
        received_count2=$(count_unique_scp_stored $suid)
        if [[ $received_count2 -gt $received_count ]]; then
          received_count=$received_count2
          # set +x
        fi
        # set +x
      fi
      # ownerdevice of "precision" equates to 10.240.14.33 (Hub1/Portals server)
      # ownerdevice of "precisionpriors" equates to 10.240.14.116 (Priors/JIT server)
      # if [ $_ownerhub = "precision" ]; then
      #   received_count=$(ssh -n 10.240.14.33 "sql.sh \"select numofimg from Dcstudy where styiuid='$suid'\" -N")
      # elif [ $_ownerhub = "precisionpriors" ]; then
      #   received_count=$(ssh -n 10.240.14.116 "sql.sh \"select numofimg from Dcstudy where styiuid='$suid'\" -N")
      # fi
      # Set to 0 if the value is empty
      received_count=${received_count:-0}
      
      # Calculate the percentage of received images
      percentage=$(( received_count * 100 / expected_count ))
      
      echo "Received $received_count / $expected_count images ($percentage%) for $suid. cmhmove=$cmhmove_flag. Waiting for more images..."
      
      # Check if the count has not changed
      if [[ $received_count -eq $previous_count ]]; then
        # Double the sleep_duration but do not exceed 60 seconds
        sleep_duration=$(( sleep_duration * 2 ))
        (( sleep_duration > 60 )) && sleep_duration=60
      # elif [[ $received_count -lt $previous_count ]]; then
      elif [[ "$cmhmove_flag" = "false" && $received_count -lt $previous_count ]]; then
        # multi-hub correction
        cmhmove="$(grep "$suid" /home/medsrv/var/log/info.log | grep "INFO STUDY cmhmove")"
        if [ -n "$cmhmove" ]; then
            cmhmove_flag="true"
        else
            cmhmove_flag="false"
        fi
        received_count=$(ssh -n 10.240.14.161 "sql.sh \"select numofimg from Dcstudy where styiuid='$suid'\" -N")
        echo "Received $received_count / $expected_count images ($percentage%) for $suid. cmhmove triggered. Waiting for more images..."
        # echo "Received $received_count / $expected_count images ($percentage%). Study being removed...continuing..."
        # break
      else
        # Reset sleep_duration if the count has changed
        sleep_duration=5
        ## sleep_count=$((sleep_count - 1))
        sleep_count=0
      fi
      
      # Store the current count for comparison in the next loop iteration
      previous_count="$received_count"
      
      # Wait for the specified duration before checking again
      sleep "$sleep_duration"

      # Check if an interrupt signal was received.
      interrupt_check || return 1
      sleep_count=$(( sleep_count + 1 ))
    done

    # echo "Received at least 95% of images. Proceeding with the next operation."
    echo "Received $received_count / $expected_count images ($percentage%). cmhmove=$cmhmove_flag. Proceeding with the next operation."
  }
  serial_move() {
    _log_file="movescu_$$.log"
    # The movescu output redirected to the file is not a
    # live reflection of the transfer. It often times, as
    # is the case with InteleRad, will return all move receipts
    # at once.
    # We have it in order to parse the output for the total
    # number of suboperations (images).
    ./execMovescu.sh "${movescu_opts[@]}" &> "$_log_file"
    # ./moveExam.sh -S "$SUID" \
    #   --target-ae "eRAD1" \
    #   --source-ae "$Source_AET" \
    #   --source-ip "$Source_IP" \
    #   --source-port "$Source_Port" "$_DEBUG_OPTS" "$_VERBOSE_OPTS" \
    #   &> "$_log_file"
    _rc_movescu=$?
    if [[ $_rc_movescu -ne 0 ]]; then
      printf "%s movescu %s FROM:%s TO:%s failed with exit code %s\n" "$_date" "${SUID}" "$Source_Label" "$Target_Label" "$_rc_movescu" | tee -a "$_SCRIPT_LOG"
      # exit 1
      echo "Sleeping for 10 minutes"
      sleep 600
    fi
    
    update_db_transfer_dt "$SUID"
    _expected_img_count="$(parse_suboperations "$_log_file")"
    wait_for_images "$_expected_img_count" "$SUID"
    sleep 0.5

    rm -f "$_log_file"
  }
  StudyExists() {
      local styiuid="$1"
      local database="$2"

      if [[ -z "$styiuid" || -z "$database" ]]; then
          return 1  # Return error if either argument is empty
      fi

      local exists
      exists=$(/home/medsrv/component/mysql/bin/mysql -BN -D "$database" \
          -e "SELECT EXISTS(SELECT 1 FROM Dcstudy WHERE styiuid = '$styiuid');")

      if [[ "$exists" -eq 1 ]]; then
          # Message -d "Study with ID $styiuid exists in $database."
          return 0
      else
          # Message -d "Study with ID $styiuid does not exist in $database."
          return 1
      fi
  }
  already_present() {
    local suid="$1"
    local intelerad_cnt
    local localdb_cnt
    local worklist_cnt
    local threshold
    pre_check_img_cnt() {
      # # Get the received count from the remote server
      # received_count=$(ssh -n 10.240.14.161 "sql.sh \"select numofimg from Dcstudy where styiuid='$suid'\" -N")
      # # Check if received_count is greater than or equal to expected_count
      # if [[ "$received_count" -ge "$expected_count" ]]; then
      #     # Continue with the process
      #     echo "Received count is sufficient; proceeding..."
      #     # Place any additional commands here to continue the process
      # fi
      local sys_id="$1"
      local suid="$2"
      local result
      result="$(sql.sh "SELECT numofobj FROM case_69206.studies_systems WHERE styiuid='$suid' AND system_id='$sys_id'" -N)"
      echo "${result:-0}"
    }

    # Get the counts
    intelerad_cnt="$(pre_check_img_cnt "1" "$suid")"
    localdb_cnt="$(pre_check_img_cnt "2" "$suid")"
    worklist_cnt="$(ssh -n 10.240.14.161 "sql.sh \"select numofobj from Dcstudy where styiuid='$suid'\" -N")"
    threshold=$(( intelerad_cnt * 95 / 100 )) # Calculate 95% of expected images

    # Return false if both localdb_cnt and worklist_cnt are 0
    if [[ "${localdb_cnt:-0}" -eq 0 && "${worklist_cnt:-0}" -eq 0 ]]; then
      echo "DEBUG: Both LocalMigDB and WorkList counts are 0."
      return 1  # false
    fi

    # Check if either localdb_cnt or worklist_cnt is greater than or equal to threshold
    if [[ "${localdb_cnt:-0}" -ge "$threshold" || "${worklist_cnt:-0}" -ge "$threshold" ]]; then
      echo "DEBUG: InteleRad:$intelerad_cnt, Threshold:$threshold, LocalMigDB:$localdb_cnt, WorkList:$worklist_cnt"
      return 0  # true
    else
      echo "DEBUG: InteleRad:$intelerad_cnt, Threshold:$threshold, LocalMigDB:$localdb_cnt, WorkList:$worklist_cnt"
      return 1  # false
    fi
  }
  skip_if_processed() {
    local suid
    suid="$1"
    # Only skip if skipProcessed is true
    if [ "${skipProcessed:-false}" = "true" ]; then
      if [ -f "$_LOG_MIGRATION" ] && grep -qF "$suid" "$_LOG_MIGRATION"; then
        return 0
      else
        return 1
      fi
    else
      return 1
    fi
  }
  getStudyData() {
    local styiuid=$1
    local column_name="$2"
    sql.sh "use $MigDB; SELECT $column_name FROM studies WHERE styiuid='$styiuid';" -N
  }
#
# =========================
# Migration Functions
# =========================
  main() {
      export -f Message
      initialize
      getOptions "$@"

      hidden_temp_file=".resume_input.$$"
      if [ "${resume:-false}" = "true" ] && [ -f "$_LOG_MIGRATION" ]; then
          echo "Resuming processing using checkpoint input stored in $hidden_temp_file"
          sleep 3
          resume_processing "$_LOG_MIGRATION" "$_INPUT_FILE" > "$hidden_temp_file"
          input_source="$hidden_temp_file"
      else
          input_source="$_INPUT_FILE"
      fi

      while IFS= read -r SUID; do
        # Skip this SUID if:
        # 1. The migration log file exists ($_LOG_MIGRATION)
        # 2. The skipProcessed flag is true (defaults to false if not set)
        # 3. The SUID is found in the migration log file (indicating it was already processed)
          if skip_if_processed "$SUID"; then
              printf "%s skipping %s, already processed\n" "$(date "+$_DATE_FMT")" "$SUID"
              continue
          fi
          if StudyExists "$SUID" "imagemedical"; then
              printf "%s skipping %s, already exists in the database\n" "$(date "+$_DATE_FMT")" "$SUID"
              continue
          fi
          process_and_transfer_suid "$SUID" || break  # Break on error
          sleep "${interstitial_sleep:=3}"
      done < "$input_source" || {
          echo "Error during processing or reading of SUID list"
          cleanup
          exit 1
      }

      # Remove the temporary file if it was created
      if [ "$input_source" != "$_INPUT_FILE" ]; then
          rm -f "$input_source"
      fi

      trap - SIGINT  # Reset trap to default behavior
  }
  process_and_transfer_suid() {
      local SUID="$1"
      # local _date="$(date "+$_DATE_FMT")"

      # Early exit if interrupted or already processed
      interrupt_check || return 1
      #shellcheck disable=SC2154
      source_file_if_checksum_has_changed_new "${_MIGRATION_CONFIG_FILE:?}" true

      checkTime
      checkLoad
      interrupt_check || return 1

      # Get the study date for use in printf/echo
      local study_date
      study_date=$(getStudyData "$SUID" "DATE(styDate)")
      if [[ -z "$study_date" ]]; then
          study_date="UNKNOWN"
      fi
      # Get the modality for use in printf/echo
      local modality
      modality=$(getStudyData "$SUID" "modality")
      if [[ -z "$modality" ]]; then
          modality="??"
      fi

      # Determine transfer method
      case "${_METHOD:="move"}" in
          move)
              # INFO: If iseradpacs is "n", then use PIC method.
              # INFO: PIC version creates a movescu_$$.log file
              Assemble_Cmove_Opts
              manage_queue
              local thread_num
              thread_num=$(get_next_thread_slot)
              # local thread_label="thread$((thread_num + 1))"
              local thread_label="thread$(printf '%02d' $((thread_num + 1)))"

              # Message "movescu" "[${thread_label}] ${movescu_opts[*]}"
              #shellcheck disable=SC2088
              # Message "[${thread_label}]" "~/component/dicom/bin/movescu ${movescu_opts[*]}"
              Message "[${thread_label}]" "~/component/dicom/bin/movescu ${movescu_opts[*]} ($study_date $modality exam)"

              # If this is a dry run, skip execution of execMovescu.sh but return success
              if [[ "${_DRY_RUN:="n"}" == "y" ]]; then
                  # Message "movescu" "DRY-RUN: Skipping actual execution of execMovescu.sh"
                  return 0
              fi

              # if [[ "${Source_isErad:="n"}" == "n" ]]; then
                # serial_move
              # else
                threaded_move "$thread_num"
              # fi
            ;;
          export)
              # ./exportExam.sh --target "${Export_Root_Dir:?}" --study "${SUID:?}"
              # TODO: Does exportExamsh update the transferred_datetime in the database? YES
              # ./exportExam.sh --target "${Export_Root_Dir:?}" --study "${SUID:?}" | tee -a migration.log 2>&1 
              ./exportExam.sh --target "${Export_Root_Dir:?}" --study "${SUID:?}" 2>&1 | tee -a migration.log | sed --unbuffered ''
              ;;
          runjavacmd)
              echo "Under construction, exiting."
              ;;
          *)
              echo "Unknown transfer method: $_METHOD" >&2
              cleanup
              exit 1
              ;;
      esac
  }
  Assemble_Cmove_Opts() {
    # Initialize movescu_opts with common options
    # movescu_opts=("-S" "--aetitle"  "${AE_TITLE:?}" "--key" "0008,0052=STUDY")
    # NOTE: THIS WORKED TO GET BT OBJECTS OUT OF A VERSION 7 SYSTEM !!!!
    # movescu_opts=("-S" "$TransferSyntax_Opts" "--aetitle"  "${AE_TITLE:?}" "--key" "0008,0052=STUDY")

    # Add security options if needed
    if [ "$Source_Protocol" = "TLS" ]; then
      # movescu_opts=("$_TLS_OPT" "-S")
      # _TLS_OPT="+tls ${SSL_SITE_KEY:?} ${SSL_SITE_CERT:?} -ic"
      movescu_opts=("+tls" "${SSL_SITE_KEY:?}" "${SSL_SITE_CERT:?}" "-ic" "-S")
    else
      movescu_opts=("-S")
    fi

    # Add specific options for this migration
    movescu_opts+=("--aetitle" "${AE_TITLE:?}")
    movescu_opts+=("--move" "$Target_AET")
    movescu_opts+=("--key" "0008,0052=STUDY")
    movescu_opts+=("--key" "0020,000d=$SUID")
    movescu_opts+=("--call" "$Source_AET" "$Source_IP" "$Source_Port")

    # Add series and SOP instance UID keys if available
    if [ -n "$SERIUID" ] && [ -n "$SOPIUID" ]; then
      movescu_opts+=("--key" "0020,000E=$SERIUID" "--key" "0008,0018=$SOPIUID")
    fi
  }

#


main "$@"
