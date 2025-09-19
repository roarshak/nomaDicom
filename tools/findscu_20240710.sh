#!/bin/bash

# Input validation functions
validate_port() {
  if ! [[ $1 =~ ^[0-9]+$ ]]; then
    echo "ERROR: Port must be a numeric value."
    exit 1
  fi
}

validate_date() {
  if ! [[ $1 =~ ^[0-9]{8}$ ]]; then
    echo "ERROR: Date must be in YYYYMMDD format."
    exit 1
  fi
}

validate_dates_order() {
  if [[ $1 -lt $2 && $3 == "reverse" ]]; then
    echo "ERROR: startdate must be later than stopdate for backward processing."
    exit 1
  elif [[ $1 -gt $2 && $3 == "forward" ]]; then
    echo "ERROR: stopdate must be later than startdate for forward processing."
    exit 1
  fi
}

# Function to parse findscu response
parse_response() {
  local findscu_response="$1"
  PatientID=$(printf "%s" "$findscu_response" | grep "(0010,0020)\|PatientID" | cut -d ' ' -f 3 | tr -d '[]')
  NumberOfStudyRelatedInstances=$(printf "%s" "$findscu_response" | grep "(0020,1208)\|NumberOfStudyRelatedInstances" | cut -d ' ' -f 3 | tr -d '[]')
  StudyDate=$(printf "%s" "$findscu_response" | grep "(0008,0020)\|StudyDate" | cut -d ' ' -f 3 | tr -d '[]')
  Modality=$(printf "%s" "$findscu_response" | grep "(0008,0061)\|Modality" | cut -d ' ' -f 3 | tr -d '[]')
  AccessionNumber=$(printf "%s" "$findscu_response" | grep "(0008,0050)\|AccessionNumber" | cut -d ' ' -f 3 | tr -d '[]')
  ErrorMsg=$(printf "%s" "$findscu_response" | grep "(0000,0902)\|ErrorComment")
}

# Function to resume from last successful date
askToResumeFromLastDt() {
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

# Function to parse script options/arguments
parse_options() {
  while getopts "a:d:q:i:p:m:s:e:o:f:" opt; do
    case $opt in
      a) ARBITRARY_AET="$OPTARG" ;;
      d) DATE="$OPTARG" ;;
      q) QUERY_AET="$OPTARG" ;;
      i) QUERY_IP="$OPTARG" ;;
      p) QUERY_PORT="$OPTARG" ;;
      m) ITERATION_MODE="$OPTARG" ;;
      s) STARTDATE="$OPTARG" ;;
      e) STOPDATE="$OPTARG" ;;
      o) ORDER="$OPTARG" ;;
      f) LIST_FILENAME="$OPTARG" ;;
      *) echo "Invalid option: -$OPTARG" ;;
    esac
  done
}

# Function for date-range iteration mode
date_range_iteration() {
  validate_date "$STARTDATE"
  validate_date "$STOPDATE"
  validate_dates_order "$STARTDATE" "$STOPDATE" "$ORDER"
  
  askToResumeFromLastDt
  
  # Date range iteration logic here
  currentdate="$STARTDATE"
  while [[ $currentdate -le $STOPDATE ]]; do
    findscu_response=$(/home/medsrv/component/dicom/bin/findscu -S "${findscu_baseopts[@]}" "${findscu_columns[@]}" --key 0008,0020="$currentdate")
    parse_response "$findscu_response"
    echo "$StudyInstanceUID,$AccessionNumber" >> "$output_file"
    # Update currentdate based on ORDER
    if [[ "$ORDER" == "forward" ]]; then
      currentdate=$(date -d "$currentdate + 1 day" +%Y%m%d)
    else
      currentdate=$(date -d "$currentdate - 1 day" +%Y%m%d)
    fi
  done
}

# Function for list-based iteration mode
list_based_iteration() {
  if [ ! -f "$LIST_FILENAME" ]; then
    echo "ERROR: List file not found."
    exit 1
  fi
  
  while read -r line; do
    findscu_response=$(/home/medsrv/component/dicom/bin/findscu -S "${findscu_baseopts[@]}" "${findscu_columns[@]}" --key 0020,000D="$line")
    parse_response "$findscu_response"
    echo "$StudyInstanceUID,$AccessionNumber" >> "$output_file"
  done < "$LIST_FILENAME"
}

# Main script
ARBITRARY_AET=""
DATE=""
QUERY_AET=""
QUERY_IP=""
QUERY_PORT=""
ITERATION_MODE=""
STARTDATE=""
STOPDATE=""
ORDER=""
LIST_FILENAME=""
output_file="output.csv"

# Parse options
parse_options "$@"

# Validate inputs
validate_port "$QUERY_PORT"
validate_date "$DATE"

findscu_baseopts=(
    "--aetitle $ARBITRARY_AET"
    "--call $QUERY_AET"
    "$QUERY_IP"
    "$QUERY_PORT"
)

findscu_columns=(
    "--key 0008,0050"  # Accession Number
    "--key 0020,000D"  # StudyInstanceUID
)

# Run the appropriate iteration mode
case $ITERATION_MODE in
  date-range)
    date_range_iteration
    ;;
  list)
    list_based_iteration
    ;;
  *)
    echo "ERROR: Invalid iteration mode."
    exit 1
    ;;
esac

echo "Script execution complete."
