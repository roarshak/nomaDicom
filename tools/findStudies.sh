#!/bin/bash
# shellcheck disable=SC2155
# filepath: /home/medsrv/KISS/viper/findscu/combined_findscu.sh
#
# DATE: 2025-07-08
# AUTHOR: Combined by GitHub Copilot
# PURPOSE: Generate input study list via DICOM with argument parsing, validation, logging, and support for both date-range and list-based iteration modes.

# Local (this server) DICOM values
# shellcheck disable=SC1091
. "$DICOM_VAR"/pb-scp.cfg

# --- Defaults ---
  interstitial_sleep=3   # Default sleep in seconds between findscu executions
  verbose=0              # Verbose/progress output (0=off, 1=on)
  verbosity=0              # 0=quiet, 1=info, 2=debug (show command)
  calling_AE_TITLE=""
  QRIP="172.25.3.12"
  QRPORT=104
  QRAE_TITLE="SCHCSCP"
  QRROOT="S"
  startdate=$(date --date='yesterday' +%Y%m%d)
  stopdate=$(date --date="$startdate -10 years" +%Y%m%d)
  suid=""
  accnum=""
  instname=""
  patid=""
  patname=""
  modality=""
  iteration_mode="date-range"   # "date-range" or "list"
  order="reverse"               # "reverse" (backward) or "forward"
  list_filename=""
  output_file="output.csv"
  AE_TITLE="$QRAE_TITLE"
  use_ssl="no"
  # SSL_SITE_KEY/SSL_SITE_CERT is set by the medsrv env
  # SSL_SITE_KEY="/home/medsrv/var/openssl/privkey.pem"
  # SSL_SITE_CERT="/home/medsrv/var/openssl/certs/default.pem"
  # _TLS_OPT="+tls ${SSL_SITE_KEY:?} ${SSL_SITE_CERT:?} -ic"
  # movescu_opts=("+tls" "${SSL_SITE_KEY:?}" "${SSL_SITE_CERT:?}" "-ic" "-S")
  ssl_key=""
  ssl_cert=""

# --- Help message ---
function print_help {
  echo "Usage: $0 [OPTIONS]"
  echo "Options:"
  echo "  --calling_aetitle <AE Title>      Set the calling AE Title (default: system default)"
  echo "  --sleep <seconds>                 Set sleep (in seconds) between each findscu execution (default: 3)"
  echo "  --verbose[=LEVEL]                 Enable verbose/progress output (LEVEL: 1=info, 2=debug/command)"
  echo "  --QRIP <IP Address>               Set the IP address of the DICOM server (default: $QRIP)"
  echo "  --QRPORT <Port>                   Set the port of the DICOM server (default: $QRPORT)"
  echo "  --QRAE_TITLE <AE Title>           Set the AE Title of the DICOM server (default: $QRAE_TITLE)"
  echo "  --QRROOT <Root>                   Set the QR Root (default: $QRROOT)"
  echo "  --startdate <YYYYMMDD>            Set the start date for querying (default: yesterday)"
  echo "  --stopdate <YYYYMMDD>             Set the end date for querying (default: startdate - 10 years)"
  echo "  --suid <StudyInstanceUID>         Specify a StudyInstanceUID to filter by (default: include all)"
  echo "  --accnum <Accession Number>       Specify an Accession Number to filter by (default: include all)"
  echo "  --instname <Institution Name>     Specify an Institution Name to filter by (default: include all)"
  echo "  --patid <Patient ID>              Specify a Patient ID to filter by (default: include all)"
  echo "  --patname <Patient Name>          Specify a Patient Name to filter by (default: include all)"
  echo "  --modality <Modality>             Specify a Modality to filter by (default: include all)"
  echo "  --iteration_mode <date-range|list>  Choose iteration mode (default: date-range)"
  echo "  --order <reverse|forward>         Set date iteration order (default: reverse)"
  echo "  --listfile <filename>             Specify file for list-based iteration"
  echo "  --output <filename>               Specify output CSV file (default: output.csv)"
  echo "  --ssl                             Enable SSL/TLS for findscu"
  echo "  --ssl-key <keyfile>               Path to SSL private key"
  echo "  --ssl-cert <certfile>             Path to SSL certificate"
  echo "  -h, --help                        Display this help and exit"
}

