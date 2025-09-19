#! /bin/bash
#shellcheck disable=SC2207,SC1091
# Do not source universal.lib. This script is intended to be self-contained.
# TODO:
#   - Verify required variables

. $HOME/etc/setenv.sh
_SCRIPT_NAME="$(basename "$0")"
_SCRIPT_CFG="${_SCRIPT_NAME%.*}.cfg"
_SCRIPT_LOG="${_SCRIPT_NAME%.*}.log"
_DATE_FMT="%Y%m%d-%H%M%S"
_MYSQL_BIN="/home/medsrv/component/mysql/bin/mysql"
_SECURITY_OPT="TCP" # Or TLS
_TLS_OPT="+tls $SSL_SITE_KEY $SSL_SITE_CERT -ic"
_DRY_RUN="n"
_VERBOSE_OPTS=""
_DEBUG_OPTS=""

# Common movescu options setup
common_storescu_opts=(
  -R
  --aetitle "$AE_TITLE"
  --call "$TARGET_AET" "$QRIP" "$QRPORT"
)

DisplayUsage() {
  pass
}
Check_Required_Variables() {
  for var in "$@"; do
    if [ -z "${!var}" ]; then
      echo "Error: $var is not set."
      exit 1
    fi
  done
}

# Function to send a DICOM object using storescu
Send_DICOM_Object() {
  # Add security options if needed
  if [ "$_SECURITY_OPT" = "TLS" ]; then
    Check_Required_Variables SSL_SITE_KEY SSL_SITE_CERT _TLS_OPT
    movescu_opts=("${common_movescu_opts[@]}" "$_TLS_OPT")
  else
    movescu_opts=("${common_movescu_opts[@]}")
  fi

  # Format the date and indicate if it's a dry run
  _date=$(date "+%Y%m%d-%H%M%S")
  [[ "${_DRY_RUN}" == "y" ]] && _date="${_date} DRY_RUN"

  if [ "$executedByUser" = "True" ] && [ "$TargetVerified" = "True" ]; then
    /home/medsrv/component/dicom/bin/storescu "${movescu_opts[@]}" "$_VERBOSE_OPTS" "$_DEBUG_OPTS" > "$_SCRIPT_LOG" 2>&1
  elif [ "$executedByUser" = "True" ] && [ "$TargetVerified" = "False" ]; then
    printf "%s %s is not a valid AE Title.\n" "$_date" "$TARGET_AET"
  elif [ "$executedByUser" = "False" ] && [ "$TargetVerified" = "True" ]; then
    /home/medsrv/component/dicom/bin/storescu "${movescu_opts[@]}" "$_VERBOSE_OPTS" "$_DEBUG_OPTS" > "$_SCRIPT_LOG" 2>&1
  elif [ "$executedByUser" = "False" ] && [ "$TargetVerified" = "False" ]; then
    printf "%s Target device %s is not verified. Skipping migration.\n" "$_date" "$TARGET_DEVICE_NAME" >> "$_SCRIPT_LOG"
    return 1
  fi

  # Mock commands to fetch DICOM details. Replace with actual `sql.sh` or database query commands.
  SUID="Mock_Styiuid_for_$DCM_Filename"
  SERIUID="Mock_Seriuid_for_$DCM_Filename"
  SOPIUID="Mock_Sopiuid_for_$DCM_Filename"

  if [ "$_SECURITY_OPT" = "TCP" ]; then
      Command="storescu -v -aec $AE_TITLE -aet $AE_TITLE $QRIP $QRPORT $DCM_Filename"
      echo "$_date Running: $Command" | tee -a "$_SCRIPT_LOG"
      if [[ "${_DRY_RUN}" == "n" ]]; then
          eval "$Command"
      fi
  elif [ "$_SECURITY_OPT" = "TLS" ]; then
      Command="storescu -v --tls $SSL_SITE_CERT $SSL_SITE_KEY none -aec $AE_TITLE -aet $AE_TITLE $QRIP $QRPORT $DCM_Filename"
      echo "$_date Running: $Command" | tee -a "$_SCRIPT_LOG"
      if [[ "${_DRY_RUN}" == "n" ]]; then
          eval "$Command"
      fi
  fi
}

# Main script execution
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <DICOM_Filename>"
    exit 1
fi

executedByUser=True
[ $# -eq 0 ] && DisplayUsage
while [ -n "$1" ]; do
	case $1 in
    --help|-h)   DisplayUsage ;;
    --script) executedByUser=False ;;
    --target-ae) TARGET_AET="$2"; shift ;;
    --target-ip) TARGET_IP="$2"; shift ;;
    --target-ip) TARGET_PORT="$2"; shift ;;
    --source-ae) AE_TITLE="$2"; shift ;;
    --file)  _file="$2"; shift ;;
    --study|-S|-s)  SUID="$2"; shift ;;
    *)        printf "Unknown option (ignored): %s" "$1"; DisplayUsage ;;
  esac
  shift
done


DCM_Filename="$1"
Send_DICOM_Object "$DCM_Filename"
