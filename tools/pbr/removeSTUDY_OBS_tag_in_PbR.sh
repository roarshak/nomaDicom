#!/bin/bash

# Function to display usage information
usage() {
    echo "Usage: $0 -S <suid> -P <pbr_file>"
    exit 1
}

# Parse command line arguments
while getopts "S:P:" opt; do
    case ${opt} in
        S )
            suid=$OPTARG
            ;;
        P )
            pbr_file=$OPTARG
            ;;
        \? )
            usage
            ;;
    esac
done

# Check if both SUID and PbR file are provided
if [ -z "$suid" ] || [ -z "$pbr_file" ]; then
    usage
fi

# Locate the study directory
stydir="$(~/component/repositoryhandler/scripts/locateStudy.sh -d $suid)"

# Combine study directory with PbR file to get the full file path
file_path="${stydir}/${pbr_file}"

# Dump DICOM metadata and filter for "obsol"
/home/medsrv/component/dcmtk/bin/dcmdump "$file_path" | grep -i "obsol"

# Copy the file to the current directory
cp -va "$file_path" .

# Show the modify command and ask for confirmation
modify_command="/home/medsrv/component/dcmtk/bin/dcmodify -e 'f215,1045' $file_path"
echo "The following command will be executed to modify the DICOM file:"
echo $modify_command
read -p "Do you want to proceed? (yes/no): " confirmation

if [ "$confirmation" != "yes" ]; then
    echo "Modification cancelled."
    exit 0
fi

# Execute the modify command
$modify_command

# Remove the backup file created by dcmodify
rm "${file_path}.bak"