# --- Input validation functions ---
validate_port() {
  if ! [[ $1 =~ ^[0-9]+$ ]]; then
    echo "ERROR: QRPORT must be a numeric value."
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
  if [[ $order == "reverse" && $startdate -lt $stopdate ]]; then
    echo "ERROR: startdate must be later than stopdate for backward processing."
    exit 1
  elif [[ $order == "forward" && $startdate -gt $stopdate ]]; then
    echo "ERROR: stopdate must be later than startdate for forward processing."
    exit 1
  fi
}

# --- Parse command-line arguments (while loop, long options) ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --verbose)
      if [[ "$2" =~ ^[0-9]+$ ]]; then
        verbosity="$2"
        shift 2
      else
        verbosity=1
        shift
      fi
      ;;
    -v)
      verbosity=1
      shift
      ;;
    --calling_aetitle)
      calling_AE_TITLE="$2"
      shift 2
      ;;
    --sleep)
      interstitial_sleep="$2"
      shift 2
      ;;
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
      AE_TITLE="$2"
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
    --suid)
      suid="$2"
      shift 2
      ;;
    --accnum)
      accnum="$2"
      shift 2
      ;;
    --instname)
      instname="$2"
      shift 2
      ;;
    --patid)
      patid="$2"
      shift 2
      ;;
    --patname)
      patname="$2"
      shift 2
      ;;
    --modality)
      modality="$2"
      shift 2
      ;;
    --iteration_mode)
      iteration_mode="$2"
      shift 2
      ;;
    --order)
      order="$2"
      shift 2
      ;;
    --listfile)
      list_filename="$2"
      shift 2
      ;;
    --output)
      output_file="$2"
      shift 2
      ;;
    --ssl)
      use_ssl="yes"
      shift
      ;;
    --ssl-key)
      ssl_key="$2"
      shift 2
      ;;
    --ssl-cert)
      ssl_cert="$2"
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

# --- Validate required parameters ---
validate_port "$QRPORT"
validate_date "$startdate"
validate_date "$stopdate"
validate_dates_order

# --- Build findscu options arrays dynamically based on user input ---
findscu_baseopts=(
    "-v"                                     # Verbose output
    "-$QRROOT"                                # QR Root
    ${calling_AE_TITLE:+--aetitle "$calling_AE_TITLE"}  # AE Title of the calling DICOM application
    "--key 0008,0052=STUDY"                   # Query/Retrieve Level (STUDY)
)

findscu_columns=()
[[ -n "$suid" ]]     && findscu_columns+=("--key 0020,000D=\"$suid\"") || findscu_columns+=("--key 0020,000D")
[[ -n "$accnum" ]]   && findscu_columns+=("--key 0008,0050=\"$accnum\"") || findscu_columns+=("--key 0008,0050")
[[ -n "$instname" ]] && findscu_columns+=("--key 0008,0080=\"$instname\"") || findscu_columns+=("--key 0008,0080")
[[ -n "$patid" ]]    && findscu_columns+=("--key 0010,0020=\"$patid\"") || findscu_columns+=("--key 0010,0020")
[[ -n "$patname" ]]  && findscu_columns+=("--key 0010,0010=\"$patname\"") || findscu_columns+=("--key 0010,0010")
[[ -n "$modality" ]] && findscu_columns+=("--key 0008,0060=\"$modality\"") || findscu_columns+=("--key 0008,0060")
findscu_columns+=("--key 0020,1208")  # Number of Study Related Instances

