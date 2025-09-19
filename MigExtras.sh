#!/bin/bash
#shellcheck disable=SC1090,SC1091,SC2155

Usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -h, --help                Display this help message."
    echo "  -f, --set-failed          Set the failure status of a study with optional database specification."
    echo "  --insert-study            Insert a study record into the database."
    echo "  -l, --link                Link a study to a system with an optional database specification."
    echo "  --insert-link             Insert and link a study with a system."
    echo "  -e, --edit-system         Choose and edit system details."
    echo "  -s, --single              Import a study list from a single-column CSV file."
    echo "  -z                        Load system details (specific action not defined in provided script excerpt)."
    echo "Additional internal functions are accessible for direct usage in specific configurations."
}
initialize_environment() {
    BatchMode="${BatchMode:-false}"
    if ! . universal.lib; then
        echo "Required library (universal.lib) not found. Exiting..."; exit 1
    else
        initialize_script_variables "MigExtras.sh"  # Sets: _SCRIPT_NAME, _SCRIPT_CFG, _SCRIPT_LOG
        initialize_script_environment              # Verifies $USER, Verifies/Sources .default.cfg & migration.cfg
        verify_env || exit 1                       # Ensure all ${env_vars[@]} are set & not empty.
    fi
}

# ADD SYSTEMS FUNCTIONS
  InsertSystem() {
    # [medsrv@Migration-Team-PACS-Hub1-v8 20240326]$ ./combined.sh --insert-system SomeTestSystem
    # Warning: Using a password on the command line interface can be insecure.
    # Warning: Using a password on the command line interface can be insecure.
    # 20240326-170723 System SomeTestSystem inserted successfully into case_11111
      if ! DatabaseExists "$MigDB"; then
        Message -d "Error: Database does not exist. Create database first with --Install"
        exit 1
      fi
      # Usage: InsertSystem "system_label" "database_name"

      local system_label="$1"
      local database_name="$2"
      RequiredVariables "system_label" "database_name"
      local insertSystemSQL="INSERT INTO systems (label) VALUES ('$system_label');"

      if ! "$MYSQL_BIN" -BN -u medsrv --database="${database_name}" -e "$insertSystemSQL"; then
          Message -d "Error inserting into systems table"
          return 1
      fi

      Message "System $system_label inserted successfully into $database_name"
      return 0
  }
  choose_system() {
      edit_system() {
          local system_id=$1
          local fields=("enabled" "proximity" "role" "label" "internalip" "externalip" "primaryip" "aet" "port" "protocol" "iseradpacs" "ssh" "epMajorVersion" "epMinorVersion" "epPatchVersion" "filesystemroot")
          local descriptions=("Enabled [y|n]" "Proximity (RemoteFS, LocalFS, RemotePACS, LocalPACS)" "Role [source|target|conductor]" "Label" "Internal IP" "External IP" "Primary IP" "AE Title" "DICOM Port" "Protocol [TCP|TLS]" "Is ERAD PACS [y|n]" "SSH [y|n]" "EP Major Version [6|7|8]" "EP Minor Version" "EP Patch Version" "Filesystem Root")
          local fieldValues=()
          local originalValues=()
          local newValue
          local selectedField

          # Fetch and store current values
          for field in "${fields[@]}"; do
              local value="$($MYSQL_BIN -BN -u medsrv --database="${MigDB:?}" -e "SELECT $field FROM systems WHERE system_id=$system_id;")"
              fieldValues+=("$value")
              originalValues+=("$value") # Store the original value
          done

          # Editing loop
          while true; do
              echo "Current values for system ID $system_id:"
              for i in "${!fields[@]}"; do
                  echo "$((i+1))) ${descriptions[$i]}: ${fieldValues[$i]}"  # No change needed here
              done
              echo "$((${#fields[@]} + 1)) Save and quit"  # Changed from $(( ${#fields[@]} + 1 ))) to $((${#fields[@]} + 1))
              echo "$((${#fields[@]} + 2)) Discard changes and quit"  # Changed from $(( ${#fields[@]} + 2 ))) to $((${#fields[@]} + 2))

              echo "Choose a field to edit, save and quit, or discard changes and quit:"
              read -r selectedField

              if [ "$selectedField" -eq "$((${#fields[@]} + 1))" ]; then  # Changed from $(( ${#fields[@]} + 1 )) to $((${#fields[@]} + 1))
                  # Save changes
                  for i in "${!fields[@]}"; do
                      if [ "${fieldValues[$i]}" != "${originalValues[$i]}" ]; then
                          $MYSQL_BIN -BN -u medsrv --database="${MigDB:?}" -e "UPDATE systems SET ${fields[$i]}='${fieldValues[$i]}' WHERE system_id=$system_id;"
                      fi
                  done
                  echo "Changes saved."
                  break
              elif [ "$selectedField" -eq "$((${#fields[@]} + 2))" ]; then  # Changed from $(( ${#fields[@]} + 2 )) to $((${#fields[@]} + 2))
                  echo "Discarding changes."
                  break # Exit without saving
              elif [ "$selectedField" -le "${#fields[@]}" ]; then
                  echo "Enter new value for ${descriptions[selectedField-1]}:"  # Changed from ${descriptions[$((selectedField-1))]} to ${descriptions[selectedField-1]}
                  read -r newValue
                  fieldValues[selectedField-1]="$newValue"  # Changed from fieldValues[$((selectedField-1))]="$newValue" to fieldValues[selectedField-1]="$newValue"
              else
                  echo "Invalid selection. Please try again."
              fi
          done
      }

      RequiredVariables "MigDB"
      echo "Available systems:"
      "$MYSQL_BIN" -BN -u medsrv --database="${MigDB:?}" -e "SELECT system_id, label FROM systems;"

      echo "Enter the system ID you want to edit:"
      read -r system_id

      edit_system "$system_id"
  }

