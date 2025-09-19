#!/bin/bash

# Define the functions

DisplayLargestFiles() {
    find $PWD -type f -exec ls -s --block-size=M {} + | sort -n -r | head -10
}

DisplayDatabaseSize() {
    sql.sh "SELECT table_schema 'DB Name', ROUND(SUM(data_length + index_length) / 1024 / 1024, 1) 'DB Size in MB' FROM information_schema.tables GROUP BY table_schema;" -t
}

DisplayDatabaseTablesSize() {
    sql.sh "SELECT table_schema as 'Database', table_name AS 'Table', round(((data_length + index_length) / 1024 / 1024), 2) 'Size in MB' FROM information_schema.TABLES ORDER BY (data_length + index_length) DESC limit 10;" -t
}

DropSelectedDatabase() {
    read -p "Enter the name of the database you wish to drop: " dbName
    read -p "Are you sure you want to drop database $dbName? This operation is irreversible. (y/n): " confirmation
    if [[ "$confirmation" = "y" || "$confirmation" = "Y" ]]; then
        sql.sh "DROP DATABASE IF EXISTS ${dbName};" -t
        echo "Database $dbName has been dropped."
    else
        echo "Operation cancelled."
    fi
}

DropDatabaseTable() {
    read -p "Enter the name of the database that contains the table: " dbName
    read -p "Enter the name of the table you wish to drop: " tableName
    read -p "Are you sure you want to drop table $tableName from database $dbName? This operation is irreversible. (y/n): " confirmation
    if [[ "$confirmation" = "y" || "$confirmation" = "Y" ]]; then
        sql.sh "USE ${dbName}; DROP TABLE IF EXISTS ${tableName};" -t
        echo "Table $tableName has been dropped from database $dbName."
    else
        echo "Operation cancelled."
    fi
}

# Display menu and handle user input

while true; do
    echo "Select an action:"
    echo "1. Display the 10 largest files"
    echo "2. Display database sizes"
    echo "3. Display top 10 database tables by size"
    echo "4. Drop a selected database"
    echo "5. Drop a database table"
    echo "6. Exit"
    read -p "Enter your choice: " choice

    case $choice in
        1) DisplayLargestFiles ;;
        2) DisplayDatabaseSize ;;
        3) DisplayDatabaseTablesSize ;;
        4) DropSelectedDatabase ;;
        5) DropDatabaseTable ;;
        6) echo "Exiting..."; exit 0 ;;
        *) echo "Invalid choice. Please select a valid option." ;;
    esac
    echo
done
