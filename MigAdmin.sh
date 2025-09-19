#!/bin/bash
#shellcheck disable=SC1090,SC1091,SC2155,SC2034
####################################################
RED='\033[0;31m'    # USED FOR COLORIZING OUTPUT: RED
NC='\033[0m'        # USED FOR COLORIZING OUTPUT: No Color
GREEN='\033[0;32m'  # USED FOR COLORIZING OUTPUT: GREEN
CYAN='\033[0;36m'   # USED FOR COLORIZING OUTPUT: CYAN
YELLOW='\033[0;33m' # USED FOR COLORIZING OUTPUT: YELLOW
####################################################

Message() {
    local quiet_mode=0
    local display_only=0
    local log_level="INFO"
    local log_file="${_SCRIPT_LOG}"
    local log_message
    local log_options=()
    local arg
    local timestamp=$(date +"$_DATE_FMT")

    CreateDirectories "${_LOGS_DIR:-./logs}" || {
        printf "Failed to create directories: %s\n" "${_LOGS_DIR:-./logs}" >&2
        exit 1
    }

    # Parse arguments
    while (( "$#" )); do
        case "$1" in
            -q|--quiet) quiet_mode=1; shift ;;
            -d|--display-only) display_only=1; shift ;;
            -l|--log-level) log_level="$2"; shift 2 ;;
            -f|--log-file) log_file="$2"; shift 2 ;;
            *) log_options+=("$1"); shift ;;
        esac
    done

    log_message="${log_options[*]}"

    local log_entry="${timestamp} [${log_level}] ${log_message}"

    # Function to write log message to file
    log_the_message() {
        local lock_dir="${log_file}.lock"
        while ! mkdir "$lock_dir" 2>/dev/null; do
            sleep 0.1
        done

        printf "%s\n" "$log_entry" >> "$log_file" || {
            printf "Failed to write to log file: %s\n" "$log_file" >&2
            rmdir "$lock_dir"
            return 1
        }

        rmdir "$lock_dir"
    }

    # Handle logging based on flags
    if [[ "${BatchMode:-false}" == "true" || $quiet_mode -eq 1 || "${QUIET_MODE:-n}" == "y" ]]; then
        log_the_message
    elif [[ $display_only -eq 1 ]]; then
        printf "%s\n" "$log_entry"
    else
        printf "%s\n" "$log_entry"
        log_the_message
    fi
}
CreateDirectories() {
    #shellcheck disable=SC2124
    local dirs="$@"
    for dir in $dirs; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir" || {
                Message "Failed to create directory: %s\n" "$dir" >&2
                return 1
            }
        fi
    done
}
initialize_environment() {
    BatchMode="${BatchMode:-false}"
    if ! . universal.lib; then
        Message -d "Required library (universal.lib) not found. Exiting..."; exit 1
    else
        initialize_script_variables "MigAdmin.sh"  # Sets: _SCRIPT_NAME, _SCRIPT_CFG, _SCRIPT_LOG
        initialize_script_environment              # Verifies $USER, Verifies/Sources .default.cfg & migration.cfg
        verify_env || exit 1                       # Ensure all ${env_vars[@]} are set & not empty.
    fi
}
upsert_system_from_file() {
    # Usage: upsert_system_from_file "path/to/dcm-node.evopacs.cfg"

    local cfgFile="$1"
    local database_name="$2"
    # Check if the file exists
    if [ ! -f "$cfgFile" ]; then
        Message "Configuration file not found: $cfgFile"
        Message "Configuration file format:"
        Message "Filename: dcm-node.<label>.cfg"
        Message "Contents:"
        Message $'\trole="<role>" #source,target,conductor'
        Message $'\tlabel="<label>"'
        Message $'\tprimaryip="<dcm_listener_ip>"'
        Message $'\taet="<aetitle>"'
        Message $'\tport="<dcm_port>"'
        Message $'\tiseradpacs="<y|n>"'
        Message $'\tproximity="<local|remote>"'
        Message $'\tepMajorVersion="<6.2|7.2|7.3|8.0>"'
        return 1
    fi

    # Source the configuration file to import variables
    . "$cfgFile"
    if [ -z "$proximity" ]; then 
        if This_IP_Address_Belongs_To_This_Machine "${primaryip:?}"; then
        proximity="local"
        else
        proximity="remote"
        fi
    fi

    # SQL command to insert or update a system entry
    RequiredVariables "role" "label" "primaryip" "aet" "port" "iseradpacs" "epMajorVersion"
    # shellcheck disable=SC2154
    local insertSystemSQL="INSERT INTO systems (proximity, label, role, primaryip, aet, port, internalip, externalip, protocol, iseradpacs, ssh, epMajorVersion, epMinorVersion, epPatchVersion, filesystemroot, autoRetrieveLists, autoImportLists)
            VALUES ('$proximity', '$label', '${role:=conductor}', '$primaryip', '${aet:?}', '${port:=0}', '${internalip:-$primaryip}', '$externalip', '${protocol:=TCP}', '${iseradpacs:=n}', '${ssh:=n}', '${epMajorVersion:=1.0}', '${epMinorVersion:=1}', '${epPatchVersion:=1}', '$filesystemroot', '${autoRetrieveLists:=false}', '${autoImportLists:=false}')
            ON DUPLICATE KEY UPDATE
            role=VALUES(role), primaryip=VALUES(primaryip), aet=VALUES(aet), port=VALUES(port), internalip=VALUES(internalip), externalip=VALUES(externalip), protocol=VALUES(protocol), iseradpacs=VALUES(iseradpacs), ssh=VALUES(ssh), epMajorVersion=VALUES(epMajorVersion), epMinorVersion=VALUES(epMinorVersion), epPatchVersion=VALUES(epPatchVersion), filesystemroot=VALUES(filesystemroot), autoRetrieveLists=VALUES(autoRetrieveLists), autoImportLists=VALUES(autoImportLists);"

    # Execute the SQL command using mysql
    # Message "Executing upsert for >>> $label <<<"
    if ! "$MYSQL_BIN" -BN -u medsrv --database="${database_name}" -e "$insertSystemSQL"; then
        Message -d "Error inserting into systems table"
        return 1
    fi

    # Message "System >>> $label <<< inserted successfully into >>> $database_name <<<"
    return 0
}
ImportMultiColStyListViaCSV() {
    ImportMultiColStyListViaCSV_MysqlLoad() {
        local data_file="$1"
        local system_label="$2"
        local database_name="$3"

        local temp_table="temp_studies_multicol"
        local existing_studies_table="temp_existing_studies"
        local system_id_query="SELECT system_id FROM systems WHERE label='$system_label';"
        local system_id=$("$MYSQL_BIN" -BN -u medsrv --database="$database_name" -e "$system_id_query")

        if [ -z "$system_id" ]; then
            Message -d "System label $system_label not found. Exiting."
            return 1
        fi

        # Added Dcstudy_D
        local create_temp_table_sql="
            DROP TABLE IF EXISTS $temp_table;
            CREATE TABLE $temp_table (
                styiuid VARCHAR(100) NOT NULL,
                numofobj SMALLINT(5),
                sumsize BIGINT(20),
                pid CHAR(64),
                pbdate CHAR(8),
                accno CHAR(16),
                modality CHAR(8),
                styDate DATETIME NOT NULL DEFAULT '2000-01-01 00:00:00',
                styDescr VARCHAR(255) NOT NULL DEFAULT 'N/A',
                Dcstudy_D CHAR(3) DEFAULT 'no',  # Assuming the default value is 'no'
                mainst INT(11) NOT NULL DEFAULT '0',
                INDEX idx_styiuid (styiuid)
            );
            DROP TABLE IF EXISTS $existing_studies_table;
            CREATE TABLE $existing_studies_table AS
            SELECT styiuid FROM studies_systems WHERE system_id = '$system_id';
        "

        local load_data_sql="
            LOAD DATA LOCAL INFILE '$data_file' INTO TABLE $temp_table
            FIELDS TERMINATED BY '\t'
            LINES TERMINATED BY '\n';
        "

        local update_invalid_dates_sql="
        UPDATE $temp_table
            SET styDate = '2000-01-01 00:00:00'
            WHERE styDate IS NULL
            OR styDate NOT BETWEEN '1000-01-01 00:00:00' AND '9999-12-31 23:59:59';
        "

        local insert_into_migadmin_sql="
            INSERT INTO migadmin (styiuid)
            SELECT DISTINCT styiuid FROM $temp_table
            ON DUPLICATE KEY UPDATE styiuid=VALUES(styiuid);
        "

        local insert_into_studies_sql="
            INSERT INTO studies (styiuid, styDate, pid, pbdate, accno, modality, styDescr)
            SELECT styiuid, styDate, pid, pbdate, accno, modality, styDescr FROM $temp_table
            ON DUPLICATE KEY UPDATE styiuid=VALUES(styiuid), styDate=VALUES(styDate), pid=VALUES(pid), pbdate=VALUES(pbdate), accno=VALUES(accno), modality=VALUES(modality), styDescr=VALUES(styDescr);
        "

        # Added Dcstudy_D
        local insert_into_studies_systems_sql="
            INSERT INTO studies_systems (styiuid, system_id, numofobj, stysize, Dcstudy_d, mainst)
            SELECT styiuid, '$system_id', numofobj, sumsize, Dcstudy_D, mainst FROM $temp_table
            ON DUPLICATE KEY UPDATE numofobj=VALUES(numofobj), Dcstudy_d=VALUES(Dcstudy_d), mainst=VALUES(mainst);
        "

        local mark_or_remove_purged_sql="
            UPDATE migadmin m
            LEFT JOIN $existing_studies_table es ON m.styiuid = es.styiuid
            LEFT JOIN (
                SELECT styiuid FROM $temp_table
            ) ts ON m.styiuid = ts.styiuid
            SET m.skip='y', m.skip_reason='disappeared', m.exam_deleted='y'
            WHERE es.styiuid IS NOT NULL AND ts.styiuid IS NULL;
        "

        # Message "Creating temporary tables..."
        if ! echo "$create_temp_table_sql" | "$MYSQL_BIN" -u medsrv --database="$database_name"; then
            Message -d "Failed to create temporary tables."
            return 1
        fi

        Message "($data_file) inserting studies from..."
        if ! echo "$load_data_sql" | "$MYSQL_BIN" --local-infile=1 -u medsrv --database="$database_name"; then
            Message -d "Failed to load data into temporary table."
            Message -d "Check ~/var/mysql_conf/4custom.cnf, it should contain:"
            printf "[mysqld]\nlocal_infile=1\n"
            Message -d "Then restart mysql with: ~/component/mysql/ctrl stop && ~/component/mysql/ctrl start"
            Message -d "Verify: sql.sh \"SHOW GLOBAL VARIABLES LIKE 'local_infile';\""
            return 1
        fi

        Message "Updating invalid dates in styDate..."
        if ! echo "$update_invalid_dates_sql" | "$MYSQL_BIN" -u medsrv --database="$database_name"; then
            Message -d "Failed to update invalid dates in styDate."
            return 1
        fi

        Message "Inserting new records into migadmin..."
        if ! echo "$insert_into_migadmin_sql" | "$MYSQL_BIN" -u medsrv --database="$database_name"; then
            Message -d "Failed to insert data into migadmin table."
            return 1
        fi

        Message "Transferring data to production tables..."
        if ! echo "$insert_into_studies_sql" | "$MYSQL_BIN" -u medsrv --database="$database_name"; then
            Message -d "Failed to transfer data to production (studies) tables."
            return 1
        fi

        if ! echo "$insert_into_studies_systems_sql" | "$MYSQL_BIN" -u medsrv --database="$database_name"; then
            Message -d "Failed to transfer data to production (studies_systems) tables."
            return 1
        fi

        Message "Marking or removing purged records..."
        if ! echo "$mark_or_remove_purged_sql" | "$MYSQL_BIN" -u medsrv --database="$database_name"; then
            Message -d "Failed to mark or remove purged records."
            return 1
        fi

        Message "Updating records outside of date-range scope..."
        local base_update_query="
            UPDATE migadmin m
            LEFT JOIN studies s ON m.styiuid = s.styiuid
            SET m.skip = 'y', m.skip_reason = 'out of scope', m.in_scope = 'n'
        "
        # Initialize variables for queries
        local stop_date_update_query=""
        local start_date_update_query=""

        # Update query for when StopDate is defined (DATE(s.styDate) < '$StopDate')
        if [[ -n "$StopDate" ]]; then
            stop_date_update_query="
                $base_update_query
                WHERE DATE(s.styDate) < '$StopDate'
            "
        fi

        # Update query for when StartDate is defined (DATE(s.styDate) > '$StartDate')
        if [[ -n "$StartDate" ]]; then
            start_date_update_query="
                $base_update_query
                WHERE DATE(s.styDate) > '$StartDate'
            "
        fi

        # Execute StopDate query if it is defined
        if [[ -n "$stop_date_update_query" ]]; then
            if ! echo "$stop_date_update_query" | "$MYSQL_BIN" -u medsrv --database="$database_name"; then
                Message -d "Failed to update records with StopDate condition."
                return 1
            fi
        fi

        # Execute StartDate query if it is defined
        if [[ -n "$start_date_update_query" ]]; then
            if ! echo "$start_date_update_query" | "$MYSQL_BIN" -u medsrv --database="$database_name"; then
                Message -d "Failed to update records with StartDate condition."
                return 1
            fi
        fi

        Message -d "Data insertion complete."
        return 0
    }
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

        local insert_into_migadmin_sql="INSERT INTO migadmin (styiuid)
                                        SELECT styiuid FROM $temp_table
                                        ON DUPLICATE KEY UPDATE styiuid=VALUES(styiuid);"

        # Insert data from temporary table into main tables
        local insert_into_studies_sql="INSERT INTO studies (styiuid) SELECT styiuid FROM $temp_table ON DUPLICATE KEY UPDATE styiuid=VALUES(styiuid);"
        local insert_into_studies_systems_sql="INSERT INTO studies_systems (styiuid, system_id)
                                              SELECT styiuid, '$system_id' FROM $temp_table
                                              ON DUPLICATE KEY UPDATE system_id=VALUES(system_id);"

        # Execute SQL commands
        # Message "Creating temporary table $temp_table..."
        echo "$create_temp_table_sql" | "$MYSQL_BIN" -u medsrv --database="$database_name"

        Message "($data_file) inserting studies from..."
        echo "$load_data_sql" | "$MYSQL_BIN" --local-infile=1 -u medsrv --database="$database_name"

        # Message "Inserting records into migadmin..."
        echo "$insert_into_migadmin_sql" | "$MYSQL_BIN" -u medsrv --database="$database_name"
        
        # Message "Inserting records into studies..."
        echo "$insert_into_studies_sql" | "$MYSQL_BIN" -u medsrv --database="$database_name"

        # Message "Inserting records into studies_systems..."
        echo "$insert_into_studies_systems_sql" | "$MYSQL_BIN" -u medsrv --database="$database_name"

        # Message -d "Data insertion complete."
    }

    local file_path="$1"
    local system_label="$2"
    local database_name="${3:-$MigDB}"
            
    RequiredVariables "file_path" "system_label" "database_name"

    # Detect column count (tab-delimited)
    local col_count
    col_count=$(awk -F'\t' '{print NF; exit}' "$file_path")

    if [[ "$col_count" -eq 1 ]]; then
        Message -d "Detected single column in file. Importing as single-column study list."
        # Call the single-column import function
        if ! ImportStyListViaCSV_MysqlLoad "$file_path" "$system_label" "$database_name"; then
            Message -d "Failed to import study list. Exiting."
            exit 1
        fi
        Message -d "Successfully imported the study list as a single-column study list."
        return 0
    else 
        # Message -d "Detected multiple columns in file. Importing as multi-column study list."
        # Call the multi-column import function
        if ! ImportMultiColStyListViaCSV_MysqlLoad "$file_path" "$system_label" "$database_name"; then
            Message -d "Failed to import multi-column study list. Exiting."
            exit 1
        fi
        # Message -d "Successfully imported the multi-column study list."
        return 0
    fi
}
GetAutoRetrievalLabels() {
    # Assuming MYSQL_BIN and MigDB are already set up in your environment
    local query="SELECT label FROM systems WHERE autoRetrieveLists='true' AND ssh='y';"
    local labels=$("$MYSQL_BIN" -BN -u medsrv --database="$MigDB" -e "$query")
    # shellcheck disable=SC2086
    echo $labels
}
FreshInstall() {
    # Variables required to execute a Fresh Installation:
    #  - MigDB, MYSQL_BIN, MYSQL_ROOT_PW
    #  - MigDB requires CaseNumber
    This_IP_Address_Belongs_To_This_Machine() {
        local ip_address="$1"
        local local_ips="$(/sbin/ifconfig | grep 'inet ' | awk '{print $2}')"
        # Check if the provided IP address is among the local IPs
        if echo "$local_ips" | grep -w "$ip_address" >/dev/null 2>&1; then
            #echo "The IP address $ip_address belongs to one of the system's interfaces."
            return 0
        else
            #echo "The IP address $ip_address does not belong to any of the system's interfaces."
            return 1
        fi
    }
    CreateDatabase() {
        local database_name
        database_name="$1"
        # Database Functions
        # root (grant) privileges required
        if ! "$MYSQL_BIN" -BN -u root -p"$MYSQL_ROOT_PW" -e "GRANT ALL PRIVILEGES ON $database_name.* TO 'medsrv'@'localhost';" 2>/dev/null; then
        Message -d "Mysql command error, exiting."
        exit 1
        fi
        
        # root (reload) privileges required
        if ! "$MYSQL_BIN" -BN -u root -p"$MYSQL_ROOT_PW" -e "FLUSH PRIVILEGES;" 2>/dev/null; then
        Message -d "Mysql command error, exiting."
        exit 1
        fi
        
        # Once privileges are granted & flushed, mysql root pw should no longer be needed
        if ! "$MYSQL_BIN" -BN -u medsrv -e "CREATE DATABASE IF NOT EXISTS $database_name;"; then
        Message -d "Mysql command error, exiting."
        exit 1
        fi
    }
    CreateTables() {
        local database_name="$1"
        local queries=""

        # SQL Mode and Checks
        queries+="SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0;
                    SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0;
                    SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='ONLY_FULL_GROUP_BY,STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION';"

        # studies Table OG
        # queries+="CREATE TABLE IF NOT EXISTS studies (
        #             styiuid VARCHAR(100) NOT NULL,
        #             is_locked ENUM('y', 'n') NOT NULL DEFAULT 'n',
        #             lockdt DATETIME NULL,
        #             accno CHAR(16) NOT NULL DEFAULT 'N/A',
        #             pid CHAR(64) NOT NULL DEFAULT 'N/A',
        #             pbdate CHAR(8) NULL DEFAULT NULL,
        #             -- styDate DATE NOT NULL DEFAULT '2001-01-01',
        #             styDate DATETIME NOT NULL DEFAULT '2000-01-01 00:00:00',
        #             modality CHAR(8) NULL DEFAULT 'N/A',
        #             styDescr VARCHAR(255) NOT NULL DEFAULT 'N/A',
        #             compressed ENUM('y', 'n') NOT NULL DEFAULT 'n',
        #             comment VARCHAR(255) NOT NULL DEFAULT '',
        #             skip ENUM('y', 'n') NOT NULL DEFAULT 'n',
        #             skip_reason VARCHAR(255) NOT NULL DEFAULT '',
        #             report_migrated ENUM('y', 'n') NOT NULL DEFAULT 'n',
        #             priority INT(11) NOT NULL DEFAULT '0',
        #             verification ENUM('pending', 'passed', 'failed', 'n/a') NOT NULL DEFAULT 'n/a',
        #             PRIMARY KEY (styiuid),
        #             INDEX idx_skip (skip),
        #             INDEX idx_verification (verification)
        #             ) ENGINE = InnoDB;"

        # studies Table
        queries+="CREATE TABLE IF NOT EXISTS studies (
                    styiuid VARCHAR(100) NOT NULL,
                    accno CHAR(16) NOT NULL DEFAULT 'N/A',
                    pid CHAR(64) NOT NULL DEFAULT 'N/A',
                    pbdate CHAR(8) NULL DEFAULT NULL,
                    styDate DATETIME NOT NULL DEFAULT '2000-01-01 00:00:00',
                    modality CHAR(8) NULL DEFAULT 'N/A',
                    styDescr VARCHAR(255) NOT NULL DEFAULT 'N/A',
                    FOREIGN KEY (styiuid) REFERENCES migadmin (styiuid) ON DELETE CASCADE,
                    PRIMARY KEY (styiuid)
                ) ENGINE = InnoDB;"

        # migadmin Table
        queries+="CREATE TABLE IF NOT EXISTS migadmin (
                    styiuid VARCHAR(100) NOT NULL,
                    is_locked ENUM('y', 'n') NOT NULL DEFAULT 'n',
                    transferred_datetime DATETIME NULL,
                    compressed ENUM('y', 'n') NOT NULL DEFAULT 'n',
                    comment VARCHAR(255) NOT NULL DEFAULT '',
                    skip ENUM('y', 'n') NOT NULL DEFAULT 'n',
                    skip_reason VARCHAR(255) NOT NULL DEFAULT '',
                    report_migrated ENUM('y', 'n') NOT NULL DEFAULT 'n',
                    priority INT(11) NOT NULL DEFAULT 0,
                    verification ENUM('pending', 'passed', 'failed', 'n/a') NOT NULL DEFAULT 'n/a',
                    export_location VARCHAR(255) NULL DEFAULT '',
                    target_only ENUM('y', 'n') NOT NULL DEFAULT 'n',
                    in_scope ENUM('y', 'n') NOT NULL DEFAULT 'y',
                    exam_requested ENUM('y', 'n') NOT NULL DEFAULT 'n',
                    exam_deleted ENUM('y', 'n') NOT NULL DEFAULT 'n',
                    PRIMARY KEY (styiuid),
                    INDEX idx_skip (skip),
                    INDEX idx_verification (verification)
                ) ENGINE = InnoDB;"

        # systems Table
        queries+="CREATE TABLE IF NOT EXISTS systems (
                    system_id INT NOT NULL AUTO_INCREMENT,
                    enabled ENUM('y', 'n') NOT NULL DEFAULT 'y',
                    proximity ENUM('local','remote','define_me') NULL DEFAULT 'define_me',
                    role ENUM('source', 'target', 'conductor') NOT NULL DEFAULT 'conductor',
                    label VARCHAR(45) NOT NULL,
                    internalip CHAR(16) NOT NULL DEFAULT '',
                    externalip CHAR(16) NOT NULL DEFAULT '',
                    primaryip CHAR(16) NOT NULL DEFAULT '',
                    aet CHAR(16) NULL DEFAULT NULL,
                    port SMALLINT(5) UNSIGNED NOT NULL DEFAULT 0,
                    protocol ENUM('TCP', 'TLS') NOT NULL DEFAULT 'TCP',
                    iseradpacs ENUM('y', 'n') NOT NULL DEFAULT 'n',
                    ssh ENUM('y', 'n') NOT NULL DEFAULT 'n',
                    epMajorVersion DECIMAL(2,1) NOT NULL DEFAULT '1.0',
                    epMinorVersion SMALLINT(3) NOT NULL DEFAULT '001',
                    epPatchVersion SMALLINT(3) NOT NULL DEFAULT '001',
                    filesystemroot VARCHAR(255) NOT NULL DEFAULT '',
                    autoRetrieveLists ENUM('true','false') DEFAULT 'false',
                    autoImportLists ENUM('true','false') DEFAULT 'false',
                    PRIMARY KEY (system_id),
                    UNIQUE INDEX label_UNIQUE (label ASC)
                    ) ENGINE = InnoDB;"

        # studies_systems Table
        queries+="CREATE TABLE IF NOT EXISTS studies_systems (
                    id INT NOT NULL AUTO_INCREMENT,
                    styiuid VARCHAR(100) NOT NULL,
                    system_id INT NOT NULL,
                    attempts SMALLINT(5) NULL DEFAULT '0',
                    last_attempt DATETIME NULL DEFAULT NULL,
                    transferred_datetime DATETIME NULL DEFAULT NULL,
                    numofobj SMALLINT(5) NOT NULL DEFAULT '0',
                    derived CHAR(32) NOT NULL DEFAULT '',
                    mainst INT(11) NOT NULL DEFAULT '0',
                    Dcstudy_d CHAR(3) NOT NULL DEFAULT 'no',
                    stysize BIGINT(20) NULL DEFAULT '0',
                    remote_ep_stydir VARCHAR(255) NULL DEFAULT NULL,
                    PRIMARY KEY (id),
                    UNIQUE KEY unique_styiuid_system_id (styiuid, system_id),
                    INDEX fk_styiuid_idx (styiuid ASC),
                    INDEX fk_systemid_idx (system_id ASC),
                    CONSTRAINT fk_stySys_styiuid
                        FOREIGN KEY (styiuid)
                        REFERENCES studies (styiuid)
                        ON DELETE NO ACTION
                        ON UPDATE NO ACTION,
                    CONSTRAINT fk_stySys_systemid
                        FOREIGN KEY (system_id)
                        REFERENCES systems (system_id)
                        ON DELETE NO ACTION
                        ON UPDATE NO ACTION
                    ) ENGINE = InnoDB;"

        # missing_objects Table
        queries+="CREATE TABLE IF NOT EXISTS missing_objects (
                        missing_object_id INT AUTO_INCREMENT PRIMARY KEY,
                        styiuid VARCHAR(100),
                        system_id INT,
                        object_name VARCHAR(255),
                        absent_fs ENUM('y', 'n') NOT NULL DEFAULT 'n',
                        absent_db ENUM('y', 'n') NOT NULL DEFAULT 'n',
                        error_message TEXT,
                        detected_date DATETIME,
                        resolved BOOLEAN DEFAULT FALSE,
                        resolution_date DATETIME NULL,
                        FOREIGN KEY (styiuid) REFERENCES studies(styiuid),
                        FOREIGN KEY (system_id) REFERENCES systems(system_id)
                    ) ENGINE = InnoDB;"
        # dcm_objects Table
        queries+="CREATE TABLE IF NOT EXISTS dcm_objects (
                        dcm_object_id INT AUTO_INCREMENT PRIMARY KEY,
                        styiuid VARCHAR(100),
                        system_id INT,
                        sopiuid VARCHAR(64),
                        fullpath VARCHAR(255),
                        skip ENUM('y','n') DEFAULT 'n',
                        error ENUM('y','n') DEFAULT 'n',
                        error_message TEXT,
                        comment VARCHAR(64) DEFAULT '',
                        sent ENUM('y','n') DEFAULT 'n',
                        FOREIGN KEY (styiuid) REFERENCES studies(styiuid),
                        FOREIGN KEY (system_id) REFERENCES systems(system_id),
                        UNIQUE KEY idx_sopiuid (sopiuid),
                        KEY xstyiuid (styiuid),
                        KEY xfullpath (fullpath)
                    ) ENGINE = InnoDB;"

        # dcm_objects Table
        queries+="CREATE VIEW study_details AS
                        SELECT 
                            s.accno,
                            s.pid,
                            s.styDate,
                            s.modality,
                            s.styDescr,
                            ss.numofobj,
                            m.in_scope,
                            m.skip,
                            m.skip_reason,
                            m.verification,
                            m.comment,
                            m.export_location,
                            m.exam_deleted,
                            sys.label AS study_source,
                            s.styiuid
                        FROM 
                            studies s
                        JOIN 
                            migadmin m ON s.styiuid = m.styiuid
                        JOIN 
                            studies_systems ss ON s.styiuid = ss.styiuid
                        JOIN 
                            systems sys ON ss.system_id = sys.system_id
                        WHERE 
                            sys.role = 'source'
                        ORDER BY
                            (in_scope = 'n') ASC,
                            s.styDate DESC;"

        # Reset SQL Mode and Checks
        queries+="SET SQL_MODE=@OLD_SQL_MODE;
                    SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS;
                    SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS;"

        # Execute all queries as a single batch
        # if ! echo "$queries" | "$MYSQL_BIN" -BN -u root -p"$MYSQL_ROOT_PW" --database="${database_name}"; then
        # Once privileges are granted, mysql root pw should no longer be needed
        if ! echo "$queries" | "$MYSQL_BIN" -BN -u medsrv --database="${database_name}"; then
            Message -d "MySQL command error on batch execution"
            return 1
        fi

        return 0
    }
    insertDicomNodesFromFile() {
        # Message -d "Checking for dcm-node files in >>> $(pwd) <<<"
        Message -d "($(pwd)) Checking for dcm-node files in..."

        for file in dcm-node.*.cfg; do
            # Check if the pattern does not expand to non-existent files
            if [[ -e "$(pwd)/$file" ]]; then
                # Call the function with the full path of the file
                # Message "Inserting system from >>> $file <<<"
                Message "($file) Inserting system from..."
                upsert_system_from_file "$(pwd)/$file" "$MigDB"
            fi
        done
    }


    if ! RequiredVariables "CaseNumber" "MigDB" "MYSQL_ROOT_PW" "MYSQL_BIN"; then
        Message "Required Variables: CaseNumber, MigDB, MYSQL_ROOT_PW, MYSQL_BIN"
        exit 1
    fi

    if DatabaseExists "$MigDB"; then
        Message "Error: Database $MigDB already exists. Exiting..."
        exit 1
    else
        CreateDatabase "$MigDB"
        if ! CreateTables "$MigDB"; then
        Message "Failed trying to load sql file into $MigDB database, exiting"
        Message "Command Used: /home/medsrv/component/mysql/bin/mysql --user=root --password=\$MYSQL_ROOT_PW --database=$MigDB <nomaDicom_tables.sql"
        fi
    fi

    # Auto-install dicom nodes
    if ${AutoAddNodes:=true}; then
        # Auto-Retrieve Study Lists
        if insertDicomNodesFromFile; then
        # Verify there is at least one source and one target
        # FIXME: I do not think this needs to be here
        # if ! Verify_AtLeast_OneSource_And_OneTarget; then
        #   Message "Error: Not enough source or target systems to perform verification."
        #   return 1
        # fi
        
        # Retrieve and process study lists for systems that need automatic retrieval
        AutoRetrieveAndImportStudyLists
        fi
    fi
    # Auto-install dicom nodes
    # if ${AutoAddNodes:=true}; then
    #     # Auto-Retrieve Study Lists
    #     if insertDicomNodesFromFile; then
    #     # Verify there is at least one source and one target
    #     # FIXME: I do not think this needs to be here
    #     # if ! Verify_AtLeast_OneSource_And_OneTarget; then
    #     #   Message "Error: Not enough source or target systems to perform verification."
    #     #   return 1
    #     # fi
        
    #     # Retrieve and process study lists for systems that need automatic retrieval
    #     # shellcheck disable=SC2207
    #     local labels=( $(GetAutoRetrievalLabels) ) # Fetch labels with autoRetrieveLists true and ssh 'y'
    #     for label in "${labels[@]}"; do
    #         # Query to check the autoImportLists status for the current label
    #         local query="SELECT autoImportLists FROM systems WHERE label='$label';"
    #         local autoImportLists=$("$MYSQL_BIN" -BN -u medsrv --database="$MigDB" -e "$query")

    #         local studyListFile="$(FetchStudyList "$label" "quiet")"
    #         if [[ -f "$studyListFile" ]]; then  # Check if the file exists and is not empty
    #             if [[ "$autoImportLists" == "true" ]]; then
    #                 ImportMultiColStyListViaCSV "$studyListFile" "$label" "$MigDB"
    #             else
    #                 Message "Auto import list is not enabled for $label"
    #             fi
    #         else
    #             Message "Failed to retrieve or find study list file for $label"
    #         fi
    #     done
    #     fi
    # fi
}
AutoRetrieveAndImportStudyLists() {
    # shellcheck disable=SC2207
    local labels=( $(GetAutoRetrievalLabels) )
    if [[ ${#labels[@]} -eq 0 ]]; then
        echo -e "\n==== WARNING ====\nNo systems found with autoRetrieveLists='true' and ssh='y'.\n=================\n"
        return 1
    fi
    for label in "${labels[@]}"; do
        local query="SELECT autoImportLists FROM systems WHERE label='$label';"
        local autoImportLists=$("$MYSQL_BIN" -BN -u medsrv --database="$MigDB" -e "$query")

        local studyListFile
        studyListFile="$(FetchStudyList "$label" "quiet")"
        if [[ ! -f "$studyListFile" ]]; then
            echo -e "\n==== WARNING ====\nStudy list for '$label' was NOT fetched (file missing or fetch failed).\n=================\n"
            continue
        fi

        if [[ "$autoImportLists" == "true" ]]; then
            ImportMultiColStyListViaCSV "$studyListFile" "$label" "$MigDB"
        else
            echo -e "\n==== WARNING ====\nStudy list for '$label' was fetched but NOT imported (autoImportLists != 'true').\n=================\n"
        fi
    done
}
setSystemDetails() {
    local label="$1"
    local system_prefix

    if [ "$label" == "$Source_Label" ]; then
        system_prefix="Source_"
    elif [ "$label" == "$Target_Label" ]; then
        system_prefix="Target_"
    else
        Message -d "Label does not match source or target labels."
        return 1
    fi

    local proximity="${system_prefix}Proximity"
    local primary_ip="${system_prefix}IP"
    local internal_ip="${system_prefix}Internal_IP"
    local version="${system_prefix}Version"
    local isErad="${system_prefix}isErad"
    local dateColumn="stydatetime"
    local dateColumnFormat="IFNULL(DATE_FORMAT($dateColumn, '%Y-%m-%d %H:%i:%s'), '2000-01-01 00:00:00')"
    local excludePbR="no"

    if [[ "${!version}" != "8.0" && "${!version}" != "7.3" ]]; then
        dateColumn="stydate"
        dateColumnFormat="DATE_FORMAT(IF($dateColumn = '' OR $dateColumn IS NULL, STR_TO_DATE('20000101', '%Y%m%d'), STR_TO_DATE($dateColumn, '%Y%m%d')), '%Y-%m-%d 00:00:00')"
    fi

    if [[ "${!isErad}" == "n" ]]; then
        excludePbR="yes"
    fi

    # The order of columns here matters. It should match the order they are read
    # from within the FetchStudyList() invokation of setSystemDetails().
    # Output the six fields separated by literal tab characters.
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "${!proximity}" "${excludePbR}" "${!primary_ip}" "${!internal_ip}" "${dateColumn}" "${dateColumnFormat}"
}
getFieldValueForLabel() {
    local label="$1"
    local field="$2"

    # Validate input parameters
    if [[ -z "$label" || -z "$field" ]]; then
        Message -d "Usage: getFieldValueForLabel <label> <field>"
        return 1
    fi

    # Query to fetch the value of the specified field for the given label
    local query="SELECT $field FROM systems WHERE label='$label';"
    local value

    # Execute the query and capture the result
    value=$("$MYSQL_BIN" -BN -u medsrv --database="$MigDB" -e "$query")

    # Check if the query returned a result
    if [[ -z "$value" ]]; then
        Message -d "Error: No value found for label '$label' and field '$field'."
        return 1
    fi

    # Output the value
    echo "$value"
    return 0
}
FetchStudyList() {
    local label="$1"
    local quiet="$2"
    local outputFile="study-list_${label}_$(date "+%Y%m%d-%H%M%S").tsv"
    outputFile="${_STYLIST_DIR:lists}/$outputFile"

    # load_system_details  # Loads Source_* and Target_* details including *_Proximity
    # Export the environments variables so they can be access by the subshell created by the command substitution below.
    # export Source_Label Source_Proximity Source_IP Source_isErad Source_Version Source_Internal_IP Target_Label Target_Proximity Target_IP Target_isErad Target_Version Target_Internal_IP
    

    # Use IFS=$'\t' to read tab-delimited output
    # IFS=$'\t' read -r proximity excludePbR primary_ip internal_ip dateColumn dateColumnFormat <<< "$(setSystemDetails "$label")"
    # [ $? -ne 0 ] && return 1  # Exit if system details setting failed

    proximity="$(getFieldValueForLabel "$label" "proximity")"
    internal_ip="$(getFieldValueForLabel "$label" "internalip")"
    
    version="$(getFieldValueForLabel "$label" "epMajorVersion")"
    if [[ "${version}" != "8.0" && "${version}" != "7.3" ]]; then
        dateColumn="stydate"
        dateColumnFormat="DATE_FORMAT(IF($dateColumn = '' OR $dateColumn IS NULL, STR_TO_DATE('20000101', '%Y%m%d'), STR_TO_DATE($dateColumn, '%Y%m%d')), '%Y-%m-%d 00:00:00')"
    else
        dateColumn="stydatetime"
        dateColumnFormat="IFNULL(DATE_FORMAT($dateColumn, '%Y-%m-%d %H:%i:%s'), '2000-01-01 00:00:00')"
    fi
    
    isErad="$(getFieldValueForLabel "$label" "iseradpacs")"
    if [[ "${!isErad}" == "n" ]]; then
        excludePbR="yes"
    else
        excludePbR="no"
    fi

    # local query_base="SELECT styiuid, numofobj, sumsize, pid, pbdate, accno, modality, $dateColumnFormat AS formatted_datetime, stydescr FROM Dcstudy WHERE mainst>='0' AND Dcstudy_d!='yes' AND derived NOT IN('copy','shortcut')"
    # [ "$excludePbR" == "yes" ] && query_base="SELECT D.styiuid, (D.numofobj - COALESCE(O.numofpbr, 0)) AS numofobj, D.sumsize, D.pid, $dateColumnFormat AS formatted_datetime FROM imagemedical.Dcstudy AS D LEFT JOIN (SELECT styiuid, COUNT(*) AS numofpbr FROM imagemedical.Dcobject WHERE FNAME LIKE 'Pb%' GROUP BY styiuid) AS O ON D.styiuid=O.styiuid WHERE D.MAINST>='0' AND D.DERIVED NOT IN('copy','shortcut') AND D.Dcstudy_D!='yes'"
    
    # Added Dcstudy_D to the select statement
    local query_base="SELECT styiuid, numofobj, sumsize, pid, pbdate, accno, modality, $dateColumnFormat AS formatted_datetime, stydescr, Dcstudy_D, mainst  FROM Dcstudy WHERE mainst>='0' AND derived NOT IN('copy','shortcut')"
    [ "$excludePbR" == "yes" ] && query_base="SELECT D.styiuid, (D.numofobj - COALESCE(O.numofpbr, 0)) AS numofobj, D.sumsize, D.pid, $dateColumnFormat AS formatted_datetime, D.Dcstudy_D, D.mainst  FROM imagemedical.Dcstudy AS D LEFT JOIN (SELECT styiuid, COUNT(*) AS numofpbr FROM imagemedical.Dcobject WHERE FNAME LIKE 'Pb%' GROUP BY styiuid) AS O ON D.styiuid=O.styiuid WHERE D.MAINST>='0' AND D.DERIVED NOT IN('copy','shortcut')"

    if [ "$proximity" == "local" ]; then
        sql.sh "$query_base" -N > "$outputFile"
    elif [ "$proximity" == "remote" ]; then
        # ssh -x "$primary_ip" "sql.sh \"$query_base\" -N" > "$outputFile"
        ssh -x "$internal_ip" "sql.sh \"$query_base\" -N" > "$outputFile"
    else
        Message -d "Proximity for $label not defined or unknown."
        return 1
    fi

    if [ "$quiet" == "quiet" ]; then
        echo "$outputFile"
    else
        Message "Study list for $label generated: $outputFile"
    fi
}
refresh_verification() {
    Verify_AtLeast_OneSource_And_OneTarget() {
        local check_systems_query="SELECT EXISTS (
            SELECT 1 FROM systems WHERE role = 'target' LIMIT 1
        ) as has_target, EXISTS (
            SELECT 1 FROM systems WHERE role = 'source' LIMIT 1
        ) as has_source;"
        
        # Check for the existence of at least one target and one source system
        output=$("$MYSQL_BIN" -BN -u medsrv --database="$MigDB" -e "$check_systems_query" | awk '{print $1, $2}')
        read -r has_target has_source <<< "$output"
        
        if [[ "$has_target" -ne 1 || "$has_source" -ne 1 ]]; then
            Message -d "Not enough source or target systems to perform verification."
            return 1
        fi
    }
    Identify_Deleted_Studies() {
        local deleted_studies_query="SELECT STYIUID FROM LogView WHERE LOGACTION='delete';"
        deleted_studies=$("$MYSQL_BIN" -BN -u medsrv --database="imagemedical" -e "$deleted_studies_query")
    }
    Update_Deleted_Studies() {
        local update_deleted_query="UPDATE $MigDB.migadmin ma
        JOIN imagemedical.LogView lv ON ma.styiuid = lv.STYIUID
        SET ma.skip = 'y', ma.skip_reason='deleted state', ma.exam_deleted = 'y'
        WHERE lv.LOGACTION = 'delete';"
        
        if ! "$MYSQL_BIN" -BN -u medsrv --database="$MigDB" -e "$update_deleted_query"; then
            Message -d "Failed to update 'deleted' status for studies in database $MigDB."
            return 1
        fi
    }

    local database_name="$1"
    local styiuid="$2"  # Optional styiuid argument
    
    local styiuid_condition=""
    if [[ -n "$styiuid" ]]; then
        styiuid_condition="AND ss.styiuid = '$styiuid'"
    fi
    
    if ! Verify_AtLeast_OneSource_And_OneTarget; then
        Message -d "Not enough source or target systems to perform verification."
        return 1
    fi

    Identify_Deleted_Studies
    if [[ -n "$deleted_studies" ]]; then
        Update_Deleted_Studies
    fi

    # Update for 'skipped' due to deletion
    local update_skipped_query="UPDATE migadmin ma
    JOIN (
        SELECT ss.styiuid
        FROM studies_systems ss
        JOIN systems sys ON ss.system_id = sys.system_id
        WHERE ss.Dcstudy_D = 'yes' $styiuid_condition
        GROUP BY ss.styiuid
    ) skipped_studies ON ma.styiuid = skipped_studies.styiuid
    SET ma.skip = 'y', ma.skip_reason = 'deleted state', ma.exam_deleted = 'y';"

    # Update to 'passed'
    local update_passed_query="UPDATE migadmin ma
    JOIN (
        SELECT ss.styiuid
        FROM studies_systems ss
        JOIN systems sys ON ss.system_id = sys.system_id AND sys.role = 'target'
        WHERE ss.Dcstudy_D != 'yes' $styiuid_condition
        GROUP BY ss.styiuid
        HAVING MAX(ss.numofobj) >= ALL (
            SELECT ss2.numofobj
            FROM studies_systems ss2
            JOIN systems sys2 ON ss2.system_id = sys2.system_id AND sys2.role = 'source'
            WHERE ss2.Dcstudy_D != 'yes' AND ss2.styiuid = ss.styiuid
        )
    ) passed_studies ON ma.styiuid = passed_studies.styiuid
    SET ma.verification = 'passed';"
    
    # Update to 'pending'
    local update_pending_query="UPDATE migadmin ma
    JOIN (
        SELECT ss.styiuid
        FROM studies_systems ss
        JOIN systems sys ON ss.system_id = sys.system_id AND sys.role = 'target'
        WHERE ss.Dcstudy_D != 'yes' AND EXISTS (
            SELECT 1
            FROM studies_systems ss2
            JOIN systems sys2 ON ss2.system_id = sys2.system_id AND sys2.role = 'source'
            WHERE ss2.styiuid = ss.styiuid AND ss2.Dcstudy_D != 'yes'
        )
        GROUP BY ss.styiuid
        HAVING MAX(ss.numofobj) > 0 AND MAX(ss.numofobj) < ALL (
            SELECT ss2.numofobj
            FROM studies_systems ss2
            JOIN systems sys2 ON ss2.system_id = sys2.system_id AND sys2.role = 'source'
            WHERE ss2.Dcstudy_D != 'yes' AND ss2.styiuid = ss.styiuid
        )
    ) pending_studies ON ma.styiuid = pending_studies.styiuid
    SET ma.verification = 'pending'
    WHERE ma.verification != 'passed';"

    if ! "$MYSQL_BIN" -BN -u medsrv --database="$database_name" -e "$update_skipped_query"; then
        Message -d "Failed to update skipped status for deleted studies in database $database_name."
        return 1
    fi

    if ! "$MYSQL_BIN" -BN -u medsrv --database="$database_name" -e "$update_passed_query"; then
        Message -d "Failed to update to 'passed' status for database $database_name."
        return 1
    fi

    if ! "$MYSQL_BIN" -BN -u medsrv --database="$database_name" -e "$update_pending_query"; then
        Message -d "Failed to update to 'pending' status for database $database_name."
        return 1
    fi

    Message "Verification refresh completed for database $database_name."
    return 0
}
set_skip_for_target_only_exams() {
    local database_name="$1"
    local query="
    UPDATE migadmin m
    JOIN (
        SELECT ss.styiuid
        FROM studies_systems ss
        JOIN systems sys ON ss.system_id = sys.system_id AND sys.role = 'target'
        WHERE NOT EXISTS ( -- Ensure there is no corresponding source entry for each target study
            SELECT 1
            FROM studies_systems ss2
            JOIN systems sys2 ON ss2.system_id = sys2.system_id AND sys2.role = 'source'
            WHERE ss2.styiuid = ss.styiuid
        )
        GROUP BY ss.styiuid
    ) target_only_studies ON m.styiuid = target_only_studies.styiuid
    SET m.skip='y', m.skip_reason='target only', m.target_only='y';"

    if ! "$MYSQL_BIN" -BN -u medsrv --database="$database_name" -e "$query"; then
        Message -d "Failed to update target-only records for database $database_name."
        return 1
    fi
}
resolve_system_label() {
    load_system_details  # Ensure that Source_Label and Target_Label are available.
    # NOTE: What happens when there are multiple target/source systems?
    local label_input="$1"
    case "$label_input" in
        source) echo "$Source_Label" ;;
        target) echo "$Target_Label" ;;
        *) echo "$label_input" ;;
    esac
}
AutoImportStudyLists() {
    # FIXME: This does not yet work as inteded.
    # I am looking to have a function that fetches the study lists, imports them, and then updates (refresh verification) the db
    # shellcheck disable=SC2207
    local labels=( $(GetAutoRetrievalLabels) )  # Fetch labels with autoRetrieveLists true and ssh 'y'
    
    for label in "${labels[@]}"; do
        # Query to check the autoImportLists status for the current label
        local query="SELECT autoImportLists FROM systems WHERE label='$label';"
        local autoImportLists=$("$MYSQL_BIN" -BN -u medsrv --database="$MigDB" -e "$query")

        local studyListFile="$(FetchStudyList "$label" "quiet")"
        if [[ -f "$studyListFile" ]]; then  # Check if the file exists and is not empty
            if [[ "$autoImportLists" == "true" ]]; then
                ImportMultiColStyListViaCSV "$studyListFile" "$label" "$MigDB"
            else
                Message "Auto import list is not enabled for $label"
            fi
        else
            Message "Failed to retrieve or find study list file for $label"
        fi
    done

    refresh_verification
}
Usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -h, --help                      Display this help message."
    echo "  --install                       Perform a fresh installation of the system."
    echo "  --fetch-all <from>              Fetch the study list and output to a file."
    echo "                                  <from> must be either 'source' or 'target'."
    echo "  -a, --all <file_path> [<system_label> [<database_name>]]"
    echo "                                  Import multiple study records from a CSV file."
    echo "                                  If <system_label> is omitted, the system label is"
    echo "                                  automatically extracted from the filename, which"
    echo "                                  should be in the format: study-list_<label>_<timestamp>.tsv"
    echo "  -t, --insert-system <config_file>"
    echo "                                  Insert or update a system record from the specified"
    echo "                                  configuration file."
    echo "  -u                              Refresh verification and mark target-only exams."
    echo "  -q, --quiet                     Run in batch mode without interactive prompts."
    echo "Note: Additional flags and options are available for specific functions."
}
parse_options() {
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -h|--help)
                Usage
                exit 0
                ;;
            --install)
                FreshInstall
                exit 0
                ;;
            --fetch-all)
                # TODO: FetchStudyList fails if internal IP is empty
                resolved_label=$(resolve_system_label "$2")
                FetchStudyList "$resolved_label"
                shift 2
                ;;
            -a|--all)
                file_path="$2"
                db="$MigDB"

                # Determine if a label was provided (next arg doesn’t start with “-”)
                if [[ $# -ge 3 && ! "$3" =~ ^- ]]; then
                    resolved_label=$(resolve_system_label "$3")

                    # Determine if a custom database name was provided
                    if [[ $# -ge 4 && ! "$4" =~ ^- ]]; then
                        db="$4"
                        shift_count=4
                    else
                        shift_count=3
                    fi
                else
                    # No label provided → infer from filename
                    base=$(basename "$file_path") # Extract system label from the filename.
                    extracted_label=${base#study-list_} # Remove prefix "study-list_"
                    extracted_label=${extracted_label%_*} # Remove the suffix starting from the last underscore
                    resolved_label="$extracted_label"
                    shift_count=2
                fi

                ImportMultiColStyListViaCSV "$file_path" "$resolved_label" "$db"
                shift $shift_count
                ;;
            -u)
                refresh_verification "$MigDB"
                set_skip_for_target_only_exams "$MigDB"
                exit 0
                ;;
            -U)
                AutoRetrieveAndImportStudyLists
                refresh_verification "$MigDB"
                set_skip_for_target_only_exams "$MigDB"
                exit 0
                ;;
            -t|--insert-system)
                upsert_system_from_file "$(pwd)/$2" "$MigDB"
                shift 2
                ;;
            -q|--quiet)
                BatchMode=true
                shift 1
                ;;
            *)
                echo "Unknown option: $1" >&2
                Usage
                exit 1
                ;;
        esac
    done
}
main() {
    [ "$USER" != "medsrv" ] && Message -d "This script must be run as medsrv! Exiting..." && exit 1
    initialize_environment
    CreateDirectories "$_STYLIST_DIR" "$_LOG_DIR"

    if [ "$#" -eq 0 ]; then
        Usage
        exit 0
    fi

    parse_options "$@"
}

main "$@"