# LOAD EXAMS FUNCTIONS
  InsertStudy() {
      if ! DatabaseExists "$MigDB"; then
        Message -d "Error: Database does not exist. Create database first with --Install"
        exit 1
      fi
      # Usage: InsertStudy "styiuid" "database_name"

      local styiuid="$1"
      local database_name="$2"
      RequiredVariables "styiuid" "database_name"
      local insertStudySQL="INSERT INTO studies (styiuid) VALUES ('$styiuid');"

      if ! "$MYSQL_BIN" -BN -u medsrv --database="${database_name}" -e "$insertStudySQL"; then
          Message -d "Error inserting into studies table"
          return 1
      fi

      Message -d "Study $styiuid inserted successfully into $database_name"
      return 0
  }
  LinkStudySystem() {
    # [medsrv@Migration-Team-PACS-Hub1-v8 20240326]$ ./combined.sh --link 1.2.124.113532.32961.28196.61186.20150706.65653.3097184759 SomeTestSystem
    # Warning: Using a password on the command line interface can be insecure.
    # Warning: Using a password on the command line interface can be insecure.
    # 20240326-170751 Study with ID 1.2.124.113532.32961.28196.61186.20150706.65653.3097184759 exists in case_11111.
    # Warning: Using a password on the command line interface can be insecure.
    # 20240326-170751 System with label SomeTestSystem exists in case_11111.
    # Warning: Using a password on the command line interface can be insecure.
    # 20240326-170751 Study 1.2.124.113532.32961.28196.61186.20150706.65653.3097184759 linked with system SomeTestSystem in case_11111 successfully.
      if ! DatabaseExists "$MigDB"; then
        Message -d "Error: Database does not exist. Create database first with --Install"
        exit 1
      fi
      # Usage: LinkStudySystem "unique_styiuid" "unique_system_label" "my_database_name"

      local styiuid="$1"
      local system_label="$2"
      local database_name="$3"
      RequiredVariables "styiuid" "system_label" "database_name"

      # Check if the study exists
      if ! StudyExists "$styiuid" "$database_name"; then
          Message -d "Study with ID $styiuid does not exist in $database_name."
          return 1
      fi

      # Check if the system exists
      if ! SystemExists "$system_label" "$database_name"; then
          Message -d "System with label $system_label does not exist in $database_name."
          return 1
      fi

      # Attempt to link the study and system
      local insertLinkSQL="INSERT INTO studies_systems (styiuid, system_id) SELECT '$styiuid', system_id FROM systems WHERE label = '$system_label';"
      if ! $MYSQL_BIN -BN -u medsrv --database="$database_name" -e "$insertLinkSQL"; then
          Message -d "Error linking study $styiuid with system $system_label in $database_name."
          return 1
      fi

      Message -d "Study $styiuid linked with system $system_label in $database_name successfully."
      return 0
  }
  InsertAndLinkRecord() {
      if ! DatabaseExists "$MigDB"; then
        Message -d "Error: Database does not exist. Create database first with --Install"
        exit 1
      fi
      # Usage: InsertAndLinkRecord "unique_styiuid" "unique_system_label" "my_database_name"

      local styiuid="$1"
      local system_label="$2"
      local database_name="$3"
      RequiredVariables "styiuid" "system_label" "database_name"

      if ! InsertStudy "$styiuid" "$database_name"; then return 1; fi

      if ! InsertSystem "$system_label" "$database_name"; then return 1; fi

      if ! LinkStudySystem "$styiuid" "$system_label" "$database_name"; then return 1; fi

      Message -d "Insertion and linking of study $styiuid with system $system_label completed successfully"
  }
  ImportStyListViaCSV() {
    ImportStyListViaCSV_MysqlLoad() {
        local data_file="$1"
        local system_label="$2"
        local database_name="$3"

        # Proceed with the rest of your function...
        local temp_table="temp_studies"
        
        # Check if the data file exists
        if [ ! -f "$data_file" ]; then
            Message -d "Data file does not exist: $data_file"
            return 1
        fi

        # Retrieve system_id for the given system_label
        local system_id_query="SELECT system_id FROM systems WHERE label='$system_label';"
        local system_id=$("$MYSQL_BIN" -BN -u medsrv --database="$database_name" -e "$system_id_query")
        
        if [ -z "$system_id" ]; then
            Message -d "System label $system_label not found. Exiting."
            return 1
        fi

        # Commands to create a temporary table
        local create_temp_table_sql="DROP TABLE IF EXISTS $temp_table;
                                      CREATE TABLE $temp_table (styiuid VARCHAR(100) NOT NULL);"

        # Load data into temporary table
        local load_data_sql="LOAD DATA LOCAL INFILE '$data_file' INTO TABLE $temp_table
                            LINES TERMINATED BY '\n';"

        # Insert data from temporary table into main tables
        local insert_into_studies_sql="INSERT INTO studies (styiuid) SELECT styiuid FROM $temp_table ON DUPLICATE KEY UPDATE styiuid=VALUES(styiuid);"
        local insert_into_studies_systems_sql="INSERT INTO studies_systems (styiuid, system_id)
                                              SELECT styiuid, '$system_id' FROM $temp_table
                                              ON DUPLICATE KEY UPDATE system_id=VALUES(system_id);"

        # Execute SQL commands
        echo "Creating temporary table..."
        echo "$create_temp_table_sql" | "$MYSQL_BIN" -u medsrv --database="$database_name"

        echo "Loading data into temporary table..."
        echo "$load_data_sql" | "$MYSQL_BIN" --local-infile=1 -u medsrv --database="$database_name"

        echo "Inserting records into studies..."
        echo "$insert_into_studies_sql" | "$MYSQL_BIN" -u medsrv --database="$database_name"

        echo "Inserting records into studies_systems..."
        echo "$insert_into_studies_systems_sql" | "$MYSQL_BIN" -u medsrv --database="$database_name"

        echo "Data insertion complete."
    }
      
      if ! DatabaseExists "$MigDB"; then
          Message -d "Error: Database does not exist. Create database first with --Install"
          exit 1
      fi

      local file_path="$1"
      local system_label="$2"
      local database_name="$3"
      local default_system="DefaultSystem$(date +%Y%m%d)"  # Default system label
      
      # If system_label is empty, set it to default_system
      if [ -z "$system_label" ]; then
          system_label="$default_system"
      fi

      # If database_name is empty, set it to MigDB
      if [ -z "$database_name" ]; then
          database_name="$MigDB"
      fi

      RequiredVariables "file_path"

      # Check if the data file exists
      if [ ! -f "$file_path" ]; then
          Message -d "Data file does not exist: $file_path"
          return 1
      fi

      # First try the faster method
      if ! ImportStyListViaCSV_MysqlLoad "$file_path" "$system_label" "$database_name"; then
        Message -d "Failed to import study list. Exiting."
        exit 1
      else
        Message -d "Successfully imported the study list."
      fi
  }
  ImportDcmObjectsViaCSV_MysqlLoad() {
    # Function to import DICOM file data into the dcm_objects table
    # Example usage: ImportDcmObjectsViaCSV_MysqlLoad "foundDcmFiles.txt" "system_label" "database_name"
      local data_file="$1"
      local system_label="$2"
      local database_name="$3"

      local temp_table="temp_dcm_objects"

      # Retrieve system_id for the given system_label
      local system_id_query="SELECT system_id FROM systems WHERE label='$system_label';"
      local system_id=$("$MYSQL_BIN" -BN -u medsrv --database="$database_name" -e "$system_id_query")

      # Check if system_id was retrieved
      if [ -z "$system_id" ]; then
          echo "System label $system_label not found. Exiting."
          return 1
      fi

      # Commands to create a temporary table
      local create_temp_table_sql="DROP TABLE IF EXISTS $temp_table;
                                  CREATE TABLE $temp_table (
                                      styiuid VARCHAR(100) NOT NULL,
                                      sopiuid VARCHAR(64) NOT NULL,
                                      fullpath VARCHAR(255) NOT NULL,
                                      INDEX idx_styiuid (styiuid),
                                      INDEX idx_sopiuid (sopiuid)
                                  );"

      # Load data into temporary table
      local load_data_sql="LOAD DATA LOCAL INFILE '$data_file' INTO TABLE $temp_table
                          FIELDS TERMINATED BY '\t' 
                          LINES TERMINATED BY '\n'
                          (styiuid, sopiuid, fullpath);"

      # Insert data from temporary table into dcm_objects table
      local insert_into_dcm_objects_sql="INSERT INTO dcm_objects (styiuid, system_id, sopiuid, fullpath)
                                        SELECT styiuid, '$system_id', sopiuid, fullpath FROM $temp_table
                                        ON DUPLICATE KEY UPDATE sopiuid=VALUES(sopiuid), fullpath=VALUES(fullpath);"

      # Execute SQL commands
      echo "Creating temporary table..."
      if ! echo "$create_temp_table_sql" | "$MYSQL_BIN" -u medsrv --database="$database_name"; then
          echo "Failed to create temporary table."
          return 1
      fi

      echo "Loading data into temporary table..."
      if ! echo "$load_data_sql" | "$MYSQL_BIN" --local-infile=1 -u medsrv --database="$database_name"; then
          echo "Failed to load data into temporary table."
          return 1
      fi

      echo "Transferring data to production dcm_objects table..."
      if ! echo "$insert_into_dcm_objects_sql" | "$MYSQL_BIN" -u medsrv --database="$database_name"; then
          echo "Failed to transfer data to production dcm_objects table."
          return 1
      fi

      echo "Data insertion complete."
      return 0
  }