# --- Function to log and execute the findscu command ---
function exe_findNlog () {
  local query_opts=("${findscu_baseopts[@]}")
  local date_filter="$1"
  local suid_filter="$2"
  local extra_opts=("${findscu_columns[@]}")
  local cmd_opts=("${query_opts[@]}")

  # Add date filter if provided
  [[ -n "$date_filter" ]] && cmd_opts+=("--key 0008,0020=\"$date_filter\"")
  # Add SUID filter if provided (for list mode)
  [[ -n "$suid_filter" ]] && cmd_opts+=("--key 0020,000D=\"$suid_filter\"")
  # Add all other columns
  cmd_opts+=("${extra_opts[@]}")
  # Add call, IP, and port
  cmd_opts+=("--call $QRAE_TITLE $QRIP $QRPORT")

  # Add SSL/TLS options if enabled
  local ssl_opts=""
  if [[ "$use_ssl" == "yes" ]]; then
    ssl_opts="+tls"
    [[ -n "$ssl_key" ]] && ssl_opts="$ssl_opts \"$ssl_key\""
    [[ -n "$ssl_cert" ]] && ssl_opts="$ssl_opts \"$ssl_cert\""
    ssl_opts="$ssl_opts -ic +ps"
  fi

  # Assemble the findscu command
  findscu_command="/home/medsrv/component/dicom/bin/findscu $QRDEBUG $ssl_opts ${cmd_opts[*]}"

  # Count lines in output file before (excluding header)
  local before_count=0
  if [[ -f "$output_file" ]]; then
    before_count=$(($(wc -l < "$output_file") - 1))
    (( before_count < 0 )) && before_count=0
  fi

  # Verbose progress output (print date, but don't newline yet)
  if (( verbosity > 0 )); then
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    if [[ -n "$date_filter" ]]; then
      short_date="${date_filter%%-*}"
      printf "%s [INFO] Querying date: %s " "$timestamp" "$short_date"
    elif [[ -n "$suid_filter" ]]; then
      printf "%s [INFO] Querying SUID: %s " "$timestamp" "$suid_filter"
    else
      printf "%s [INFO] Querying " "$timestamp"
    fi
  fi

  # Execute the command and capture the response
  findscu_response=$(eval $findscu_command 2>&1)
  findscu_return_code=$?

  # Log the command and response
  echo "$findscu_command" >> findscu_commands.log
  echo "$findscu_response" >> brfind.log

  # Log errors if any
  if [ $findscu_return_code -ne 0 ]; then
      echo "$(date) Error querying archive" | tee -a brfinderr.log
      echo "$findscu_response" | tee -a brfinderr.log
      if (( verbose )); then
        echo "Records found: 0"
      fi
      return 1
  fi

  # Extract and log DICOM tag values
  Extract_DCM_Tag_Values_From_FindSCU_Response "$findscu_response" "$findscu_command" "$date_filter" "$suid_filter"

  # Count lines in output file after (excluding header)
  local after_count=0
  if [[ -f "$output_file" ]]; then
    after_count=$(($(wc -l < "$output_file") - 1))
    (( after_count < 0 )) && after_count=0
  fi

  # Calculate number of new records
  local new_records=$(( after_count - before_count ))
  if (( verbosity > 0 )); then
    printf "Records found: %s" "$new_records"
    if (( verbosity > 1 )); then
      printf " CMD: %s" "$findscu_command"
    fi
    printf "\n"
  fi
}

