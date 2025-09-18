#!/bin/bash
#shellcheck disable=SC1090,SC1091,SC2155,SC2034

Usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -s, --studyid ID       Specify the study ID to process."
    echo "  -f, --file FILE        Specify a file with a list of study IDs to process."
    echo "  -b, --batch            Run script in batch mode without interactive inputs."
    echo "  -v, --verbose          Run script in verbose mode to get detailed logs."
    echo "      --no-auto-resolve  Disable automatic resolution of unregistered objects."
    echo "  -h, --help             Display this help message."
}
initialize_environment() {
    BatchMode="${BatchMode:-false}"
    if ! . universal.lib; then
        echo "Required library (universal.lib) not found. Exiting..."; exit 1
    else
        initialize_script_variables "MigResearch.sh"  # Sets: _SCRIPT_NAME, _SCRIPT_CFG, _SCRIPT_LOG
        initialize_script_environment              # Verifies $USER, Verifies/Sources .default.cfg & migration.cfg
        verify_env || exit 1                       # Ensure all ${env_vars[@]} are set & not empty.
    fi
}

# STUDY RESEARCH FUNCTIONS
  getStudyInfo() {
      local suid="$1"
      local skip_print_info="${2:-false}"
      load_system_details
      RequiredVariables "suid" "Target_IP" "Source_IP" >/dev/null
      local system_ip=""

      if [[ "$Target_Proximity" == "remote" ]]; then
        system_ip="$Target_IP"
      else
        system_ip="$Source_IP"
      fi

      getMigDbInfo "$suid"
      getSourceInfo "$suid" "$Source_IP"
      getTargetInfo "$suid" "$Target_IP"

      compareFSObjects "$suid" "$Target_IP"
      compareDBObjects "$suid" "$Target_IP"

            # If all missing objects are obsolete, update status and print info
            if allMissingObjectsObsolete; then
                updateMigAdminStatus "$suid"
                printInfo

            # New case: Filesystems show no missing objects but DB shows missing entries
            # This indicates files exist on target FS but are not registered in DICOM DB.
            # Automatically mark migration verification as passed and append note.
            elif [[ ${NumofObjMissing_FS:-0} -eq 0 && ${NumofObjMissing_DB:-0} -gt 0 ]]; then
                # Files exist on target FS but DB entries missing (unregistered objects)
                # Only auto-resolve if the toggle is enabled
                if [[ "${AUTO_RESOLVE_UNREGISTERED:-true}" == "true" ]]; then
                    updateMigAdminStatus "$suid" "unregistered objects"
                else
                    echo "AUTO_RESOLVE_UNREGISTERED is disabled; skipping auto-update for SUID: $suid"
                fi
                # Still print info so operator has visibility
                if [[ "$skip_print_info" != "true" ]]; then
                    printInfo
                fi

            elif [[ "$skip_print_info" != "true" ]]; then
                printInfo
            fi
  }
  getStudyInfo_OG() {
      local suid="$1"
      load_system_details
      RequiredVariables "suid" "Target_IP" "Source_IP" >/dev/null
      local system_ip=""

      if [[ "$Target_Proximity" == "remote" ]]; then
        system_ip="$Target_IP"
      else
        system_ip="$Source_IP"
      fi

      getMigDbInfo "$suid"
      getSourceInfo "$suid" "$Source_IP"
      getTargetInfo "$suid" "$Target_IP"

      compareFSObjects "$suid" "$Target_IP"
      compareDBObjects "$suid" "$Target_IP"

      if allMissingObjectsObsolete; then
        updateMigAdminStatus "$suid"
      else
        printInfo
      fi

  }
  getSourceInfo() {
      local suid="$1"
      local source_ip="$2"

      if [[ "$Source_Proximity" == "local" ]]; then
          Dcstudy_D_Source="$(sql.sh "SELECT Dcstudy_D FROM Dcstudy WHERE STYIUID='$suid'" -N 2>/dev/null)"
          StudyDir_Source="$(/home/medsrv/component/repositoryhandler/scripts/locateStudy.sh -d "$suid" 2>/dev/null)"
          Storestate_ProcessMode_Source="$(grep -is ProcessMode "$StudyDir_Source/.info/storestate.rec" | cut -d'=' -f2)"
          NumofObj_DB_Source="$(sql.sh "SELECT NUMOFOBJ FROM Dcstudy WHERE STYIUID='$suid'" -N)"
          NumofImg_DB_Source="$(sql.sh "SELECT NUMOFIMG FROM Dcstudy WHERE STYIUID='$suid'" -N)"
          NumofObj_FS_Source="$(ls "$StudyDir_Source" 2>/dev/null | wc -l)"
          # ObsoleteStatus_Source=$(getObsoleteStatus "local" "$StudyDir_Source" "")
          ObsoleteStatus_Source=$(getDicomTagValue "local" "$StudyDir_Source" "" "f215,1045")
          PBStatus_Source=$(getDicomTagValue "local" "$StudyDir_Source" "" "f215,1002")
          ObsoleteSOPS_Source=$(getReferencedSOPInstanceUIDs "local" "$StudyDir_Source" "")
          PBLastModifiedDate_Source=$(getDicomTagValue "local" "$StudyDir_Source" "" "f215,1015")
      else
          Dcstudy_D_Source="$(ssh -n "$source_ip" "sql.sh \"SELECT Dcstudy_D FROM Dcstudy WHERE STYIUID='$suid'\" -N" 2>/dev/null)"
          StudyDir_Source="$(ssh -n "$source_ip" "/home/medsrv/component/repositoryhandler/scripts/locateStudy.sh -d $suid" 2>/dev/null)"
          Storestate_ProcessMode_Source="$(ssh -n "$source_ip" "grep -is ProcessMode \"$StudyDir_Source/.info/storestate.rec\"" | cut -d'=' -f2)"
          NumofObj_DB_Source="$(ssh -n "$source_ip" "sql.sh \"SELECT NUMOFOBJ FROM Dcstudy WHERE STYIUID='$suid'\" -N" 2>/dev/null)"
          NumofImg_DB_Source="$(ssh -n "$source_ip" "sql.sh \"SELECT NUMOFIMG FROM Dcstudy WHERE STYIUID='$suid'\" -N" 2>/dev/null)"
          NumofObj_FS_Source="$(ssh -n "$source_ip" "ls \"$StudyDir_Source\" 2>/dev/null" | wc -l)"
          # ObsoleteStatus_Source=$(getObsoleteStatus "remote" "$StudyDir_Source" "$source_ip")
          ObsoleteStatus_Source=$(getDicomTagValue "remote" "$StudyDir_Source" "$source_ip" "f215,1045")
          PBStatus_Source=$(getDicomTagValue "remote" "$StudyDir_Source" "$source_ip" "f215,1002")
          ObsoleteSOPS_Source=$(getReferencedSOPInstanceUIDs "remote" "$StudyDir_Source" "$source_ip")
          PBLastModifiedDate_Source=$(getDicomTagValue "remote" "$StudyDir_Source" "$source_ip" "f215,1015")
      fi
      executeVerboseTasks "$source_ip" "$suid" "$Source_Proximity" "Source"
  }
  getTargetInfo() {
      local suid="$1"
      local target_ip="$2"

      if [[ "$Target_Proximity" == "local" ]]; then
          Dcstudy_D_Target="$(sql.sh "SELECT Dcstudy_D FROM Dcstudy WHERE STYIUID='$suid'" -N 2>/dev/null)"
          StudyDir_Target="$(/home/medsrv/component/repositoryhandler/scripts/locateStudy.sh -d "$suid" 2>/dev/null)"
          Storestate_ProcessMode_Target="$(grep -is ProcessMode "$StudyDir_Target/.info/storestate.rec" | cut -d'=' -f2)"
          NumofObj_DB_Target="$(sql.sh "SELECT NUMOFOBJ FROM Dcstudy WHERE STYIUID='$suid'" -N)"
          NumofImg_DB_Target="$(sql.sh "SELECT NUMOFIMG FROM Dcstudy WHERE STYIUID='$suid'" -N)"
          NumofObj_FS_Target="$(ls "$StudyDir_Target" 2>/dev/null | wc -l)"
          # ObsoleteStatus_Target=$(getObsoleteStatus "local" "$StudyDir_Target" "")
          ObsoleteStatus_Target=$(getDicomTagValue "local" "$StudyDir_Target" "" "f215,1045")
          PBStatus_Target=$(getDicomTagValue "local" "$StudyDir_Target" "" "f215,1002")
          ObsoleteSOPS_Target=$(getReferencedSOPInstanceUIDs "local" "$StudyDir_Target" "")
          PBLastModifiedDate_Target=$(getDicomTagValue "local" "$StudyDir_Target" "" "f215,1015")
      else
          Dcstudy_D_Target="$(ssh -n "$target_ip" "sql.sh \"SELECT Dcstudy_D FROM Dcstudy WHERE STYIUID='$suid'\" -N" 2>/dev/null)"
          StudyDir_Target="$(ssh -n "$target_ip" "/home/medsrv/component/repositoryhandler/scripts/locateStudy.sh -d $suid" 2>/dev/null)"
          Storestate_ProcessMode_Target="$(ssh -n "$target_ip" "grep -is ProcessMode \"$StudyDir_Target/.info/storestate.rec\"" | cut -d'=' -f2)"
          NumofObj_DB_Target="$(ssh -n "$target_ip" "sql.sh \"SELECT NUMOFOBJ FROM Dcstudy WHERE STYIUID='$suid'\" -N" 2>/dev/null)"
          NumofImg_DB_Target="$(ssh -n "$target_ip" "sql.sh \"SELECT NUMOFIMG FROM Dcstudy WHERE STYIUID='$suid'\" -N" 2>/dev/null)"
          NumofObj_FS_Target="$(ssh -n "$target_ip" "ls \"$StudyDir_Target\" 2>/dev/null" | wc -l)"
          # ObsoleteStatus_Target=$(getObsoleteStatus "remote" "$StudyDir_Target" "$target_ip")
          ObsoleteStatus_Target=$(getDicomTagValue "remote" "$StudyDir_Target" "$target_ip" "f215,1045")
          PBStatus_Target=$(getDicomTagValue "remote" "$StudyDir_Target" "$target_ip" "f215,1002")
          ObsoleteSOPS_Target=$(getReferencedSOPInstanceUIDs "remote" "$StudyDir_Target" "$target_ip")
          PBLastModifiedDate_Target=$(getDicomTagValue "remote" "$StudyDir_Target" "$target_ip" "f215,1015")
      fi
      executeVerboseTasks "$target_ip" "$suid" "$Target_Proximity" "Target"
  }
  executeVerboseTasks() {
      local system_ip="$1"
      local suid="$2"
      local proximity="$3"
      local label="$4"
      if [ "$verbose" = "v" ]; then
          local task_types=("VarLock" "TMP1" "TMP2" "cpuQ" "netQ" "TaskQ_Sched" "TaskQ_Retry" "TaskQ_Failed" "DB_Q")
          for task in "${task_types[@]}"; do
              if [[ "$proximity" == "local" ]]; then
                  eval "NumofTasks_${task}_${label}=\$(find /home/medsrv/var/${task,,} -type f 2>/dev/null | xargs grep -il \"$suid\" 2>/dev/null | wc -l)"
              else
                  eval "NumofTasks_${task}_${label}=\$(ssh -n \"$system_ip\" 'find /home/medsrv/var/${task,,} -type f 2>/dev/null | xargs grep -il \"$suid\" 2>/dev/null' | wc -l)"
              fi
          done
      fi
  }
  compareFSObjects() {
      local suid="$1"
      local SourceObjects_FS=""
      local TargetObjects_FS=""

      if [[ "$Source_Proximity" == "local" ]]; then
          SourceObjects_FS=$(ls "$StudyDir_Source" 2>/dev/null)
      else
          SourceObjects_FS=$(ssh -n "$Source_IP" "ls \"$StudyDir_Source\" 2>/dev/null")
      fi

      if [[ "$Target_Proximity" == "local" ]]; then
          TargetObjects_FS=$(ls "$StudyDir_Target" 2>/dev/null)
      else
          TargetObjects_FS=$(ssh -n "$Target_IP" "ls \"$StudyDir_Target\" 2>/dev/null")
      fi

      # Get the difference between source and target objects
      local result="$(comm -23 <(echo "$SourceObjects_FS" | sort) <(echo "$TargetObjects_FS" | sort))"

      # Initialize Result_FS as an array
      Result_FS=()

      # Check if result is empty
      if [[ -z "$result" ]]; then
          NumofObjMissing_FS=0
      else
          # Convert result into an array
          while IFS= read -r line; do
              Result_FS+=("$line")
          done <<< "$result"
          NumofObjMissing_FS=${#Result_FS[@]}
      fi
  }
  compareDBObjects() {
      local suid="$1"

      if [[ "$Source_Proximity" == "local" ]]; then
          SourceObjects_DB=$(sql.sh "SELECT FNAME FROM Dcobject WHERE STYIUID='$suid'" -N)
      else
          SourceObjects_DB=$(ssh -n "$Source_IP" "sql.sh \"SELECT FNAME FROM Dcobject WHERE STYIUID='$suid'\" -N")
      fi

      if [[ "$Target_Proximity" == "local" ]]; then
          TargetObjects_DB=$(sql.sh "SELECT FNAME FROM Dcobject WHERE STYIUID='$suid'" -N)
      else
          TargetObjects_DB=$(ssh -n "$Target_IP" "sql.sh \"SELECT FNAME FROM Dcobject WHERE STYIUID='$suid'\" -N")
      fi

      local result=$(comm -23 <(echo "$SourceObjects_DB" | sort) <(echo "$TargetObjects_DB" | sort))
      
      # Check if result is empty before counting lines
      if [[ -z "$result" ]]; then
          NumofObjMissing_DB=0
      else
          NumofObjMissing_DB=$(printf "%s\n" "$result" | wc -l)
      fi

      Result_DB="$result"
  }
  getMigDbInfo() {
      suid="$1"
      # Query each column individually from the studies table.
      GMIstyDate=$("$MYSQL_BIN" -BN -u medsrv --database="${database_name}" -e "SELECT styDate FROM studies WHERE styiuid='$suid';")
      GMImodality=$("$MYSQL_BIN" -BN -u medsrv --database="${database_name}" -e "SELECT modality FROM studies WHERE styiuid='$suid';")

      # Query from the studies_systems table.
      # GMInumofobj=$("$MYSQL_BIN" -BN -u medsrv --database="${database_name}" -e "SELECT numofobj FROM studies_systems WHERE styiuid='$suid';")
      GMInumofobj="N/A"
      GMInumofimg="N/A"

      # Query each column individually from the migadmin table.
      GMIcomment=$("$MYSQL_BIN" -BN -u medsrv --database="${database_name}" -e "SELECT comment FROM migadmin WHERE styiuid='$suid';")
      GMIskip=$("$MYSQL_BIN" -BN -u medsrv --database="${database_name}" -e "SELECT skip FROM migadmin WHERE styiuid='$suid';")
      GMIskip_reason=$("$MYSQL_BIN" -BN -u medsrv --database="${database_name}" -e "SELECT skip_reason FROM migadmin WHERE styiuid='$suid';")
      GMIverification=$("$MYSQL_BIN" -BN -u medsrv --database="${database_name}" -e "SELECT verification FROM migadmin WHERE styiuid='$suid';")
  }
  getDicomTagValue() {
    # Function to retrieve the value of a specified DICOM tag from all PbR files in a directory
    # To fetch ReferencedSOPInstanceUIDs (0008,1155)
    #   getDicomTagValue "local" "/path/to/stydir" "" "0008,1155"
    # To fetch PBStatus (f215,1002)
    #   getDicomTagValue "remote" "/path/to/stydir" "192.168.1.100" "f215,1002"
    local proximity="$1"
    local stydir="$2"
    local system_ip="$3"
    local dicom_tag="$4"
    local tag_values=""
    local dicom_files=()

    if [[ -z "$dicom_tag" ]]; then
        echo "Error: No DICOM tag provided."
        return 1
    fi

    if [[ "$proximity" == "local" ]]; then
        # Find all PbR* files in the local directory
        mapfile -t dicom_files < <(find "$stydir" -type f -name 'PbR*' 2>/dev/null)
        
        if [[ ${#dicom_files[@]} -eq 0 ]]; then
            echo "N/A"
            return 1
        fi
        
        # Loop through all found files and accumulate tag values
        for dicom_file in "${dicom_files[@]}"; do
            local value=$(/home/medsrv/component/dicom/bin/dcmdump "$dicom_file" | grep -Po "(?<=\\($dicom_tag\\) [A-Z]{2} \\[)[^\\]]+")
            tag_values+="$value"$'\n'
        done
    else
        # Find all PbR* files in the remote directory
        mapfile -t dicom_files < <(ssh -n "$system_ip" "find \"$stydir\" -type f -name 'PbR*' 2>/dev/null")
        
        if [[ ${#dicom_files[@]} -eq 0 ]]; then
            echo "N/A"
            return 1
        fi
        
        # Loop through all found files and accumulate tag values
        for dicom_file in "${dicom_files[@]}"; do
            local value=$(ssh -n "$system_ip" "/home/medsrv/component/dicom/bin/dcmdump \"$dicom_file\"" | grep -Po "(?<=\\($dicom_tag\\) [A-Z]{2} \\[)[^\\]]+")
            tag_values+="$value"$'\n'
        done
    fi

    echo "$tag_values"
  }
  getObsoleteStatus() {
      # Function to retrieve ObsoleteStatus (f215,1045) value from a DICOM file
      # local suid="$1"
      local proximity="$1"
      local stydir="$2"
      local system_ip="$3"
      local obsolete_status=""
      local dicom_file=""  # This will store the path to the PbR* file

      if [[ "$proximity" == "local" ]]; then
          # Find the PbR* file in the local directory
          dicom_file=$(find "$stydir" -type f -name 'PbR*' | head -n 1)
          if [[ -z "$dicom_file" ]]; then
              echo "N/A"
              return 1
          fi
          obsolete_status=$(/home/medsrv/component/dicom/bin/dcmdump "$dicom_file" | grep -Po '(?<=\(f215,1045\) CS \[)[^\]]+')
      else
          # Find the PbR* file in the remote directory
          dicom_file=$(ssh -n "$system_ip" "find \"$stydir\" -type f -name 'PbR*' | head -n 1")
          if [[ -z "$dicom_file" ]]; then
              echo "N/A"
              return 1
          fi
          obsolete_status=$(ssh -n "$system_ip" "/home/medsrv/component/dicom/bin/dcmdump \"$dicom_file\"" | grep -Po '(?<=\(f215,1045\) CS \[)[^\]]+')
      fi

      echo "$obsolete_status"
  }
  getReferencedSOPInstanceUIDs() {
      # Function to retrieve each ReferencedSOPInstanceUID (0008,1155) from all PbR files in a directory
      local proximity="$1"
      local stydir="$2"
      local system_ip="$3"
      local referenced_sop_instance_uids=""
      local dicom_files=()

      if [[ "$proximity" == "local" ]]; then
          # Find all PbR* files in the local directory
          mapfile -t dicom_files < <(find "$stydir" -type f -name 'PbR*')
          
          if [[ ${#dicom_files[@]} -eq 0 ]]; then
              echo "N/A"
              return 1
          fi
          
          # Loop through all found files and accumulate UIDs
          for dicom_file in "${dicom_files[@]}"; do
              local uids=$(/home/medsrv/component/dicom/bin/dcmdump "$dicom_file" | grep -Po '(?<=\(0008,1155\) UI \[)[^\]]+')
              referenced_sop_instance_uids+="$uids"$'\n'
          done
      else
          # Find all PbR* files in the remote directory
          mapfile -t dicom_files < <(ssh -n "$system_ip" "find \"$stydir\" -type f -name 'PbR*'")
          
          if [[ ${#dicom_files[@]} -eq 0 ]]; then
              echo "N/A"
              return 1
          fi
          
          # Loop through all found files and accumulate UIDs
          for dicom_file in "${dicom_files[@]}"; do
              local uids=$(ssh -n "$system_ip" "/home/medsrv/component/dicom/bin/dcmdump \"$dicom_file\"" | grep -Po '(?<=\(0008,1155\) UI \[)[^\]]+')
              referenced_sop_instance_uids+="$uids"$'\n'
          done
      fi

      echo "$referenced_sop_instance_uids"
  }
  printInfo() {
      # Prepare the output in a variable
      local output
      output=$(
          printf "\n%-15s %-15s %-15s %-15s\n" "Category" "Source" "Target" "MigDB"
          echo "-------------------------------------------------------------"
          printf "%-15s %-15s %-15s %-15s\n" "IP Address" "$Source_IP" "$Target_IP" "$SERVERIP"
          printf "%-15s %-15s %-15s %-15s\n" "ProcessMode" "${Storestate_ProcessMode_Source:-unavailable}" "${Storestate_ProcessMode_Target:-unavailable}" "N/A"
          printf "%-15s %-15s %-15s %-15s\n" "Dcstudy_D" "${Dcstudy_D_Source:-unavailable}" "${Dcstudy_D_Target:-unavailable}" "N/A"
          printf "%-15s %-15s %-15s %-15s\n" "ImagesDB" "${NumofImg_DB_Source:-0}" "${NumofImg_DB_Target:-0}" "N/A"
          printf "%-15s %-15s %-15s %-15s\n" "ObjectsDB" "${NumofObj_DB_Source:-0}" "${NumofObj_DB_Target:-0}" "${GMInumofobj:-0}"
          printf "%-15s %-15s %-15s %-15s\n" "ObjectsFS" "${NumofObj_FS_Source:-0}" "${NumofObj_FS_Target:-0}" "N/A"
          printf "%-15s %-15s %-15s\n" "FSobjectsMissing" "N/A" "$NumofObjMissing_FS"
          printf "%-15s %-15s %-15s\n" "DBobjectsMissing" "N/A" "$NumofObjMissing_DB"
          echo "-------------------------------------------------------------"
          printf "%-15s %-15s %-15s %-15s\n" "PBStatus" "${PBStatus_Source:-0}" "${PBStatus_Target:-0}" "N/A"
          printf "%-15s %-15s %-15s %-15s\n" "ObsoleteStatus" "${ObsoleteStatus_Source:-none}" "${ObsoleteStatus_Target:-none}" "N/A"
          printf "%-15s %-15s %-15s %-15s\n" "PBLastModifiedDate" "${PBLastModifiedDate_Source:-unavailable}" "${PBLastModifiedDate_Target:-unavailable}" "N/A"

          printf "Source Dir: %s\n" "$StudyDir_Source"
          printf "Target Dir: %s\n" "$StudyDir_Target"

          # Print details of missing FS objects
            if [[ "$verbose" = "v" || $NumofObjMissing_FS -gt 0 ]]; then
                printf "\nMissing FS Objects:\n"
                for obj in "${Result_FS[@]}"; do
                    # Strip all leading alphabetic characters followed by a period
                    stripped_obj="${obj#[[:alpha:]]*.}"

                    # Check if the stripped object is in the obsolete SOPs source list
                    if [[ "$ObsoleteSOPS_Source" == *"$stripped_obj"* ]]; then
                        obj+=" Obs via PbR @Source"
                    fi

                    # Check if the stripped object is in the obsolete SOPs target list
                    if [[ "$ObsoleteSOPS_Target" == *"$stripped_obj"* ]]; then
                        obj+=" Obs via PbR @Target"
                    fi

                    printf "%s\n" "$obj"
                done
            fi

          # Print details of missing DB objects
          if [[ "$verbose" = "v" || $NumofObjMissing_DB -gt 0 ]]; then
              printf "\nMissing DB Objects:\n$Result_DB\n"
          fi
      )

      # Decide whether to pipe the output through `less` or print directly
      if [[ "$UsePager" == "true" ]]; then
          echo "$output" | less -R
      else
          echo "$output"
      fi
  }
  insertMissingObject() {
      local styiuid="$1"
      local system_id="$2"
      local object_name="$3"
      local absent_fs="$4"
      local absent_db="$5"
      local detected_date="$6"
      local resolved="${7:-FALSE}"
      local resolution_date="${8:-NULL}"

      # Format the SQL query to insert data into the missing_objects table
      local query="INSERT INTO missing_objects 
                  (styiuid, system_id, object_name, absent_fs, absent_db, detected_date, resolved, resolution_date)
                  VALUES
                  ('$styiuid', $system_id, '$object_name', '$absent_fs', '$absent_db', '$detected_date', $resolved, $resolution_date);"

      # Execute the query using the sql.sh script
      if ! sql.sh "$query"; then
          echo "Failed to insert missing object record into the database."
          return 1
      else
          echo "Missing object record successfully inserted."
          return 0
      fi
  }
  allMissingObjectsObsolete() {
      local missing_objects=("${Result_FS[@]}")
      local obsolete_sops="$ObsoleteSOPS_Source"
      local stripped_obj=""

      if [[ ${#missing_objects[@]} -eq 0 ]]; then
          return 1  # False - no missing objects to check
      fi

      for obj in "${missing_objects[@]}"; do
          # Strip all leading alphabetic characters followed by a period
          stripped_obj="${obj#[[:alpha:]]*.}"

          # Check if the stripped object is not in the obsolete SOPs source list
          if [[ "$obsolete_sops" != *"$stripped_obj"* ]]; then
              return 1  # False - found an object not in obsolete SOPs
          fi
      done

      return 0  # True - all missing objects are in obsolete SOPs
  }
  updateMigAdminStatus() {
      local suid="$1"
      local note="${2:-}"
      local update_query
      RequiredVariables "suid" "MigDB" "Source_IP" >/dev/null

      # If a note is provided, append it to the existing comment. Otherwise use the
      # historical default comment.
      if [[ -n "$note" ]]; then
          # Escape single quotes in the note for SQL safety (double them)
          local note_escaped
          note_escaped=$(printf "%s" "$note" | sed "s/'/''/g")
          update_query="USE $MigDB; UPDATE migadmin SET verification='passed', comment=CONCAT(IFNULL(comment,''), ' ', '$note_escaped') WHERE styiuid='$suid';"
      else
          update_query="USE $MigDB; UPDATE migadmin SET verification='passed', comment='missing obj(s) were obs' WHERE styiuid='$suid';"
      fi

      # Execute the query using the sql.sh script
      if sql.sh "$update_query"; then
          echo "Migration database updated successfully for SUID: $suid."
          return 0
      else
          echo "Failed to update migration database for SUID: $suid."
          return 1
      fi
  }

# MISC FUNCTIONS
  parse_args() {
      UsePager="false"  # Default is not to use the pager
      FileMode="false"  # Default is not to process a file
      AUTO_RESOLVE_UNREGISTERED="true"  # Default: automatically resolve unregistered objects

      while [[ "$#" -gt 0 ]]; do
          case $1 in
              -s|--studyid) 
                  suid="$2"; shift ;;
              -f|--file) 
                  file="$2"; FileMode="true"; shift ;;
              -b|--batch) 
                  BatchMode="true" ;;
              -v|--verbose) 
                  verbose="v" ;;
              --no-auto-resolve)
                  AUTO_RESOLVE_UNREGISTERED="false" ;;
              -p|--pager)  # New option to use less for paging output
                  UsePager="true" ;;
              --) 
                  shift; break ;;
              -h|--help) 
                  Usage; exit 0 ;;
              *) 
                  echo "Unknown parameter passed: $1"; Usage; exit 1 ;;
          esac
          shift
      done
  }

main_OG() {
    parse_args "$@"
    
    # Initialize environment
    initialize_environment
    database_name="$MigDB"
    
    # Process the study information if a study ID is provided
    if [[ -n "$suid" ]]; then
        getStudyInfo "$suid"
    else
        echo "Error: No study ID provided. Use -s or --studyid to specify the study ID."
        Usage
        exit 1
    fi
}
main() {
    parse_args "$@"
    
    # Initialize environment
    initialize_environment
    database_name="$MigDB"
    
    # Process the study information if a study ID or file is provided
    if [[ "$FileMode" == "true" ]]; then
        if [[ -f "$file" ]]; then
            while IFS= read -r suid; do
                getStudyInfo "$suid" "true"  # Passing "true" to skip printInfo
            done < "$file"
        else
            echo "Error: File not found: $file"
            exit 1
        fi
    elif [[ -n "$suid" ]]; then
        getStudyInfo "$suid"
    else
        echo "Error: No study ID or file provided. Use -s or --studyid to specify the study ID or -f or --file to specify a file."
        Usage
        exit 1
    fi
}

main "$@"