# MYSQL UPDATE FUNCTIONS
  set_verification() {
      # FIXME: Needs a menu option to access this function
      local _styiuid="$1"
      local _status="$2"
      local _query="UPDATE studies SET verification='$_status' WHERE styiuid='$_styiuid'"

      # verify _styiuid is not empty
      if [[ -z "$_styiuid" ]]; then
          echo "Error: Study UID cannot be empty."
          return 1  # Return with an error code
      fi

      # verify _status is one of four possible options: pending, passed, failed, n/a
      if [[ "$_status" != "pending" && "$_status" != "passed" && "$_status" != "failed" && "$_status" != "n/a" ]]; then
          echo "Error: Invalid status '$_status'. Valid options are 'pending', 'passed', 'failed', 'n/a'."
          return 1  # Return with an error code
      fi

      # Execute the query
      if ! "$MYSQL_BIN" -BN -u medsrv --database="${database_name}" -e "$_query"; then
          echo "Error: Failed to update verification status."
          return 1
      fi

      echo "Verification status updated successfully."
      return 0
  }
  set_failed_with_comment_check() {
      # FIXME: Needs work; simple as that.
      local styiuid="$1"
      local database_name="$2"
      # Check if comment is empty
      local comment_check_query="SELECT comment FROM studies WHERE styiuid='$styiuid' AND TRIM(comment) = '';"
      local comment_empty=$("$MYSQL_BIN" -BN -u medsrv --database="$database_name" -e "$comment_check_query")
      
      if [[ -n "$comment_empty" ]]; then
          echo "Comments must be added before a study verification can be set to failed."
          echo "Use the script like this: ./main.sh --edit-study verification failed '<comment>'"
      else
          local update_failed_query="UPDATE studies SET verification = 'failed' WHERE styiuid='$styiuid';"
          "$MYSQL_BIN" -BN -u medsrv --database="$database_name" -e "$update_failed_query"
      fi
  }

