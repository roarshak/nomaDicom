#!/bin/bash
# shellcheck disable=SC2155

# 6/25/2024 16:36 PM Latest results
# Total files scanned: 7,766
# DICOM files found: 7,408
# [medsrv@migtesting-v7source ~]$
# [medsrv@migtesting-v7source ~]$ head foundDcmFiles.txt
# StudyInstanceUID,SOPInstanceUID,FilePath
# 1.3.39.19600601.2.2.999.20181016.150025778.25813        2.16.840.1.113662.4.1314809300303.1540332572.128500058042840    /home/medsrv/data/dicom.repository/data0/MH/8S/KX/1.3.39.19600601.2.2.999.20181016.150025778.25813/MR.2.16.840.1.113662.4.1314809300303.1540332572.128500058042840
# 1.3.39.19600601.2.2.999.20181016.150025778.25813        2.16.840.1.113662.4.1314809300303.1540333193.130613831872928    /home/medsrv/data/dicom.repository/data0/MH/8S/KX/1.3.39.19600601.2.2.999.20181016.150025778.25813/MR.2.16.840.1.113662.4.1314809300303.1540333193.130613831872928
# 1.3.39.19600601.2.2.999.20181016.150025778.25813        2.16.840.1.113662.4.1314809300303.1540333001.129961082114499    /home/medsrv/data/dicom.repository/data0/MH/8S/KX/1.3.39.19600601.2.2.999.20181016.150025778.25813/MR.2.16.840.1.113662.4.1314809300303.1540333001.129961082114499


# DEFAULTS
start_dir="."
output_file="foundDcmFiles.txt"

isDicom() {
    local f=$1
    local ftype

    [ ! -f "$f" ] && { echo "$f is a unicorn" ; return 0 ; }
    ftype=$(file -b $f 2>/dev/null)
    if [ "DICOM medical imaging data" == "$ftype" ]; then
        return 0
    else
        return 1
    fi
}

# Function to process DICOM files in a directory and output results
process_dicom_files() {
    local dashboard="dashboard.txt"

    # Initialize counters
    local total_files=0
    local dicom_files=0

    # Check if dcmdump exists
    if [ ! -x "/home/medsrv/component/dicom/bin/dcmdump" ]; then
        echo "dcmdump is not available. Exiting."
        return 1
    fi

    # Function to update the dashboard
    update_dashboard() {
        local total_files="$1"
        local dicom_files="$2"
        echo "Total files scanned: $total_files" > "$dashboard"
        echo "DICOM files found: $dicom_files" >> "$dashboard"
    }

    # Header for the CSV file
    echo "StudyInstanceUID,SOPInstanceUID,FilePath" > "$output_file"

    # Find files and process them
    find "$start_dir" -type f | while read -r f; do
        # Update file count
        total_files=$((total_files + 1))

        # Check if file is a DICOM file by looking for DICM at offset 128
        if [ "$(dd if="$f" bs=1 skip=128 count=4 2>/dev/null)" = "DICM" ]; then
            dicom_files=$((dicom_files + 1))

            # Extract identifiers
            local styiuid="$($HOME/component/dicom/bin/dcmdump +P 0020,000d "$f" | sed 's/^.*\[\(.*\)\].*$/\1/')"
            local sopiuid="$($HOME/component/dicom/bin/dcmdump +P 0008,0018 "$f" | sed 's/^.*\[\(.*\)\].*$/\1/')"

            # Write to CSV file
            echo -e "$styiuid\t$sopiuid\t$f" >> "$output_file"
        fi

        # Update and display the dashboard every 25 files without scrolling
        # if [ $((total_files % 25)) -eq 0 ]; then
        #     update_dashboard "$total_files" "$dicom_files"
        #     clear
        #     cat "$dashboard"
        # fi
        clear
        printf "Total files scanned: %'d\n" "$total_files"
        printf "DICOM files found: %'d\n" "$dicom_files"
    done

    # Final dashboard update and display without clearing the counts
    # update_dashboard
    # clear
    # cat "$dashboard"
}

# Parse command-line options
while getopts ":d:o:" opt; do
  case ${opt} in
    d ) start_dir=$OPTARG ;;
    o ) output_file=$OPTARG ;;
    \? ) echo "Usage: cmd [-d directory] [-o output_file]"
         return 1 ;;
  esac
done

# Run the function with directory and output file parameters
process_dicom_files "$start_dir" "$output_file"