# --- Function to extract DICOM tag values from findscu response ---
Extract_DCM_Tag_Values_From_FindSCU_Response() {
  local findscu_response="$1"
  local findscu_command="$2"
  local date_filter="$3"
  local suid_filter="$4"

  printf "Command: %s\n" "$findscu_command" >> brfind.log
  printf "Filters: suid=%s accnum=%s instname=%s patid=%s studydate=%s patname=%s modality=%s\n" "$suid" "$accnum" "$instname" "$patid" "$date_filter" "$patname" "$modality" >> brfind.log

  printf "%s" "$findscu_response" | awk '
    BEGIN {
      in_study = 0
      StudyInstanceUID = AccessionNumber = InstitutionName = PatientID = PatientName = StudyDate = Modality = NumberOfStudyRelatedInstances = ErrorMsg = ""
    }
    /^RESPONSE:/ {
      if (in_study) {
        # Output previous study before starting new one
        print StudyInstanceUID "," AccessionNumber "," InstitutionName "," PatientID "," PatientName "," StudyDate "," Modality "," NumberOfStudyRelatedInstances "," ErrorMsg
      }
      # Reset for new study
      in_study = 1
      StudyInstanceUID = AccessionNumber = InstitutionName = PatientID = PatientName = StudyDate = Modality = NumberOfStudyRelatedInstances = ErrorMsg = ""
      next
    }
    in_study {
      if ($0 ~ /\(0020,000d\)/) {
        match($0, /\[([^\]]*)\]/, arr); StudyInstanceUID = arr[1]
      }
      if ($0 ~ /\(0008,0050\)/) {
        match($0, /\[([^\]]*)\]/, arr); AccessionNumber = arr[1]
      }
      if ($0 ~ /\(0008,0080\)/) {
        match($0, /\[([^\]]*)\]/, arr); InstitutionName = arr[1]
      }
      if ($0 ~ /\(0010,0020\)/) {
        match($0, /\[([^\]]*)\]/, arr); PatientID = arr[1]
      }
      if ($0 ~ /\(0010,0010\)/) {
        match($0, /\[([^\]]*)\]/, arr); PatientName = arr[1]
      }
      if ($0 ~ /\(0008,0020\)/) {
        match($0, /\[([^\]]*)\]/, arr); StudyDate = arr[1]
      }
      if ($0 ~ /\(0008,0060\)/) {
        match($0, /\[([^\]]*)\]/, arr); Modality = arr[1]
      }
      if ($0 ~ /\(0020,1208\)/) {
        match($0, /\[([^\]]*)\]/, arr); NumberOfStudyRelatedInstances = arr[1]
      }
      if ($0 ~ /\(0000,0902\)/) {
        match($0, /\[([^\]]*)\]/, arr); ErrorMsg = arr[1]
      }
    }
    END {
      if (in_study) {
        print StudyInstanceUID "," AccessionNumber "," InstitutionName "," PatientID "," PatientName "," StudyDate "," Modality "," NumberOfStudyRelatedInstances "," ErrorMsg
      }
    }
  ' >> "$output_file"
}

# --- Resume logic ---
function askToResumeFromLastDt () {
  if [ -f currentdate.state ]; then
    read -r -t 10 -p "Resume from last successful date? (Automatically sets no after 10 seconds) Y/n: " ans
    [[ $? -gt 128 ]] && ans="n"
    if [ "$ans" = "Y" ] || [ "$ans" = "y" ]; then 
      . currentdate.state
    else
      rm -f currentdate.state
    fi
  fi
  [ -z "$currentdate" ] && currentdate=$startdate
}

# --- Iteration modes ---
date_range_iteration() {
  askToResumeFromLastDt
  if [[ "$order" == "reverse" ]]; then
    while [[ ${currentdate} -ge ${stopdate} ]]; do
      echo "currentdate=$currentdate" > currentdate.state
      if ! exe_findNlog "${currentdate}-${currentdate}" ""; then
        break
      fi
      nextdate=$(date --date="$currentdate 1 day ago" +%Y%m%d)
      currentdate=$nextdate
      sleep "$interstitial_sleep"
    done
  else
    while [[ ${currentdate} -le ${stopdate} ]]; do
      echo "currentdate=$currentdate" > currentdate.state
      if ! exe_findNlog "${currentdate}-${currentdate}" ""; then
        break
      fi
      nextdate=$(date --date="$currentdate 1 day" +%Y%m%d)
      currentdate=$nextdate
      sleep "$interstitial_sleep"
    done
  fi
  echo "$(hostname) migration stopped at $(date)" > stopped.txt
  tail -n 10 brfind.log >> stopped.txt
}

list_based_iteration() {
  if [ ! -f "$list_filename" ]; then
    echo "ERROR: List file not found: $list_filename"
    exit 1
  fi
  local lineno=0
  while read -r line; do
    ((lineno++))
    if (( verbose )); then
      echo "[INFO] Querying list item #$lineno: $line"
    fi
    if ! exe_findNlog "" "$line"; then
      break
    fi
    sleep "$interstitial_sleep"
  done < "$list_filename"
}

# --- Main ---
# Write CSV header
echo "StudyInstanceUID,AccessionNumber,InstitutionName,PatientID,PatientName,StudyDate,Modality,NumberOfStudyRelatedInstances,ErrorMsg" > "$output_file"

case "$iteration_mode" in
  date-range)
    date_range_iteration
    ;;
  list)
    list_based_iteration
    ;;
  *)
    echo "ERROR: Invalid iteration mode: $iteration_mode"
    print_help
    exit 1
    ;;
esac

echo "Script execution complete."