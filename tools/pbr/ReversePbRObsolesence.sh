#!/bin/bash

# Initialize default values
whatif_mode=0
dicom_file=""
pbr_filename=""

# Function to show usage information
usage() {
    echo "Usage: $0 -f <DICOM_file> -p <PbR_filename> [--whatif]"
    echo "  -f <DICOM_file>      Specify the DICOM file to modify."
    echo "  -p <PbR_filename>    Specify the PbR filename to remove from the obsolete sequence."
    echo "  --whatif             Run in what-if mode. No changes will be made to the file."
    exit 1
}

# Parse command-line options
parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -f) dicom_file="$2"; shift 2 ;;
            -p) pbr_filename="$2"; shift 2 ;;
            --whatif) whatif_mode=1; shift ;;
            -h|--help) usage ;;
            *) echo "Unknown option: $1"; usage ;;
        esac
    done
}

# Validate required parameters
validate_params() {
    if [ -z "$dicom_file" ] || [ -z "$pbr_filename" ]; then
        echo "Error: DICOM file and PbR filename must be specified."
        usage
    fi
}

# Determine the absolute path of the DICOM file
resolve_dicom_path() {
    if [[ "$dicom_file" != /* ]]; then
        local local_choice=""
        if [ -f "$dicom_file" ]; then
            local_choice="./$dicom_file"
        fi

        local styiuid=$(sql.sh "select styiuid from Dcobject where fname='$dicom_file' limit 1" -N)
        local repository_path=$(/home/medsrv/component/repositoryhandler/scripts/locateStudy.sh -d "$styiuid")

        if [ -n "$local_choice" ] && [ -n "$repository_path" ]; then
            echo "Multiple instances of the DICOM file found:"
            echo "1) Local directory: $local_choice"
            echo "2) Repository: $repository_path"
            read -p "Select the file to operate on (1 or 2): " file_choice

            case $file_choice in
                1) dicom_file="$local_choice" ;;
                2) dicom_file="$repository_path" ;;
                *) echo "Invalid selection. Exiting."; exit 1 ;;
            esac
        elif [ -n "$repository_path" ]; then
            dicom_file="$repository_path"
        elif [ -n "$local_choice" ]; then
            dicom_file="$local_choice"
        else
            echo "No valid DICOM file found. Exiting."
            exit 1
        fi
    fi
}

# Extract SOP Instance UID from PbR filename
extract_sop_uid() {
    sop_instance_uid=$($DCDUMP +P SOPInstanceUID $pbr_filename | awk '{print $3}' | sed 's/\[//g;s/\]//g')
    # sop_instance_uid=$($DCDUMP +P "0008,0018" $pbr_filename | awk -F'[' '{print $2}' | awk -F']' '{print $1}')
    # sop_instance_uid=$($DCDUMP +P "0008,1155" $pbr_filename | awk '{print $3}' | sed 's/\[//g;s/\]//g')
    echo "Extracted SOP Instance UID: $sop_instance_uid"
}
find_item_indexes_OG() {
    # This will dump the ObsoleteObjectSequence and filter out the required SOPInstanceUID along with its preceding item marker (fffe,e000)
    item_indexes=$($DCDUMP +P "f215,1046" "$dicom_file" | grep -B 2 "$sop_instance_uid" | grep "(fffe,e000)" | awk '{print NR}')
    echo "Item indexes to be removed: $item_indexes"
}
find_item_indexes() {
    # This will dump the ObsoleteObjectSequence and filter out the required SOPInstanceUID along with its preceding item marker (fffe,e000)
    item_indexes=$($DCDUMP "$dicom_file" | grep -A 2 "(fffe,e000)" | grep "$sop_instance_uid" -B 1 | grep "(fffe,e000)" | awk '{print NR}')
    echo "Item indexes to be removed: $item_indexes"
}

# Modify DICOM file
modify_dicom() {
    local backup_file="${dicom_file}.bak"
    cp "$dicom_file" "$backup_file"

    # local item_indexes=$($DCDUMP "$dicom_file" | grep -B 1 "$sop_instance_uid" | grep "(fffe,e000)" | awk -F'[][]' '{print $2}')

    for index in $item_indexes; do
        local tag_path="(f215,1046)[$index]"
        if [ "$whatif_mode" -eq 1 ]; then
            echo "Would remove item at $tag_path containing PbR filename '$pbr_filename'."
        else
            $DCMODIFY -e "$tag_path" "$dicom_file"
            if [ $? -eq 0 ]; then
                echo "Successfully removed item at $tag_path containing PbR filename '$pbr_filename'."
            else
                echo "Failed to remove item at $tag_path."
                cp "$backup_file" "$dicom_file"
                exit 1
            fi
        fi
    done
    echo "All matched items have been processed."
}

main() {
    parse_args "$@"
    validate_params
    resolve_dicom_path
    extract_sop_uid
    find_item_indexes
    modify_dicom
}

# Path to DCMTK tools
DCMTK_BIN="/home/medsrv/component/dcmtk/bin"
DCMODIFY="${DCMTK_BIN}/dcmodify"
DCDUMP="${DCMTK_BIN}/dcmdump"

main "$@"