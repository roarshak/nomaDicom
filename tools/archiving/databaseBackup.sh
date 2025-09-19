#!/bin/bash
#shelsdflcheck disable=SC2154,SC3045,SC1090

print_usage() {
    echo "Usage: $0 [-d database] [-b backup_dir] [-B batch_mode] [-h]"
    echo "  -d database     Specify the database to back up"
    echo "  -b backup_dir   Specify the backup directory"
    echo "  -B batch_mode   Set batch mode (true/false)"
    echo "  -h              Show this help message"
}
initialize_script_variables() {
    local script_name="$1"
    _SCRIPT_NAME="${script_name}"
    _SCRIPT_CFG="${script_name%.*}.cfg"
    _SCRIPT_LOG="${script_name%.*}.log"
}
executeDatabaseBackup() {
    initialize_environment
    CreateDirectories "${_WDIR}/${backup_dir}"
    _backup_sql_filename="case-${crm_case_number}_$(date +%Y%m%d_%H%M%S).sql"
    _backup_zip_filename="${_backup_sql_filename}.zip"
    printf "Backup started for database - %s\n" "$db_to_backup"
    if /home/medsrv/component/mysql/bin/mysqldump -v --add-drop-database --add-drop-table --complete-insert --add-locks -u root --password="$MYSQL_ROOT_PW" "${db_to_backup}" >"${_WDIR}/${backup_dir}/${_backup_sql_filename}" 2>/dev/null; then
        printf "Backup completed for database - %s\n" "$db_to_backup"
    else
        printf "%s Backup failed for database - %s\n" "$db_to_backup" "$(date)"
        exit 1
    fi

    if zip "${_WDIR}/${backup_dir}/$_backup_zip_filename" "${_WDIR}/${backup_dir}/$_backup_sql_filename"; then
        # rm --preserve-root -f "${_WDIR}/${backup_dir}/$_backup_sql_filename"
        printf "Database backup compressed successfully\n"
    else
        printf "%s Compression failed for file - %s\n" "${_backup_zip_filename}" "$(date)"
        exit 1
    fi

    # find "${_WDIR}/${backup_dir}" -mtime +"${_DAYS_TO_RETAIN_DB_BACKUPS:=14}" -delete
    return 0
}
main() {
    initialize_script_variables "databaseBackup.sh"  # Sets: _SCRIPT_NAME, _SCRIPT_CFG, _SCRIPT_LOG
    # Prompt the user for the database name
    if [ -z "$migration_database" ]; then
        read -r -p "Enter the name of the database you wish to back up: " db_to_backup
    else
        db_to_backup="$migration_database"
    fi

    # Execute the backup
    if executeDatabaseBackup; then
        echo "Backup completed successfully."
    else
        echo "Backup failed. Please check the logs."
    fi
}

while [ $# -gt 0 ]; do
    case "$1" in
        -d|--database)
            migration_database="$2"; shift 2;;
        -c|--case)
            crm_case_number="$2"; shift 2;;
        -b|--backup_dir)
            backup_dir="$2"; shift 2;;
        -B|--batch_mode)
            BatchMode="$2"; shift 2;;
        -h|--help)
            print_usage; exit 0;;
        *)
            echo "Unknown option: $1"; print_usage
            exit 1;;
    esac
done

main
