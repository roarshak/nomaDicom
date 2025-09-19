#!/bin/bash

# Function to display usage information
usage() {
    echo "Usage: $0 [--generate] | [<input_list_file> <parent_device>]"
    echo
    echo "Options:"
    echo "  --generate         Generate the input list using SQL and process it."
    echo "  <input_list_file>  Path to the file containing the list of styiuids (one per line)."
    echo "  <parent_device>    The name of the parent device to apply as 'staged'."
    echo
    echo "Example:"
    echo "  $0 styiuids.txt CrescentMedicalCenter"
    echo "  $0 --generate CrescentMedicalCenter"
    exit 1
}

# Ensure the script is run by the user "medsrv"
if [[ "$(whoami)" != "medsrv" ]]; then
    echo "This script must be run as the user 'medsrv'."
    exit 1
fi

# Check arguments for mutually exclusive options
if [[ "$#" -eq 1 && "$1" == "--generate" ]]; then
    generate_list=true
    parent_device="$2"
elif [[ "$#" -eq 2 ]]; then
    generate_list=false
    input_list="$1"
    parent_device="$2"
else
    echo "Error: Incorrect or missing arguments."
    usage
fi

storestate_cmd="/home/medsrv/component/utils/bin/storestate"
sql_cmd="sql.sh \"SELECT styiuid From Dcstudy WHERE mainst>='0'\" -N"
log_file="/var/log/study_processing_failures.log"

# Create or clear the log file at the start of execution
: > "$log_file"

# Handle self-generated input list
if [[ "$generate_list" == true ]]; then
    echo "Generating input list using SQL command..."
    input_list="/tmp/generated_study_list.txt"
    eval "$sql_cmd" > "$input_list"

    if [[ "$?" -ne 0 || ! -s "$input_list" ]]; then
        echo "Error: Failed to generate input list or list is empty."
        exit 1
    fi

    echo "Generated input list saved to: $input_list"
fi

# Validate provided input list file
if [[ "$generate_list" == false ]]; then
    if [[ ! -f "$input_list" ]]; then
        echo "Error: Input list file '$input_list' does not exist."
        usage
    fi

    if [[ ! -r "$input_list" ]]; then
        echo "Error: Input list file '$input_list' is not readable."
        usage
    fi
fi

# Iterate over each line in the input file
while read -r styiuid || [[ -n "$styiuid" ]]; do
    # Skip empty lines
    if [[ -z "$styiuid" ]]; then
        continue
    fi

    # Execute the storestate command
    echo "Processing styiuid: $styiuid"
    "$storestate_cmd" --study="$styiuid" --setstaged="$parent_device"

    # Check for errors in command execution and log failures
    if [[ "$?" -ne 0 ]]; then
        echo "Failed to process styiuid: $styiuid"
        echo "$(date '+%Y-%m-%d %H:%M:%S') Failed to process styiuid: $styiuid" >> "$log_file"
    else
        echo "Successfully processed styiuid: $styiuid"
    fi
done < "$input_list"

echo "Processing complete."

# Cleanup generated input list
if [[ "$generate_list" == true ]]; then
    echo "Cleaning up generated input list..."
    rm -f "$input_list"
fi

echo "Failures logged to: $log_file"
