#!/bin/bash
#
# DATE: 1/18/2022
# AUTHOR: Joel Booth
# PURPOSE: Generate input study list via DICOM with argument parsing, validation, and tagged comments

# Local (this server) DICOM values
. $DICOM_VAR/pb-scp.cfg

# Defaults
QRIP="172.25.3.12"
QRPORT=104
QRAE_TITLE="SCHCSCP"
QRROOT="S"
startdate=$(date --date='yesterday' +%Y%m%d)  # Set the start date to yesterday
stopdate=$(date --date="$startdate -10 years" +%Y%m%d)  # Stop date is 10 years before the start date
suid=""  # Empty means include the StudyInstanceUID in response without filtering
accnum=""  # Accession Number, empty means include it in the response without filtering
instname=""  # Institution Name, empty means include it in the response without filtering
patid=""  # Patient ID, empty means include it in the response without filtering
patname=""  # Patient Name, empty means include it in the response without filtering
modality=""  # Modality, empty means include it in the response without filtering

# Help message
function print_help {
  echo "Usage: $0 [OPTIONS]"
  echo "Options:"
  echo "  --QRIP <IP Address>               Set the IP address of the DICOM server (default: 172.25.3.12)"
  echo "  --QRPORT <Port>                   Set the port of the DICOM server (default: 104)"
  echo "  --QRAE_TITLE <AE Title>           Set the AE Title of the DICOM server (default: SCHCSCP)"
  echo "  --QRROOT <Root>                   Set the QR Root (default: S)"
  echo "  --startdate <YYYYMMDD>            Set the start date for querying (default: yesterday)"
  echo "  --stopdate <YYYYMMDD>             Set the end date for querying (default: startdate - 10 years)"
  echo "  --suid <StudyInstanceUID>         Specify a StudyInstanceUID to filter by (default: include all)"
  echo "  --accnum <Accession Number>       Specify an Accession Number to filter by (default: include all)"
  echo "  --instname <Institution Name>     Specify an Institution Name to filter by (default: include all)"
  echo "  --patid <Patient ID>              Specify a Patient ID to filter by (default: include all)"
  echo "  --patname <Patient Name>          Specify a Patient Name to filter by (default: include all)"
  echo "  --modality <Modality>             Specify a Modality to filter by (default: include all)"
  echo "  -h, --help                        Display this help and exit"
}

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --QRIP)
      QRIP="$2"
      shift 2
      ;;
    --QRPORT)
      QRPORT="$2"
      shift 2
      ;;
    --QRAE_TITLE)
      QRAE_TITLE="$2"
      shift 2
      ;;
    --QRROOT)
      QRROOT="$2"
      shift 2
      ;;
    --startdate)
      startdate="$2"
      shift 2
      ;;
    --stopdate)
      stopdate="$2"
      shift 2
      ;;
    --suid|--accnum|--instname|--patid|--studydate|--patname|--modality)
      eval ${1:2}="$2"
      shift 2
      ;;
    -h|--help)
      print_help
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      print_help
      exit 1
      ;;
  esac
done

# Validate required parameters
function validate_params {
  local errors=0

  # Check for empty parameters
  for param in QRIP QRPORT QRAE_TITLE QRROOT startdate stopdate; do
    if [[ -z "${!param}" ]]; then
      echo "ERROR: $param is required but not set."
      ((errors++))
    fi
  done

  # Check for specific format requirements (could add regex checks here)
  if ! [[ $QRPORT =~ ^[0-9]+$ ]]; then
    echo "ERROR: QRPORT must be a numeric value."
    ((errors++))
  fi

  if ! [[ $startdate =~ ^[0-9]{8}$ ]] || ! [[ $stopdate =~ ^[0-9]{8}$ ]]; then
    echo "ERROR: startdate and stopdate must be in YYYYMMDD format."
    ((errors++))
  fi

  # Compare dates to ensure startdate is not after stopdate
  # FIXME: 
  if [[ $startdate -lt $stopdate ]]; then
    echo "ERROR: startdate must be later than stopdate for backward processing."
    ((errors++))
  fi

  # Exit if there are errors
  if [[ $errors -ne 0 ]]; then
    exit 1
  fi
}

# Call the validation function
validate_params

# Define findscu options as an array with comments on DICOM tags
findscu_baseopts=(
    "-$QRROOT"                                # QR Root
    "--aetitle $AE_TITLE"                     # AE Title of the local DICOM application
    "--key 0008,0052=STUDY"                   # Query/Retrieve Level (STUDY)
)

