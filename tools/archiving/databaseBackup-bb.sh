#!/bin/bash

# Define all required variables before running
MYSQL_ROOT_PW="ec3tera"
db_to_backup=""
WDIR=""
backup_dir="backup"
crm_case_number=""

backup_sql_filename="case-${crm_case_number}_$(date +%Y%m%d_%H%M%S).sql"
backup_zip_filename="${backup_sql_filename}.zip"

mysql="/home/medsrv/component/mysql/bin/mysqldump"
mysql_opts="--add-drop-database --add-drop-table --complete-insert --add-locks -u root --password=\"$MYSQL_ROOT_PW\""
mysql_dump_file="$WDIR/$backup_dir/$backup_sql_filename"
mysqldump_cmd="$mysql -v $mysql_opts $db_to_backup > $mysql_dump_file 2>/dev/null"

zip_outfile="$WDIR/$backup_dir/$backup_zip_filename"
zip_cmd="zip $zip_outfile $mysql_dump_file"

# Check for empty required variables
for var in MYSQL_ROOT_PW db_to_backup WDIR backup_dir crm_case_number; do
    if [ -z "${!var}" ]; then
        echo "ERROR: Variable '$var' is not set. Edit the script and set all required variables."
        exit 1
    fi
done

# Run mysqldump
if eval $mysqldump_cmd; then
    echo "Backup completed for database - $db_to_backup"
else
    echo "Backup failed for database - $db_to_backup"
    exit 1
fi

# Compress the backup
if eval $zip_cmd; then
    echo "Database backup compressed successfully"
else
    echo "Compression failed for file - $backup_zip_filename"
    exit 1
fi