# MISC / NOT USED
  calcSizeOfStyList() {
    # Call the function with the lsofsuid file as an argument
    # calcSizeOfStyList "$1"
    local lsofsuid="$1"

    # VERIFYING CORRECT USER
    if [ "$(whoami)" != "medsrv" ]; then
        echo "Script must be run as user: medsrv"
        return 1
    fi

    local sum="0"
    local count="0"
    local total=$(cat "$lsofsuid" | wc -l)
    local start=$(date +%s)

    # Main loop
    while read -r suid && [ "$count" -lt "$total" ]; do
        ####### WORK #######
        local repoloc=$(~/component/repositoryhandler/scripts/locateStudy.sh -d "$suid")
        local repolocsize=$(du -s --block-size=1K "$repoloc" | awk '{print $1}')  # size in KB
        sum=$(($sum + $repolocsize))
        local sum_mb=$(($sum / 1024))
        local sum_gb=$(($sum_mb / 1024))
        ####### WORK #######

        # Progress calculation
        local cur=$(date +%s)
        count=$((count + 1))
        local pd=$((count * 73 / total))
        local runtime=$((cur - start))
        local estremain=$(((runtime * total / count) - runtime))

        # Print progress
        printf "\r%d.%d%% complete ($count of $total) - est %d:%0.2d remaining - SUM $sum KB ($sum_mb MB, $sum_gb GB)\e[K" \
            $((count * 100 / total)) $(((count * 1000 / total) % 10)) $((estremain / 60)) $((estremain % 60))
    done < "$lsofsuid"

    printf "\ndone\n"
  }
  handle_error() {
      local error_message="$1"
      local exit_code="${2:-1}"  # Default exit code is 1

      # Log the error message using the existing logging function
      Message -l "ERROR" "$error_message"

      # Perform cleanup operations
      echo "Performing cleanup operations..."
      # Add any necessary cleanup commands here, like removing temporary files
      echo "Cleanup completed."

      # Exit with the provided exit code
      exit "$exit_code"
  }
  StudyExists() {
      local styiuid="$1"
      local database="$2"

      if [[ -z "$styiuid" || -z "$database" ]]; then
          Message -d "Usage: StudyExists <styiuid> <database>"
          return 2
      fi

      local exists
      exists=$(/home/medsrv/component/mysql/bin/mysql -BN -D "$database" \
          -e "SELECT EXISTS(SELECT 1 FROM studies WHERE styiuid = '$styiuid');")

      if [[ "$exists" -eq 1 ]]; then
          Message -d "Study with ID $styiuid exists in $database."
          return 0
      else
          Message -d "Study with ID $styiuid does not exist in $database."
          return 1
      fi
  }
  SystemExists() {
      local system_label="$1"
      local database_name="$2"

      # SQL query to check if the system exists
      local checkSystemExistsSQL="SELECT EXISTS(SELECT 1 FROM systems WHERE label='$system_label');"

      # Execute the SQL query and check the existence
      if ! $MYSQL_BIN -BN -u root -p"$MYSQL_ROOT_PW" --database="$database_name" -e "$checkSystemExistsSQL" | grep -q 1; then
          Message -d "System with label $system_label does not exist in $database_name."
          return 1
      else
          Message -d "System with label $system_label exists in $database_name."
          return 0
      fi
    # Usage example:
    # CheckSystemExists "unique_system_label" "my_database_name"
    # if [ $? -eq 0 ]; then
    #   echo "System exists."
    # else
    #   echo "System does not exist."
    # fi
  }
  getRoleFor() {
    local label="$1"  # Capture the first argument as the label
    # SQL query to get the role for the given label
    local getRoleSQL="SELECT role FROM systems WHERE label='$label';"

    # Using MYSQL_BIN and MigDB assuming these are defined elsewhere in your environment or script
    local role
    role="$("$MYSQL_BIN" -BN -u medsrv --database="$MigDB" -e "$getRoleSQL")"

    if [ -z "$role" ]; then
        return 1
    else
        echo "$role"
    fi
  }
  verifySelfAET() {
    if [ -z "$AE_TITLE" ] || ! grep -q "$AE_TITLE" /home/medsrv/var/dicom/pb-scp.cfg; then
      . /home/medsrv/var/dicom/pb-scp.cfg
    fi
  }
  #shellcheck disable=SC2034
  verifyTargetDevice() {
    # TODO: Source_AET will not work if the source is local
    TargetVerified=False
      if [[ -n $(sql.sh "SELECT AE FROM Target WHERE AE='$Source_AET'" -N) ]]; then
        TargetVerified=True
      else
        Message "Target device $TARGET_DEVICE_NAME cannot be verified. Exiting."
        exit 1
      fi
  }
  # For archival purposes
  Usage_From_MigAdminsh() {
      # local topic="${1,,}"  # Bash 4.0+ required
      local topic="$(echo "$1" | tr '[:upper:]' '[:lower:]')"

      local setup_config_info="Options for Setup & Config:
        --install
            Perform a fresh installation.
            Example: $0 --install

        --insert-system <system_label>
            Insert a system record.
            Example: $0 --insert-system 'old_v7_prod'

        --edit-system
            Edit an existing system record. Displays a list of systems for selection.

        -a, --all <file_path> [<system_label> [<database_name>]]
            Import study records from a CSV file containing multiple columns.
            Example: $0 --all 'file_path' 'old_v7_prod'
            CSV File format: Each line should contain STYIUID, number of objects, and the cumulative size of objects.
            Example CSV content: 1.2.840.142.4.11373.113797.122574.721925 250 1250000
                                1.2.840.142.4.11373.113798.122575.721926 300 1500000
                                1.2.840.142.4.11373.113799.122576.721927 100 500000
            To generate a multi-column file with viable study instance UIDs, number of objects, and sum size for migration:
            Example: sql.sh \"SELECT styiuid, numofobj, sumsize FROM Dcstudy WHERE mainst>='0' AND Dcstudy_d!='yes' AND derived NOT IN('copy','shortcut')\" -N > study-list_\$(date \"+%Y%m%d-%H%M%S\").tsv
            If you have SSH connectivity, you can fetch the remote study list with multiple columns using this command:
            Example: ssh remote_pacs \"sql.sh \\\"SELECT styiuid, numofobj, sumsize FROM Dcstudy WHERE mainst>='0' AND Dcstudy_d!='yes' AND derived NOT IN('copy','shortcut')\\\" -N\" >study-list_\$(date \"+%Y%m%d-%H%M%S\")_remote.tsv

        -s, --single <file_path> [<system_label> [<database_name>]]
            Import STYIUIDs from a single-column CSV file.
            Example: $0 --single 'file_path' 'old_v7_prod'
            Single-column CSV File format: Each line should contain a single STYIUID.
            Example CSV content: 1.2.840.142.4.11373.113797.122574.721925
                                  1.2.840.142.4.11373.113798.122575.721926
                                  1.2.840.142.4.11373.113799.122576.721927
            To generate a single-column file with viable study instance UIDs for migration:
            Example: sql.sh \"SELECT styiuid FROM Dcstudy WHERE mainst>='0' AND Dcstudy_d!='yes' AND derived NOT IN('copy','shortcut')\" -N > suid-list_\$(date \"+%Y%m%d-%H%M%S\").txt
            If you have SSH connectivity, you can fetch the remote study list using this command:
            Example: ssh remote_pacs \"sql.sh \\\"SELECT styiuid FROM Dcstudy WHERE mainst>='0' AND Dcstudy_d!='yes' AND derived NOT IN('copy','shortcut')\\\" -N\" >suid-list_\$(date \"+%Y%m%d-%H%M%S\")_remote.txt
            "

      local study_adjustments_info="Options for Study Adjustments:
        -I|-i <styiuid>
        --study-info <styiuid>
            Gather exam state information.
            Example: $0 -S '1.2.840.142.4.11373.113797.122574.721925'

        --insert-study <styiuid> [database name]
            Insert a study record.
            Example: $0 --insert-study '1.2.840.142.4.11373.113797.122574.721925'

        --set-failed <styiuid> [database name]
            Set verification status to 'failed' for a specific study, requires comment.

        -l, --link <styiuid> <system_label> [database name]
            Link a study and system.

        --insert-link <styiuid> <system_label> [database name]
            Insert and link a study with a system."

      local queries_info="Options for Queries:
        -Q, --query-context
            Display project context information.
            Example: $0 -Q"

      case "$topic" in
          *setup*|*config*)
              echo "$setup_config_info"
              ;;
          *study*|*adjustment*)
              echo "$study_adjustments_info"
              ;;
          *query*|*queries*)
              echo "$queries_info"
              ;;
          *)
              echo "Usage: $0 --help [topic]"
              echo "Topics available:"
              echo "  Setup & Config      Configure system settings and perform installations."
              echo "  Study Adjustments   Modify and manage study records."
              echo "  Queries             Display system and project context information."
              ;;
      esac
  }
  
#
main() {
    initialize_environment

    if [ "$#" -eq 0 ]; then
        Usage
        exit 0
    fi

    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -h|--help) Usage "$2"; exit 0 ;;
            -f|--set-failed) set_failed_with_comment_check "$2" "${3:-$MigDB}"; shift 2 ;;
            --insert-study) InsertStudy "$2" "$MigDB"; shift 2 ;;
            -l|--link) LinkStudySystem "$2" "$3" "${4:-$MigDB}"; shift 3 ;;
            --insert-link) InsertAndLinkRecord "$2" "$3" "${4:-$MigDB}"; shift 3 ;;
            -e|--edit-system) choose_system; exit 0 ;;
            -s|--single) ImportStyListViaCSV "$2" "$3" "${4:-$MigDB}"; shift 3 ;;
            -z) load_system_details ;; # NOTE: Add some action after loading details?
            *) echo "Unknown option: $1" >&2; Usage; exit 1 ;;
        esac
        shift
    done
}

main "$@"