# Define findscu options as an array with comments on DICOM tags
findscu_columns=(
    "--key 0008,0050"           # Accession Number
    # "--key 0020,000D"             # StudyInstanceUID
    # "--key 0020,000D=\"${suid}\""             # StudyInstanceUID
    # "--key 0008,0050=\"${accnum}\""           # Accession Number
    # "--key 0008,0080=\"${instname}\""         # Institution Name
    # "--key 0010,0020=\"${patid}\""            # Patient ID
    # "--key 0010,0010=\"${patname}\""          # Patient Name
    # "--key 0008,0060=\"${modality}\""         # Modality
)

# Function to log and execute the findscu command
function exe_findNlog () {
  singleDate="$1"
  [[ -z "$singleDate" ]] && { echo "ERROR: Required variable singleDate missing, exiting"; exit; }

  # Make a findscu_opts array that has the findscu_baseopts, the query date, findscu_columns, and then "--call $QRAE_TITLE $QRIP $QRPORT"
  findscu_options=("${findscu_baseopts[@]}" "--key 0008,0020=\"${singleDate}\"" "${findscu_columns[@]}" "--call $QRAE_TITLE $QRIP $QRPORT")

  # Assemble the findscu command with options from the array
  findscu_command="~/component/dicom/bin/findscu $QRDEBUG ${findscu_options[@]}"
  
  # Execute the command and capture the response
  findscu_response=$(eval $findscu_command 2>&1)
  findscu_return_code=$?

  # Check if the command was successful
  if [ $findscu_return_code -ne 0 ]; then
      echo "$(date) Error querying archive" | tee -a brfinderr.log
      echo "$findscu_response" | tee -a brfinderr.log
      return 1
  fi

  # Log the response to a separate file
  echo "$findscu_command" >> findscu_commands.log
  echo "$findscu_response" >> brfind.log

  # Extract data using the newly added function and print
  Extract_DCM_Tag_Values_From_FindSCU_Response "$findscu_response"
}

# TODO: This function needs some work
Extract_DCM_Tag_Values_From_FindSCU_Response() {
	findscu_response="$1"
	# Use grep and cut to extract the relevant information from the file
	PatientID=$(printf "%s" "$findscu_response" | grep "(0010,0020)\|PatientID" | cut -d ' ' -f 3 | tr -d '[]')
	NumberOfStudyRelatedInstances="$(printf "%s" "$findscu_response" | grep "(0020,1208)\|NumberOfStudyRelatedInstances" | cut -d ' ' -f 3 | tr -d '[]')"
	StudyDate="$(printf "%s" "$findscu_response" | grep "(0008,0020)\|StudyDate" | cut -d ' ' -f 3 | tr -d '[]')"
	Modality="$(printf "%s" "$findscu_response" | grep "(0008,0061)\|Modality" | cut -d ' ' -f 3 | tr -d '[]')"
	AccessionNumber="$(printf "%s" "$findscu_response" | grep "(0008,0050)\|AccessionNumber" | cut -d ' ' -f 3 | tr -d '[]')"
	ErrorMsg="$(printf "%s" "$findscu_response" | grep "(0000,0902)\|ErrorComment")"

  # Add a printf line to show the command.
  printf "Command: %s\n" "$findscu_command"
  # Add a printf line to show the filters
  printf "Filters: suid=%s accnum=%s instname=%s patid=%s studydate=%s patname=%s modality=%s\n" "$suid" "$accnum" "$instname" "$patid" "$singleDate" "$patname" "$modality"
  # Add a printf line to show the AccessionNumber, converting new lines to comma plus space
  printf "AccessionNumber: %s\n" "$(echo "$AccessionNumber" | tr '\n' ', ')"
  # Add a printf line to show the extracted values
  # printf "PatientID: %s\nNumberOfStudyRelatedInstances: %s\nStudyDate: %s\nModality: %s\nAccessionNumber: %s\nErrorMessage: %s\n\n" "$PatientID" "$NumberOfStudyRelatedInstances" "$StudyDate" "$Modality" "$AccessionNumber" "$ErrorMsg"
}


function askToResumeFromLastDt () {
  if [ -f currentdate.state ]; then
    read -t 10 -p "Resume from last successful date? (Automatically sets no after 10 seconds) Y/n: " ans
    [[ $? -gt 128 ]] && ans="n"
    if [ "$ans" = "Y" -o "$ans" = "y" ]; then 
      . currentdate.state
    else
      rm -f currentdate.state
    fi
  fi
  
  [ -z "$currentdate" ] && currentdate=$startdate
}

askToResumeFromLastDt

while [[ ${currentdate} -ge ${stopdate} ]]; do
    echo "currentdate=$currentdate" > currentdate.state
    querydate="${currentdate}-${currentdate}"
    exe_findNlog $querydate
    [ $? -ne 0 ] && break
    nextdate=$(date --date="$currentdate 1 day ago" +%Y%m%d)
    currentdate=$nextdate
    sleep 3
done
echo "$(hostname) migration stopped at $(date)" > stopped.txt
tail -n 10 brfind.log >> stopped.txt
