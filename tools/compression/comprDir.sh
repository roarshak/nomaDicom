#!/bin/sh
workdir="$(pwd)"
# Log file for errors and skipped entries
log_file="$workdir/log_file.log"

# File containing the STYIUIDs, one per line
suid_file="$workdir/suid_list.txt"

# Loop through each line in the suid file
while read -r suid; do
    # Check time
    bash checkTime.sh
    
    echo "Processing STYIUID: $suid"

    # Locate the study directory
    study_dir=$(~/component/repositoryhandler/scripts/locateStudy.sh -d "$suid")

    # Count the number of lines returned
    line_count=$(echo "$study_dir" | wc -l)

    # Check if exactly one line was returned and it is a directory
    if [ "$line_count" -eq 1 ] && [ -d "$study_dir" ]; then
        echo "Found study directory: $study_dir"

        # Call compressDirectory.sh on the study directory
        bash /home/medsrv/ASP_compression/compressDirectory.sh "$study_dir" >/dev/null 2>&1

    else
        # Log the skipped entry
        echo "Skipped STYIUID: $suid. Multiple directories or non-directory found." >> "$log_file"
    fi

done < "$suid_file"

echo "Finished processing all STYIUIDs."
