#!/bin/bash
#shellcheck disable=SC1090,SC1091,SC2155

usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -h, --help         Display this help message."
    echo "  -q, --query        Enter query mode to fetch and display migration status data."
    echo "  -e, --env          Display environment details."
}
parse_args() {
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            -q|--query)
                QueryFor_
                exit 0
                ;;
            -e|--env)
                display_env
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
        # shellcheck disable=SC2317
        shift
    done
}
initialize_environment() {
    BatchMode="${BatchMode:-false}"
    if ! . universal.lib; then
        echo "Required library (universal.lib) not found. Exiting..."; exit 1
    else
        initialize_script_variables "MigStatus.sh"  # Sets: _SCRIPT_NAME, _SCRIPT_CFG, _SCRIPT_LOG
        initialize_script_environment              # Verifies $USER, Verifies/Sources .default.cfg & migration.cfg
        verify_env || exit 1                       # Ensure all ${env_vars[@]} are set & not empty.
    fi
}
calculate_percentage() {
  local part="$1"
  local whole="$2"

  # Ensure that the whole is not zero to avoid division by zero error
  if [[ "$whole" -eq 0 ]]; then
    echo "0"  # Return 0% if the whole is 0 to avoid division by zero
    return
  fi

  # Calculate percentage
  local percentage
  # percentage=$(bc -l <<< "scale=2; ($part/$whole)*100")  # 'bc -l' is used for floating point division
  percentage=$( printf "%.2f" "$(echo "scale=4; $part / $whole * 100" | bc -l)" )

  # Output the result formatted to two decimal places
  printf "%.2f%%\n" "$percentage"
}
bytes_to_gb() {
    local bytes="$1"
    if [[ -z "$bytes" || "$bytes" -eq 0 ]]; then
        echo "0 GB"
    else
        # Convert bytes to gigabytes (1 GB = 1024 * 1024 * 1024 bytes)
        local gb=$(echo "scale=2; $bytes / (1024 * 1024 * 1024)" | bc)
        echo "${gb} GB"
    fi
}
# Function to validate SortColumns and SortDirections and apply defaults if necessary
validate_sort_column() {
    local sort_columns="$1"
    local sort_directions="$2"

    # Read the allowed columns from migration.cfg
    local allowed_columns=$(grep 'AllowedSortColumns' migration.cfg | cut -d'=' -f2)

    # Convert allowed columns and input columns/directions to arrays
    IFS=',' read -r -a allowed_columns_array <<< "$allowed_columns"
    IFS=',' read -r -a sort_columns_array <<< "$sort_columns"
    IFS=',' read -r -a sort_directions_array <<< "$sort_directions"

    local validated_columns=()
    local validated_directions=()

    # Validate each column and its corresponding direction
    for i in "${!sort_columns_array[@]}"; do
        local col="${sort_columns_array[$i]}"
        local dir="${sort_directions_array[$i]:-DESC}"  # Default to DESC if no direction provided

        # Validate the column
        local valid_column="false"
        for allowed_col in "${allowed_columns_array[@]}"; do
            if [[ "$col" == "$allowed_col" ]]; then
                valid_column="true"
                break
            fi
        done

        # If column is invalid, default to the first allowed column but avoid echoing
        if [[ "$valid_column" != "true" ]]; then
            col="s.styDate"  # Fallback to 'studies.styDate'
        fi
        validated_columns+=("$col")

        # Validate the direction (only allow ASC or DESC)
        if [[ "$dir" != "ASC" && "$dir" != "DESC" ]]; then
            dir="DESC"  # Fallback to 'DESC'
        fi
        validated_directions+=("$dir")
    done

    # Join the validated columns and directions into comma-separated strings
    local validated_sort_columns=$(IFS=','; echo "${validated_columns[*]}")
    local validated_sort_directions=$(IFS=','; echo "${validated_directions[*]}")

    # Return the validated columns and directions without any error messages
    echo "$validated_sort_columns $validated_sort_directions"
}

