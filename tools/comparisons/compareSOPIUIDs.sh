#!/bin/bash

AE_TITLE=""
. /home/medsrv/var/dicom/pb-scp.cfg #To get "AE_TITLE" variable
study_instance_uid="$1"

# Can arbitrarily set these here if desired
Source_AET=""
Source_IP=""
Source_Port=""
Target_IP=""
Target_AET=""
Target_Port=""

# Override values above with values from migration.cfg if present
if [[ -f "migration.cfg" ]]; then
  . migration.cfg
fi

# Unused
# Source_Device=""
# Source_Label="V7 PACS"
# Target_Device=""
# Target_Label="EVO PACS"

create_temp_dir() {
    local dir="$1"
    [[ ! -d "$dir" ]] && mkdir -p "$dir"
}
retrieve_local_sopiuids() {
    local study_instance_uid="$1"
    local temp_dir="$2"
    sql.sh "SELECT SOPIUID FROM imagemedical.Dcobject WHERE STYIUID = '${study_instance_uid}'" -N >"${temp_dir}/${study_instance_uid}/local_sopiuids.txt"
}
retrieve_sopiuids() {
    local system_type="$1"  # 'source' or 'target'
    local study_instance_uid="$2"
    local AE_TITLE="$3"
    local call_aet="$4"
    local call_ip="$5"
    local call_port="$6"
    local temp_dir="$7"
    local findscu_path="/home/medsrv/component/dicom/bin/findscu"
    local output_file="${temp_dir}/${study_instance_uid}/${system_type}_sopiuids.txt"
    local findscu_options="--aetitle $AE_TITLE --key 0008,0052=IMAGE --key 0020,000D=$study_instance_uid --key 0008,0018"

    echo "Retrieving SOP Instance UIDs for study $study_instance_uid from $system_type system..."

    local command="$findscu_path -S $findscu_options --call $call_aet $call_ip $call_port"

    # Execute the findscu command and process the output
    echo "Command: ~/component/dicom/bin/findscu -S --aetitle $AE_TITLE --key 0008,0052=IMAGE --key 0020,000D=$study_instance_uid --key 0008,0018 --call $call_aet $call_ip $call_port | grep SOPInstanceUID | cut -d \"[\" -f2 | cut -d \"]\" -f1"
    local seriuid_sopiuids=$($command 2>&1 | grep SOPInstanceUID | cut -d "[" -f2 | cut -d "]" -f1)
    echo "$seriuid_sopiuids" > "$output_file"

    echo "SOP Instance UIDs retrieved and saved to $output_file"

    # Retrieve SOP Instance UIDs from local system
    #retrieve_sopiuids "local" "$study_instance_uid" "$AE_TITLE" "$AE_TITLE" "localhost" "104" "$temp_dir"
    # Retrieve SOP Instance UIDs from remote system
    #retrieve_sopiuids "remote" "$study_instance_uid" "$AE_TITLE" "$source_aet" "$source_ip" "$source_port" "$temp_dir"
}
compare_sopiuids() {
    local study_instance_uid="$1"
    local temp_dir="$2"
    comm -23 "${temp_dir}/${study_instance_uid}/source_sopiuids.txt" "${temp_dir}/${study_instance_uid}/target_sopiuids.txt" >"${temp_dir}/${study_instance_uid}/missing_sopiuids.txt"
}
handle_missing_sopiuids() {
    local study_instance_uid="$1"
    local temp_dir="$2"
    local target_pacs_qr_aet="$3"
    local Source_AET="$4"
    local Source_IP="$5"
    local Source_Port="$6"
    local missing_sopiuids="$(cat "${temp_dir}/${study_instance_uid}/missing_sopiuids.txt")"
    
    for missing_sopiuid in $missing_sopiuids; do
        # Simulate storescu execution, handle errors, etc.
        # Update the database based on success/failure
        echo "Process missing SOPIUID: $missing_sopiuid"
    done
}
final_report_and_db_update() {
    local study_instance_uid="$1"
    local temp_dir="$2"
    local missing_count="$(wc -l <"${temp_dir}/${study_instance_uid}/missing_sopiuids.txt")"
    echo "Final report for $study_instance_uid: $missing_count missing SOP Instance UIDs"

    if [[ $verbose -eq 1 ]]; then
        echo "Verbose Output: Side-by-Side Comparison of SOP Instance UIDs"
        echo -e "Source SOP Instance UIDs\tTarget SOP Instance UIDs"
        paste "${temp_dir}/${study_instance_uid}/source_sopiuids.txt" "${temp_dir}/${study_instance_uid}/target_sopiuids.txt"
        echo "Missing SOP Instance UIDs:"
        cat "${temp_dir}/${study_instance_uid}/missing_sopiuids.txt"
    fi
}
# Main script execution
main() {
    if [[ -z "$study_instance_uid" ]]; then
        echo "Usage: $0 -u <Study_Instance_UID> [-a <Source_AET>] [-i <Source_IP>] [-p <Source_Port>] [-A <Target_AET>] [-I <Target_IP>] [-P <Target_Port>]"
        exit 1
    fi

    local temp_dir="$(pwd)/tmp"
    create_temp_dir "${temp_dir}/${study_instance_uid}"
    # retrieve_local_sopiuids "$study_instance_uid" "$temp_dir"
    retrieve_sopiuids "source" "$study_instance_uid" "$AE_TITLE" "$Source_AET" "$Source_IP" "$Source_Port" "$temp_dir"
    retrieve_sopiuids "target" "$study_instance_uid" "$AE_TITLE" "$Target_AET" "$Target_IP" "$Target_Port" "$temp_dir"
    compare_sopiuids "$study_instance_uid" "$temp_dir"
    # handle_missing_sopiuids "$study_instance_uid" "$temp_dir" "TargetAET" "$Source_AET" "$Source_IP" "$Source_Port"
    final_report_and_db_update "$study_instance_uid" "$temp_dir"
}

while getopts ":s:a:i:p:A:I:P:v" opt; do
  case $opt in
    s) study_instance_uid="$OPTARG" ;;
    a) Source_AET="$OPTARG" ;;
    i) Source_IP="$OPTARG" ;;
    p) Source_Port="$OPTARG" ;;
    A) Target_AET="$OPTARG" ;;
    I) Target_IP="$OPTARG" ;;
    P) Target_Port="$OPTARG" ;;
    v) verbose=1 ;;
    \?) echo "Invalid option -$OPTARG" >&2; exit 1 ;;
    :) echo "Option -$OPTARG requires an argument." >&2; exit 1 ;;
  esac
done

main "$@"
