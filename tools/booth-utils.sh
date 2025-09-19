#!/bin/bash

myscript=$(basename "$0")
mylog=${myscript%.*}.log
mydropfile=${myscript%.*}.d
dateformat="%Y-%m-%d %H:%M:%S"

# Add the new option to getOptions
getOptions() {
    [ $# -eq 0 ] && Usage
    while [ -n "$1" ]; do
        case $1 in
            --help|-h) Usage ;;
            --verbose|-v) _VERBOSE_OPTS="--verbose" ;;
            --whatif|-if) _DRY_RUN="y" ;;
            --env) manage_env --display ; exit 0 ;;
            --show-big-files) DisplayLargestFiles ;;
            --backup-db) performDatabaseBackup ; exit $? ;;
            --archive-project) archiveProjectDirectory ; exit $? ;;
            *)
                Message --display-only --log-level "ERROR" "Unknown option (ignored): $1"
                Usage ;;
        esac
        shift
    done
}

# =========================
# Helper Functions
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
      local log_file="$mylog"
      local log_message=""
      local log_options=()
      local timestamp=$(date +"$dateformat")

      # Parse arguments
      while [[ $# -gt 0 ]]; do
          case "$1" in
              -q|--quiet) quiet_mode=1 ;;
              -d|--display-only) display_only=1 ;;
              -l|--log-level) log_level="$2"; shift ;;
              -f|--log-file) log_file="$2"; shift ;;
              *) log_options+=("$1") ;;
          esac
          shift
      done

      # Combine all remaining arguments into the log message
      log_message="${log_options[*]}"

      # Handle dry-run prefix
      [[ "${_DRY_RUN:="n"}" == "y" ]] && log_message="DRY-RUN $log_message"

      # Construct the log entry
      log_message="${timestamp} [${log_level}] ${log_message}"

      # Output the log message based on the chosen mode
      if [[ $display_only -eq 1 ]]; then
          printf "%s\n" "$log_message"
      elif [[ $quiet_mode -eq 1 ]]; then
          printf "%s\n" "$log_message" >> "$log_file"
      else
          printf "%s\n" "$log_message" | tee -a "$log_file"
      fi
  }
  sourceDropFile() {
      if [[ -f "$mydropfile" ]]; then
          # Log that the drop file is being sourced
          Message --log-level "INFO" "Sourcing drop file: $mydropfile"
          # Source the drop file
          . "$mydropfile"
          # Log successful sourcing
          Message --log-level "INFO" "Drop file sourced successfully."
      else
          # Log if the drop file is not found
          Message --log-level "WARNING" "Drop file not found: $mydropfile"
      fi
  }

# =========================
# Utilities
# =========================
  DisplayLargestFiles() {
      local exclude_dir="$PWD/backups/dcm"

      # Log the exclusion of files from the specified directory
      Message --display-only --log-level "INFO" "Excluding files in $exclude_dir"

      # Find and display the largest files, excluding the specified directory
      find $PWD -type f ! -path "$exclude_dir/*" -exec ls -s --block-size=M {} + | sort -n -r | head -10
  }
  performDatabaseBackup() {
      # Display a list of MySQL databases
      Message --display-only --log-level "INFO" "Fetching the list of MySQL databases."
      local databases
      databases=$(mysql -u root --password="$MYSQL_ROOT_PW" -e "SHOW DATABASES;" 2>/dev/null | awk 'NR>1')
      if [ -z "$databases" ]; then
          Message --log-level "ERROR" "Failed to fetch the list of MySQL databases. Ensure MySQL is running and credentials are correct."
          exit 1
      fi

      printf "Available Databases:\n"
      printf "%s\n" "$databases"

      # Prompt for database name if not already set
      if [ -z "$migration_database" ]; then
          read -r -p "Enter the name of the database you wish to back up: " db_to_backup
      else
          db_to_backup="$migration_database"
      fi

      # Validate that the selected database exists
      if ! printf "%s\n" "$databases" | grep -q "^${db_to_backup}$"; then
          Message --log-level "ERROR" "The database '${db_to_backup}' does not exist."
          exit 1
      fi

      # Set up backup filenames
      local backup_sql_filename="migdb-backup_${db_to_backup}_$(date +%Y%m%d_%H%M%S).sql"
      local backup_zip_filename="${backup_sql_filename}.zip"

      # Log the start of the backup
      Message --log-level "INFO" "Starting backup for database: ${db_to_backup}"

      # Start the backup
      if mysqldump -u root --password="$MYSQL_ROOT_PW" "$db_to_backup" >"$backup_sql_filename" 2>/dev/null; then
          Message --log-level "INFO" "Backup completed for database: ${db_to_backup}. File: ${backup_sql_filename}"
      else
          Message --log-level "ERROR" "Backup failed for database: ${db_to_backup}."
          exit 1
      fi

      # Compress the backup file
      if zip "$backup_zip_filename" "$backup_sql_filename"; then
          rm -f "$backup_sql_filename"
          Message --log-level "INFO" "Backup compressed successfully. File: ${backup_zip_filename}"
      else
          Message --log-level "ERROR" "Compression failed for file: ${backup_sql_filename}."
          exit 1
      fi
  }
  archiveProjectDirectory() {
      local project_dir="$PWD"
      local customer_name
      local case_number

      # Prompt for customer name
      read -r -p "Enter the customer name: " customer_name
      if [[ -z "$customer_name" ]]; then
          Message --log-level "ERROR" "Customer name cannot be empty."
          exit 1
      fi

      # Prompt for case number
      read -r -p "Enter the case number: " case_number
      if [[ -z "$case_number" ]]; then
          Message --log-level "ERROR" "Case number cannot be empty."
          exit 1
      fi

      # Create archive name with customer name and case number
      local timestamp
      timestamp=$(date +%Y%m%d_%H%M%S)
      local archive_name="${customer_name}_${case_number}_${timestamp}.zip"

      # Log the start of the archiving process
      Message --log-level "INFO" "Starting project directory archiving process."

      # Use zip command without changing directories
      zip -vr "../$archive_name" ./* \
          -x "./backups/*" \
          -x "./.checkLoad.tmp" \
          -x "./.migration_counter"

      # Check if the archiving was successful
      if [ $? -eq 0 ]; then
          Message --log-level "INFO" "Project directory archived successfully. Archive file: ../${archive_name}"
      else
          Message --log-level "ERROR" "Failed to archive the project directory."
          exit 1
      fi
  }

# =========================
# Utilities
# =========================
main() {
  getOptions "$@"
}

main "$@"