# MYSQL QUERY FUNCTIONS
  QueryFor_() {
      RequiredVariables "MigDB"
      if ! DatabaseExists "$MigDB"; then
          Message -d "Error: Database does not exist. Create database first with --Install"
          exit 1
      fi

      # local database_name="${1:-$MigDB}"
      local database_name="${MigDB}"

      echo "Select an option to proceed (you can select multiple options, separated by spaces):"
      echo "1) Display Project Context"
      echo "2) Display System Details"
      echo "3) Total Unique Studies (WHERE skip='n')"
      echo "4) Unique Studies In-Scope (WHERE skip='n')"
      echo "5) Unique Studies Sent (WHERE skip='n' AND verification IN('pending','passed'))"
      echo "6) Unique Studies Migrated (WHERE skip='n' AND verification='passed')" # Moved to position 6
      echo "7) Pending Studies (WHERE skip='n' AND verification='pending' AND role='source')"
      echo "8) Fully Absent Studies (WHERE skip='n' AND verification='n/a' AND role='source')"
      echo "9) Unique Studies Set to Skip (WHERE skip='y')"
      echo "10) Unique Studies to Migrate (WHERE skip='n' AND verification='n/a' AND role='source')"
      echo "11) Migrated Studies File (WHERE skip='n' AND verification='failed')" #NOTE: review for mysql errors
      echo "Please enter your choice (1-11):"
      read -r -a choices

      Total_InScope_Studies="$(unique_studies_in_scope "$database_name" "quiet")"
      z_Total_InScope_Studies_Count="
        SELECT SUM(ss.stysize)
        FROM studies s
        JOIN migadmin m ON s.styiuid = m.styiuid
        JOIN studies_systems ss ON s.styiuid = ss.styiuid
        JOIN systems sys ON ss.system_id = sys.system_id
        WHERE m.in_scope = 'y'
          AND sys.role = 'source'
      "
      z_Total_InScope_Studies_Size="
        SELECT SUM(ss.stysize)
        FROM studies s
        JOIN migadmin m ON s.styiuid = m.styiuid
        JOIN studies_systems ss ON s.styiuid = ss.styiuid
        JOIN systems sys ON ss.system_id = sys.system_id
        WHERE m.in_scope = 'y'
          AND sys.role = 'source'
      "
      for choice in "${choices[@]}"; do
          case $choice in
              1) DisplayProjectContext ;;
              2) display_system_details "$database_name" ;;
              3) total_unique_studies_with_size "$database_name" ;;
              # 4) echo "Unique studies in-scope: $Total_InScope_Studies" ;;
              4) unique_studies_in_scope "$database_name" ;;
              5) unique_studies_sent "$database_name" ;;
              6) unique_studies_migrated "$database_name" ;;
              7) unique_studies_pending "$database_name" ;;
              8) unique_studies_wholly_missing "$database_name" ;;
              9) unique_studies_to_skip "$database_name" ;;
              10) unique_studies_to_migrate "$database_name" ;;
              11) Migration_Study_List "$database_name" ;;
              *) echo "Invalid option: $choice" ;;
          esac
      done
  }
  DisplayProjectContext() {
      # No need for database_name as an argument since we'll use the MigDB variable

      # Ensure the CaseNumber and MigDB variables are set
      if [[ -z "$CaseNumber" || -z "$MigDB" ]]; then
          Message -d "ERROR: Required variables CaseNumber or MigDB are not set."
          return 1
      fi

      Message -d "Context Information for Project:"
      Message -d "Case Number: $CaseNumber"
      Message -d "Database Name: $MigDB"

      # Display existing tables
      Message -d "Existing Tables in $MigDB:"
      echo "SHOW TABLES;" | "$MYSQL_BIN" -BN -u medsrv --database="$MigDB" | while read -r table; do
          Message -d " - $table"
      done

      # Display summary of existing records in key tables, e.g., studies and systems
      local studies_count=$(echo "SELECT COUNT(*) FROM studies;" | "$MYSQL_BIN" -BN -u medsrv --database="$MigDB")
      local systems_count=$(echo "SELECT COUNT(*) FROM systems;" | "$MYSQL_BIN" -BN -u medsrv --database="$MigDB")
      
      # Calculate total DICOM dataset size from the 'stysize' column in 'studies_systems' table
      local total_size_bytes=$(echo "SELECT COALESCE(SUM(stysize), 0) FROM studies_systems;" | "$MYSQL_BIN" -BN -u medsrv --database="$MigDB")
      local total_size_gb=$(echo "scale=2; $total_size_bytes / 1024 / 1024 / 1024" | bc)

      Message -d "Number of Systems: $systems_count"
      Message -d "Number of Studies: $studies_count ($total_size_gb GB)"
      # Message -d "Total Size of DICOM Dataset: $total_size_gb GB"

      # Add number of in-scope studies and size (apply date filters if provided)
      local query="SELECT COUNT(*) FROM studies s WHERE 1=1"
      local size_query="SELECT COALESCE(SUM(ss.stysize), 0) FROM studies_systems ss JOIN studies s ON s.styiuid = ss.styiuid WHERE 1=1"

      if [[ -n "$StartDate" ]]; then
          query+=" AND DATE(s.styDate) <= '$StartDate'"
          size_query+=" AND DATE(s.styDate) <= '$StartDate'"
      fi
      if [[ -n "$StopDate" ]]; then
          query+=" AND DATE(s.styDate) >= '$StopDate'"
          size_query+=" AND DATE(s.styDate) >= '$StopDate'"
      fi

      # Execute the queries for in-scope studies and size
      local in_scope_studies_count=$(echo "$query;" | "$MYSQL_BIN" -BN -u medsrv --database="$MigDB")
      local in_scope_total_size_bytes=$(echo "$size_query;" | "$MYSQL_BIN" -BN -u medsrv --database="$MigDB")
      local in_scope_total_size_gb=$(echo "scale=2; $in_scope_total_size_bytes / 1024 / 1024 / 1024" | bc)

      Message -d "Number of in-scope Studies: $in_scope_studies_count ($in_scope_total_size_gb GB)"
      # Message -d "Total Size of in-scope DICOM Dataset: $in_scope_total_size_gb GB"
  }
  display_system_details() {
      local database_name="$1"
      # local query="SELECT system_id, enabled, proximity, role, label, internalip, externalip, primaryip, aet, port, protocol, iseradpacs, ssh, epMajorVersion, epMinorVersion, epPatchVersion, filesystemroot FROM systems;"
      local query="SELECT system_id, enabled, proximity, role, label, internalip, externalip, primaryip, aet, port, protocol, iseradpacs, ssh, epMajorVersion, epMinorVersion, epPatchVersion, filesystemroot FROM systems\G"

      echo "System Details:"
      "$MYSQL_BIN" -u medsrv --database="${database_name}" -e "$query"
  }
  total_unique_studies_with_size() {
    local database_name="$1"
    local output_mode="$2"

    local where_clause="WHERE skip='n' AND role='source'"
    # Modified query to also retrieve the sum of the 'stysize' column across all studies
    # local query="SELECT COUNT(*), COALESCE(SUM(ss.stysize), 0) FROM studies s LEFT JOIN studies_systems ss ON s.styiuid = ss.styiuid;"
    # local query="SELECT COUNT(DISTINCT s.styiuid), COALESCE(SUM(ss.stysize), 0) FROM studies s LEFT JOIN studies_systems ss ON s.styiuid = ss.styiuid WHERE s.skip!='y';"
    local query="
      SELECT COUNT(*)
      FROM migadmin m
      WHERE m.skip != 'y'
        AND m.styiuid IN (
          SELECT DISTINCT ss.styiuid
          FROM studies_systems ss
          INNER JOIN systems s ON ss.system_id = s.system_id
          WHERE s.role != 'target'
        )"

    # Read the result into separate variables
    # read count sumsize <<< $("${MYSQL_BIN}" -BN -u medsrv --database="${database_name}" -e "${query}" -s -N)
    # shellcheck disable=SC2046,SC2162
    read count <<< $("${MYSQL_BIN}" -BN -u medsrv --database="${database_name}" -e "${query}" -s -N)
    
    # Convert bytes to gigabytes and format the number
    # local gb_size=$(echo "scale=2; $sumsize / 1024 / 1024 / 1024" | bc)
    # local formatted_gb_size=$(printf "%'.2f\n" $gb_size)  # formats to nearest hundredths with commas

    # Formatting output based on the output mode
    if [[ "${output_mode}" == "quiet" ]]; then
      echo "${count}"
    else
      echo "Total unique studies: ${count} [$where_clause]"
    fi
  }
  unique_studies_in_scope() {
    local database_name="$1"
    local output_mode="$2"
    local where_clause="WHERE m.skip='n'"  # Initial condition referencing migadmin table
    # local query="SELECT COUNT(DISTINCT s.styiuid) FROM studies s JOIN migadmin m ON s.styiuid = m.styiuid ${where_clause}"
    local query="SELECT COUNT(DISTINCT s.styiuid), SUM(ss.stysize)
                 FROM studies s
                 JOIN migadmin m ON s.styiuid = m.styiuid
                 JOIN studies_systems ss ON s.styiuid = ss.styiuid
                 JOIN systems sys ON ss.system_id = sys.system_id
                 ${where_clause} AND sys.role = 'source'"
    
    if [[ -n "$StartDate" ]]; then
      query+=" AND DATE(s.styDate) <= '$StartDate'"
      where_clause+=" AND DATE(s.styDate) <= '$StartDate'"
    fi
    
    if [[ -n "$StopDate" ]]; then
      query+=" AND DATE(s.styDate) >= '$StopDate'"
      where_clause+=" AND DATE(s.styDate) >= '$StopDate'"
    fi
    
    query+=";"
    local result=$("$MYSQL_BIN" -BN -u medsrv --database="${database_name}" -e "$query" -s -N)

    # Split the result into two variables: count and dataset_size
    local count=$(echo "$result" | awk '{print $1}')
    local dataset_size=$(echo "$result" | awk '{print $2}')

    if [[ "$output_mode" == "quiet" ]]; then
      echo "$count"
    else
      echo "Unique studies in-scope: $count ($(bytes_to_gb "$dataset_size")) [$where_clause]" 
    fi
  }
  unique_studies_sent() {
    local database_name="$1"
    local output_mode="$2"

    # Modified where clause to align with new table structure
    local where_clause="WHERE m.skip='n' AND m.verification IN('pending','passed') AND ss.role='source'"
    
    # Modified query to dynamically exclude target systems based on their role and include migadmin table for skip and verification
    # local query="
    #   SELECT COUNT(DISTINCT s.styiuid)
    #   FROM studies s
    #   JOIN migadmin m ON s.styiuid = m.styiuid
    #   JOIN studies_systems ss ON s.styiuid = ss.styiuid
    #   JOIN systems sys ON ss.system_id = sys.system_id
    #   WHERE m.skip != 'y'
    #     AND m.verification IN ('pending', 'passed')
    #     AND sys.role != 'target'
    # "

    local query="
      SELECT COUNT(DISTINCT s.styiuid), SUM(ss.stysize)
      FROM studies s
      JOIN migadmin m ON s.styiuid = m.styiuid
      JOIN studies_systems ss ON s.styiuid = ss.styiuid
      JOIN systems sys ON ss.system_id = sys.system_id
      WHERE m.skip != 'y'
        AND m.verification IN ('pending', 'passed')
        AND sys.role != 'target'
    "

    # Add date filters if StartDate or StopDate are provided
    if [[ -n "$StartDate" ]]; then
      query+=" AND DATE(s.styDate) <= '$StartDate'"
      where_clause+=" AND DATE(s.styDate) <= '$StartDate'"
    fi

    if [[ -n "$StopDate" ]]; then
      query+=" AND DATE(s.styDate) >= '$StopDate'"
      where_clause+=" AND DATE(s.styDate) >= '$StopDate'"
    fi

    # Finalize query
    query+=";"

    # Execute query to get both the count and summed stysize
    local result=$("${MYSQL_BIN}" -BN -u medsrv --database="${database_name}" -e "$query" -s -N)

    # Split the result into count and summed stysize
    # local count=$(echo "$result" | awk '{print $1}')
    local count=$(echo "$result" | cut -f1)
    # local dataset_size=$(echo "$result" | awk '{print $2}')
    local dataset_size=$(echo "$result" | cut -f2)
    local gb_size=$(bytes_to_gb "$dataset_size")

    # Calculate Total_InScope_Study_Size
    local total_query="
      SELECT SUM(ss.stysize)
      FROM studies s
      JOIN migadmin m ON s.styiuid = m.styiuid
      JOIN studies_systems ss ON s.styiuid = ss.styiuid
      JOIN systems sys ON ss.system_id = sys.system_id
      WHERE m.skip = 'n'
        AND sys.role = 'source'
    "

    # Execute query to get total in-scope study size
    local total_result=$("${MYSQL_BIN}" -BN -u medsrv --database="${database_name}" -e "$total_query" -s -N)
    local Total_InScope_Study_Size="$total_result"

    # Calculate percentage for dataset_size
    local dataset_percentage=$(calculate_percentage "$dataset_size" "$Total_InScope_Study_Size")
    local stycnt_percentage=$(calculate_percentage "$count" "$Total_InScope_Studies")

    # Decide the output based on the mode
    if [[ "$output_mode" == "quiet" ]]; then
      # echo "$count,${formatted_gb_size} GB"
      echo "$count"
    else
      # echo "Unique studies sent (unverified): $count ($gb_size [$dataset_percentage pct]) ($(calculate_percentage "$count" "$Total_InScope_Studies")) [$where_clause]"
      echo "Unique studies sent (unverified): $count ($stycnt_percentage) | $gb_size ($dataset_percentage) [$where_clause]"
    fi
  }
  unique_studies_migrated() {
    local database_name="$1"
    local output_mode="$2"
    # local query="SELECT COUNT(*) FROM studies WHERE skip!='y' AND verification='passed'"
    # Modified where clause to align with new table structure
    local where_clause="WHERE m.verification='passed'"
    
    # Modified query to include migadmin for verification
    # local query="
    #   SELECT COUNT(DISTINCT s.styiuid)
    #   FROM studies s
    #   JOIN migadmin m ON s.styiuid = m.styiuid
    #   WHERE m.verification = 'passed'
    # "

    local query="
      SELECT COUNT(DISTINCT s.styiuid), SUM(ss.stysize)
      FROM studies s
      JOIN migadmin m ON s.styiuid = m.styiuid
      JOIN studies_systems ss ON s.styiuid = ss.styiuid
      JOIN systems sys ON ss.system_id = sys.system_id
      WHERE m.verification = 'passed'
        AND sys.role = 'source'
    "

    # Add date filters if StartDate or StopDate are provided
    if [[ -n "$StartDate" ]]; then
      query+=" AND DATE(s.styDate) <= '$StartDate'"
      where_clause+=" AND DATE(s.styDate) <= '$StartDate'"
    fi

    if [[ -n "$StopDate" ]]; then
      query+=" AND DATE(s.styDate) >= '$StopDate'"
      where_clause+=" AND DATE(s.styDate) >= '$StopDate'"
    fi

    query+=";"
    
    # Read the count into a variable
    local result=$("${MYSQL_BIN}" -BN -u medsrv --database="${database_name}" -e "$query" -s -N)

    # Split the result into count and summed stysize
    local count=$(echo "$result" | cut -f1)
    local dataset_size=$(echo "$result" | cut -f2)
    local gb_size=$(bytes_to_gb "$dataset_size")

    # Calculate Total_InScope_Study_Size
    local total_query="
      SELECT SUM(ss.stysize)
      FROM studies s
      JOIN migadmin m ON s.styiuid = m.styiuid
      JOIN studies_systems ss ON s.styiuid = ss.styiuid
      JOIN systems sys ON ss.system_id = sys.system_id
      WHERE m.skip = 'n'
        AND sys.role = 'source'
    "

    # Execute query to get total in-scope study size
    local total_result=$("${MYSQL_BIN}" -BN -u medsrv --database="${database_name}" -e "$total_query" -s -N)
    local Total_InScope_Study_Size="$total_result"

    # Calculate percentage for dataset_size
    local dataset_percentage=$(calculate_percentage "$dataset_size" "$Total_InScope_Study_Size")
    local stycnt_percentage=$(calculate_percentage "$count" "$Total_InScope_Studies")

    # Decide the output based on the mode
    if [[ "$output_mode" == "quiet" ]]; then
      echo "$count"
    else
      # echo "Unique studies migrated (verified): $result ($gb_size GB [$dataset_percentage pct]) ($(calculate_percentage "$result" "$Total_InScope_Studies")) [$where_clause]"
      echo "Unique studies migrated (verified): $count ($stycnt_percentage) | $gb_size ($dataset_percentage) [$where_clause]"
    fi
  }
  unique_studies_pending() {
      local database_name="$1"
      local output_mode="${2:-verbose}"
      local sort_column=${SortColumn:-"s.styDate"}
      local sort_direction=${SortDirection:-"DESC"}

      # Validate the SortColumn and SortDirection using the external function
      read sort_column sort_direction <<< $(validate_sort_column "$sort_column" "$sort_direction")

      # Create a filename with a date-time stamp for storing the query results
      local filename="suids-pending_$(date "+%Y%m%d-%H%M%S").txt"
      local filename="${_STYLIST_DIR:lists}/$filename"

      # Define the shared WHERE clause
      local where_clause="WHERE m.skip='n' AND m.verification='pending' AND sys.role='source'"

      # Add date filters if StartDate or StopDate are provided
      if [[ -n "$StartDate" ]]; then
          where_clause+=" AND DATE(s.styDate) <= '$StartDate'"
      fi

      if [[ -n "$StopDate" ]]; then
          where_clause+=" AND DATE(s.styDate) >= '$StopDate'"
      fi

      # Construct the ORDER BY clause by combining columns and directions
      IFS=',' read -r -a sort_columns_array <<< "$sort_column"
      IFS=',' read -r -a sort_directions_array <<< "$sort_direction"

      local order_by_clause=""
      for i in "${!sort_columns_array[@]}"; do
          order_by_clause+="${sort_columns_array[$i]} ${sort_directions_array[$i]}, "
      done
      order_by_clause="${order_by_clause%, }"  # Remove trailing comma and space

      # First query: Write styiuid to file for pending studies, using the dynamic sorting
      local file_query="
      SELECT s.styiuid 
      FROM studies s
      JOIN migadmin m ON s.styiuid = m.styiuid
      JOIN studies_systems ss ON s.styiuid = ss.styiuid
      JOIN systems sys ON ss.system_id = sys.system_id
      $where_clause
      ORDER BY $order_by_clause;"  # Apply sorting based on migration.cfg values

      # Execute the first query and save the styiuid results to the file
      "$MYSQL_BIN" -BN -u medsrv --database="${database_name}" -e "$file_query" > "$filename"

      # Count the number of lines in the file
      local count=$(wc -l < "$filename")

      # Second query: Get the count and the sum of stysize for pending studies
      local size_query="
      SELECT COUNT(DISTINCT s.styiuid), IFNULL(SUM(ss.stysize), 0)
      FROM studies s
      JOIN migadmin m ON s.styiuid = m.styiuid
      JOIN studies_systems ss ON s.styiuid = ss.styiuid
      JOIN systems sys ON ss.system_id = sys.system_id
      $where_clause;"

      # Execute the second query to get the count and summed stysize
      local result=$("$MYSQL_BIN" -BN -u medsrv --database="${database_name}" -e "$size_query")

      # Split the result into count and summed stysize
      local dataset_size=$(echo "$result" | awk '{print $2}')

      # Convert dataset size from bytes to gigabytes
      local gb_size=$(bytes_to_gb "$dataset_size")

      # Calculate Total_InScope_Study_Size
      local total_size_query="
        SELECT SUM(ss.stysize)
        FROM studies s
        JOIN migadmin m ON s.styiuid = m.styiuid
        JOIN studies_systems ss ON s.styiuid = ss.styiuid
        JOIN systems sys ON ss.system_id = sys.system_id
        WHERE m.skip = 'n'
          AND sys.role = 'source'
      "
      local total_count_query="
        SELECT COUNT(DISTINCT s.styiuid)
        FROM studies s
        JOIN migadmin m ON s.styiuid = m.styiuid
        JOIN studies_systems ss ON s.styiuid = ss.styiuid
        JOIN systems sys ON ss.system_id = sys.system_id
        WHERE m.skip = 'n'
          AND sys.role = 'source'
      "

      # Execute query to get total in-scope study size
      local total_size_result=$("${MYSQL_BIN}" -BN -u medsrv --database="${database_name}" -e "$total_size_query" -s -N)
      local Total_InScope_Study_Size="$total_size_result"
      local total_count_result=$("${MYSQL_BIN}" -BN -u medsrv --database="${database_name}" -e "$total_count_query" -s -N)
      local Total_InScope_Studies="$total_count_result"

      # Calculate percentage for dataset_size
      local dataset_percentage=$(calculate_percentage "$dataset_size" "$Total_InScope_Study_Size")
      local stycnt_percentage=$(calculate_percentage "$count" "$Total_InScope_Studies")

      # Provide output to the user based on the chosen mode
      if [[ "$output_mode" == "quiet" ]]; then
          echo "$filename"
      else
          echo "Studies pending verification: $count ($stycnt_percentage) | $gb_size ($dataset_percentage) [$where_clause] (Out file: $filename)"
          # echo "file query:"
          # echo "$file_query"
      fi
  }
  unique_studies_wholly_missing() {
      local database_name="$1"
      local output_mode="${2:-verbose}"

      # Create a filename with a date-time stamp for storing the query results
      local filename="suids-fully-absent_$(date "+%Y%m%d-%H%M%S").txt"
      local filename="${_STYLIST_DIR:lists}/$filename"

      # Define the shared WHERE clause
      local where_clause="WHERE m.skip='n' AND m.verification='n/a' AND sys.role='source'"

      # Add date filters if StartDate or StopDate are provided
      if [[ -n "$StartDate" ]]; then
          where_clause+=" AND DATE(s.styDate) <= '$StartDate'"
      fi

      if [[ -n "$StopDate" ]]; then
          where_clause+=" AND DATE(s.styDate) >= '$StopDate'"
      fi

      # First query: Write styiuid to file for wholly missing studies
      local file_query="
      SELECT s.styiuid 
      FROM studies s 
      JOIN migadmin m ON s.styiuid = m.styiuid
      JOIN studies_systems ss ON s.styiuid = ss.styiuid
      JOIN systems sys ON ss.system_id = sys.system_id
      $where_clause;"

      # Execute the first query and save the styiuid results to the file
      "$MYSQL_BIN" -BN -u medsrv --database="${database_name}" -e "$file_query" > "$filename"

      # Count the number of lines in the file
      local count=$(wc -l < "$filename")

      # Second query
      local size_query="
      SELECT COUNT(DISTINCT s.styiuid), IFNULL(SUM(ss.stysize), 0)
      FROM studies s
      JOIN migadmin m ON s.styiuid = m.styiuid
      JOIN studies_systems ss ON s.styiuid = ss.styiuid
      JOIN systems sys ON ss.system_id = sys.system_id
      $where_clause;"

      # Execute the second query to get the count and summed stysize (if needed)
      local result=$("$MYSQL_BIN" -BN -u medsrv --database="${database_name}" -e "$size_query")

      # Split the result into count and summed stysize
      local count=$(echo "$result" | awk '{print $1}')
      local dataset_size=$(echo "$result" | awk '{print $2}')

      # Convert dataset size from bytes to gigabytes
      local gb_size=$(bytes_to_gb "$dataset_size")

      # Calculate Total_InScope_Study_Size
      local total_query="
        SELECT SUM(ss.stysize)
        FROM studies s
        JOIN migadmin m ON s.styiuid = m.styiuid
        JOIN studies_systems ss ON s.styiuid = ss.styiuid
        JOIN systems sys ON ss.system_id = sys.system_id
        WHERE m.skip = 'n'
          AND sys.role = 'source'
      "

      # Execute query to get total in-scope study size
      local total_result=$("${MYSQL_BIN}" -BN -u medsrv --database="${database_name}" -e "$total_query" -s -N)
      local Total_InScope_Study_Size="$total_result"

      # Calculate percentage for dataset_size
      local dataset_percentage=$(calculate_percentage "$dataset_size" "$Total_InScope_Study_Size")

      # Provide output to the user based on the chosen mode
      if [[ "$output_mode" == "quiet" ]]; then
          echo "$filename"
      else
          echo "Fully Absent Total records: $count () | $gb_size ($dataset_percentage) [$where_clause] (Out file: $filename)"
      fi
  }
  unique_studies_to_skip() {
    local database_name="$1"
    local output_mode="$2"
    local where_clause="WHERE m.skip='y' AND m.verification!='passed'"
    local query="
      SELECT COUNT(DISTINCT s.styiuid)
      FROM studies s
      JOIN migadmin m ON s.styiuid = m.styiuid
      ${where_clause}"

    # Add date filters if StartDate or StopDate are provided
    if [[ -n "$StartDate" ]]; then
      query+=" AND DATE(s.styDate) <= '$StartDate'"
      where_clause+=" AND DATE(s.styDate) <= '$StartDate'"
    fi

    if [[ -n "$StopDate" ]]; then
      query+=" AND DATE(s.styDate) >= '$StopDate'"
      where_clause+=" AND DATE(s.styDate) >= '$StopDate'"
    fi

    query+=";"
    
    local result=$("$MYSQL_BIN" -BN -u medsrv --database="${database_name}" -e "$query" -s -N)
    
    if [[ "$output_mode" == "quiet" ]]; then
      echo "$result"
    else
      echo "Studies set to skip: $result [$where_clause]"
    fi
  }
  unique_studies_to_migrate_OG() {
      local database_name="$1"
      local output_mode="${2:-verbose}"
      local count
      local label="Studies to migrate:"
      
      # Create a filename with a date-time stamp for storing the query results
      local filename="suids-to-migrate_$(date "+%Y%m%d-%H%M%S").txt"
      local filename="${_STYLIST_DIR:lists}/$filename"
      local instruction="Kick-off img xfer: ./MigTransfer.sh -L ${filename}"
      
      # Define the shared WHERE clause
      local where_clause="WHERE m.skip='n' AND m.verification='n/a' AND sys.role='source'"

      # Add date filters if StartDate or StopDate are provided
      if [[ -n "$StartDate" ]]; then
          where_clause+=" AND DATE(s.styDate) <= '$StartDate'"
      fi

      if [[ -n "$StopDate" ]]; then
          where_clause+=" AND DATE(s.styDate) >= '$StopDate'"
      fi

      # First query: Write styiuid to file for studies to migrate
      local file_query="
      SELECT s.styiuid 
      FROM studies s 
      JOIN migadmin m ON s.styiuid = m.styiuid
      JOIN studies_systems ss ON s.styiuid = ss.styiuid
      JOIN systems sys ON ss.system_id = sys.system_id
      $where_clause;"

      # Execute the first query and save the styiuid results to the file
      "$MYSQL_BIN" -BN -u medsrv --database="${database_name}" -e "$file_query" > "$filename"

      # Calculate the number of records
      count=$(wc -l < "$filename")

      # Second query: Get the count and the sum of stysize for studies to migrate
      local size_query="
      SELECT COUNT(DISTINCT s.styiuid), IFNULL(SUM(ss.stysize), 0)
      FROM studies s
      JOIN migadmin m ON s.styiuid = m.styiuid
      JOIN studies_systems ss ON s.styiuid = ss.styiuid
      JOIN systems sys ON ss.system_id = sys.system_id
      $where_clause;"

      # Execute the second query to get the count and summed stysize
      local result=$("$MYSQL_BIN" -BN -u medsrv --database="${database_name}" -e "$size_query")

      # Split the result into count and summed stysize
      local total_count=$(echo "$result" | awk '{print $1}')
      local dataset_size=$(echo "$result" | awk '{print $2}')

      # Convert dataset size from bytes to gigabytes
      local gb_size=$(bytes_to_gb "$dataset_size")

      # Calculate Total_InScope_Study_Size
      local total_query="
        SELECT SUM(ss.stysize)
        FROM studies s
        JOIN migadmin m ON s.styiuid = m.styiuid
        JOIN studies_systems ss ON s.styiuid = ss.styiuid
        JOIN systems sys ON ss.system_id = sys.system_id
        WHERE m.skip = 'n'
          AND sys.role = 'source'
      "

      # Execute query to get total in-scope study size
      local total_result=$("${MYSQL_BIN}" -BN -u medsrv --database="${database_name}" -e "$total_query" -s -N)
      local Total_InScope_Study_Size="$total_result"

      # Calculate percentage for dataset_size
      local dataset_percentage=$(calculate_percentage "$dataset_size" "$Total_InScope_Study_Size")

      # Log output to migrate.COMMAND regardless of the output mode
      {
          echo "Generated file: $filename"
          echo "Total records: $count ($gb_size GB)"
          echo "To migrate the studies listed in the file, run:"
          echo "./MigTransfer.sh -L $(pwd)/$filename"
          echo "Optionally, include the --whatif flag to perform a dry run:"
          echo "./MigTransfer.sh -L $(pwd)/$filename --whatif"
      } > migrate.COMMAND

      # Provide output to the user based on the chosen mode
      if [[ "$output_mode" == "quiet" ]]; then
          echo "$filename"
      else
          echo -e "${label} ${total_count} (pct of total) | $gb_size ($dataset_percentage) [$where_clause]\n${instruction}"
      fi
  }
  unique_studies_to_migrate() {
      local database_name="$1"
      local output_mode="${2:-verbose}"
      local count
      local label="Studies to migrate:"

      # Create a filename with a date-time stamp for storing the query results
      local filename="suids-to-migrate_$(date "+%Y%m%d-%H%M%S").txt"
      local filename="${_STYLIST_DIR:lists}/$filename"
      local instruction="Kick-off img xfer: ./MigTransfer.sh -L ${filename}"

      # Define the shared WHERE clause
      local where_clause="WHERE m.skip='n' AND m.verification='n/a' AND sys.role='source'"

      # Add date filters if StartDate or StopDate are provided
      if [[ -n "$StartDate" ]]; then
          where_clause+=" AND DATE(s.styDate) <= '$StartDate'"
      fi
      if [[ -n "$StopDate" ]]; then
          where_clause+=" AND DATE(s.styDate) >= '$StopDate'"
      fi

      # Sorting (mirrors unique_studies_pending)
      local sort_column=${SortColumn:-"s.styDate"}
      local sort_direction=${SortDirection:-"DESC"}
      read sort_column sort_direction <<< "$(validate_sort_column "$sort_column" "$sort_direction")"

      # Build ORDER BY (supports multi-column, comma-separated)
      IFS=',' read -r -a sort_columns_array <<< "$sort_column"
      IFS=',' read -r -a sort_directions_array <<< "$sort_direction"

      local order_by_clause=""
      for i in "${!sort_columns_array[@]}"; do
          order_by_clause+="${sort_columns_array[$i]} ${sort_directions_array[$i]}, "
      done
      order_by_clause="${order_by_clause%, }"

      # First query: Write styiuid to file for studies to migrate (with ORDER BY)
      local file_query="
      SELECT s.styiuid
      FROM studies s
      JOIN migadmin m ON s.styiuid = m.styiuid
      JOIN studies_systems ss ON s.styiuid = ss.styiuid
      JOIN systems sys ON ss.system_id = sys.system_id
      $where_clause
      ORDER BY $order_by_clause;"

      # Execute the first query and save the styiuid results to the file
      "$MYSQL_BIN" -BN -u medsrv --database="${database_name}" -e "$file_query" > "$filename"

      # Calculate the number of records
      count=$(wc -l < "$filename")

      # Second query: Get the count and the sum of stysize for studies to migrate
      local size_query="
      SELECT COUNT(DISTINCT s.styiuid), IFNULL(SUM(ss.stysize), 0)
      FROM studies s
      JOIN migadmin m ON s.styiuid = m.styiuid
      JOIN studies_systems ss ON s.styiuid = ss.styiuid
      JOIN systems sys ON ss.system_id = sys.system_id
      $where_clause;"

      # Execute the second query to get the count and summed stysize
      local result
      result=$("$MYSQL_BIN" -BN -u medsrv --database="${database_name}" -e "$size_query")

      # Split the result into count and summed stysize
      local total_count dataset_size
      total_count=$(echo "$result" | awk '{print $1}')
      dataset_size=$(echo "$result" | awk '{print $2}')

      # Convert dataset size from bytes to gigabytes
      local gb_size
      gb_size=$(bytes_to_gb "$dataset_size")

      # Calculate Total_InScope_Study_Size
      local total_query="
        SELECT SUM(ss.stysize)
        FROM studies s
        JOIN migadmin m ON s.styiuid = m.styiuid
        JOIN studies_systems ss ON s.styiuid = ss.styiuid
        JOIN systems sys ON ss.system_id = sys.system_id
        WHERE m.skip = 'n'
          AND sys.role = 'source'
      "

      # Execute query to get total in-scope study size
      local total_result
      total_result=$("${MYSQL_BIN}" -BN -u medsrv --database="${database_name}" -e "$total_query" -s -N)
      local Total_InScope_Study_Size="$total_result"

      # Calculate percentage for dataset_size
      local dataset_percentage
      dataset_percentage=$(calculate_percentage "$dataset_size" "$Total_InScope_Study_Size")

      # Log output to migrate.COMMAND regardless of the output mode
      {
          echo "Generated file: $filename"
          echo "Total records: $count ($gb_size GB)"
          echo "To migrate the studies listed in the file, run:"
          echo "./MigTransfer.sh -L $(pwd)/$filename"
          echo "Optionally, include the --whatif flag to perform a dry run:"
          echo "./MigTransfer.sh -L $(pwd)/$filename --whatif"
      } > migrate.COMMAND

      # Provide output to the user based on the chosen mode
      if [[ "$output_mode" == "quiet" ]]; then
          echo "$filename"
      else
          echo -e "${label} ${total_count} (pct of total) | $gb_size ($dataset_percentage) [$where_clause]\n${instruction}"
      fi
  }
  Migration_Study_List_OG(){
      local database_name="$1"
      local output_mode="${2:-verbose}"
      local _table="studies_systems"
      local where_clause="WHERE sys.role='source'"
      local filename="Migration-Study-List_$(date "+%Y%m%d-%H%M%S").txt"
      # local header="PATIENT_ID|PATIENT_DOB|ACCESSION_NUMBER|STUDY_DESC|OBJECT_COUNT|STUDY_DATE|STUDY_TIME|MODALITY_CODE|MIGRATED|REASON|STUDYUID"
      local header="PATIENT_ID\tPATIENT_DOB\tACCESSION\tSTUDY_DESC\tOBJECTS\tSTUDY_DATE\tSTUDY_TIME\tMODALITY\tVERIFICATION\tSKIP\tSKIP_REASON\tSTUDYUID"
      
      # THEDATE for V7: IFNULL(CONCAT(SUBSTRING(d.THEDATE, 1, 4), '-', SUBSTRING(d.THEDATE, 5, 2), '-', SUBSTRING(d.THEDATE, 7, 2)), '') AS STUDY_DATE,
      # THETIME for V7: CONCAT(LPAD(FLOOR(d.THETIME / 10000), 2, '0'), ':', LPAD(FLOOR((d.THETIME % 10000) / 100), 2, '0'), ':', LPAD(FLOOR(d.THETIME % 100), 2, '0')) AS STUDY_TIME_FORMATTED,
      # IFNULL(CONCAT(SUBSTRING(s.PBDATE, 1, 4), '-', SUBSTRING(s.PBDATE, 5, 2), '-', SUBSTRING(s.PBDATE, 7, 2)), '') AS PATIENT_DOB,
      local query="
          SELECT
              s.PID AS PATIENT_ID,
              s.PBDATE AS PATIENT_DOB,
              s.ACCNO AS ACCESSION_NUMBER,
              s.STYDESCR AS STUDY_DESC,
              ss.numofobj AS OBJECT_COUNT,
              DATE(s.styDate) AS STUDY_DATE,
              TIME(s.styDate) AS STUDY_TIME,
              s.MODALITY AS MODALITY_CODE,
              m.verification AS VERIFICATION,
              m.skip AS SKIP,
              m.skip_reason AS SKIP_REASON,
              s.STYIUID AS STUDYUID
          FROM $database_name.$_table ss
          JOIN systems sys ON ss.system_id = sys.system_id
          JOIN studies s ON ss.styiuid = s.styiuid
          JOIN migadmin m ON s.styiuid = m.styiuid
          $where_clause"

      # # Add date filters if StartDate or StopDate are provided
      # if [[ -n "$StartDate" ]]; then
      #     # FIXME: Need a dynamic way to handle the differences in date fields between V7 & V8
      #     #        In V7, the date field is STYDATE and is a char(10) for dates looking like 'YYYYMMDD'. the time field is STYTIME and is an char(16) for times looking like 'HHMMSS' to 'HHMMSS.FFFFFF'
      #     #        In V8, the date and time fields are combined into one field called STYDATETIME and is a datetime field.
      #     query+=" AND DATE(s.styDate) <= '$StartDate'"
      # fi

      # if [[ -n "$StopDate" ]]; then
      #     query+=" AND DATE(s.styDate) >= '$StopDate'"
      # fi
      
      query+="ORDER BY (SKIP_REASON='') DESC, styDate DESC"
      query+=";"

      # Execute the query and save the output to a file
      echo -e "$header" > "$filename"
      "$MYSQL_BIN" -BN -u medsrv --database="${database_name}" -e "$query" | awk -F'\t' -v OFS='|' '{print $0}' >> "$filename"

      # Calculate the number of records
      local count=$(wc -l < "$filename")

      # Log output to migrate.COMMAND regardless of the output mode
      echo "Migration Study Spreadsheet: $count [$where_clause] (Out file: $filename)"

      # Provide output to the user based on the chosen mode
      if [[ "$output_mode" == "quiet" ]]; then
          echo "$filename"
      fi
  }
  Migration_Study_List(){
    local database_name="$1"
    local output_mode="${2:-verbose}"
    local view_name="study_details"
    local filename="Migration-Study-List_$(date "+%Y%m%d-%H%M%S").txt"
    local header="PATIENT_ID\tACCESSION\tSTUDY_DESC\tOBJECTS\tSTUDY_DATE\tSTUDY_TIME\tMODALITY\tVERIFICATION\tSKIP\tSKIP_REASON\tSTUDYUID\tSTUDY_SOURCE"

    # Query using the view
    # Add this for exports to HD:
    # REPLACE(export_location, '/mnt/case_78568', '') AS EXPORT_LOCATION,
    local query="
        SELECT
            REPLACE(REPLACE(REPLACE(REPLACE(pid, '\r', ''), '\n', ''), '\t', ''), '\"', '') AS PATIENT_ID,
            REPLACE(REPLACE(REPLACE(REPLACE(accno, '\r', ''), '\n', ''), '\t', ''), '\"', '') AS ACCESSION,
            REPLACE(REPLACE(REPLACE(REPLACE(styDescr, '\r', ''), '\n', ''), '\t', ''), '\"', '') AS STUDY_DESC,
            numofobj AS OBJECTS,
            DATE(styDate) AS STUDY_DATE,
            TIME(styDate) AS STUDY_TIME,
            REPLACE(REPLACE(REPLACE(REPLACE(modality, '\r', ''), '\n', ''), '\t', ''), '\"', '') AS MODALITY,
            REPLACE(REPLACE(REPLACE(REPLACE(verification, '\r', ''), '\n', ''), '\t', ''), '\"', '') AS VERIFICATION,
            skip AS SKIP,
            REPLACE(REPLACE(REPLACE(REPLACE(skip_reason, '\r', ''), '\n', ''), '\t', ''), '\"', '') AS SKIP_REASON,
            REPLACE(REPLACE(REPLACE(REPLACE(styiuid, '\r', ''), '\n', ''), '\t', ''), '\"', '') AS STUDYUID,
            REPLACE(REPLACE(REPLACE(REPLACE(study_source, '\r', ''), '\n', ''), '\t', ''), '\"', '') AS STUDY_SOURCE
        FROM $view_name;
    "

    # Write header and execute the query
    {
        echo -e "$header"
        "$MYSQL_BIN" -BN -u medsrv --database="${database_name}" -e "$query"
    } | awk -F'\t' -v OFS='|' '{print $0}' > "$filename"

    # Log and handle output
    local count=$(wc -l < "$filename")
    echo "Migration Study Spreadsheet: $count (Out file: $filename)"
    [[ "$output_mode" == "quiet" ]] && echo "$filename"
  }

# MAIN
main() {
    if [[ "$#" -eq 0 ]]; then
        echo "No arguments provided."
        usage
        exit 1
    fi
    
    initialize_environment
    parse_args "$@"
}

main "$@"
