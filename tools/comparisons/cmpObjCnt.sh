#!/bin/bash

# Define Functions
  DisplayUsage() {
    echo "Usage: $(basename "$0") [--help|-h] [--script] [--study <Study Instance UID>] [--target-aet <AETitle>] [--target-ip <ip address>] [--target-port <port>]"
    echo "  --help|-h   Display this help message"
    echo "  --script    Scripted mode, to be called from another script"
    echo "  --study <Study Instance UID>    Study Instance UID to check"
    echo "  --target-aet <AETitle>    AETitle of the target server"
    echo "  --target-ip <ip address>    IP address of the target server"
    echo "  --target-port <port>    Port of the target server"
    exit 1
  }
  check_and_source_config() {
    while [ -n "$1" ]; do
      if [[ -f "$1" ]]; then
        . "$1"
      else
        echo "ERROR: Could not find $1. Exiting."
        exit 1
      fi
      shift
    done
  }
  CFind_StudyInfo_For_SUID() {
    # Reference
      # DCM TAG     VR  Tag Name
      # (0008,0052)	CS	Query/Retrieve Level
      # (0020,000D)	UI	Study Instance UID
      # (0020,1208)	IS	Number of Study Related Instances
      # (0008,0020)	DA	Study Date
      # (0008,0061)	CS	Modalities in Study
      # (0008,0050)	SH	Accession Number
      # (0010,0020)	LO	Patient ID
      # (0008,0056)	CS	Instance Availability

      # if ! /home/medsrv/component/dicom/bin/findscu -S --aetitle "$_LOCAL_AE_TITLE" --key 0008,0052=STUDY --key 0020,000D="$1" --key 0020,1208 --key 0008,0020 --key 0008,0061 --key 0008,0050 --key 0010,0020 --call $2 $3 $4; then
      # 	# return 1
      # 	exit 1
      # fi
    #

    # TLS_OPT="+tls $SSL_SITE_KEY $SSL_SITE_CERT -ic"
    # $TLS_OPT \
    if ! /home/medsrv/component/dicom/bin/findscu -S \
      --aetitle "$AE_TITLE" \
      --key 0008,0052=STUDY \
      --key 0020,000D="$1" \
      --key 0020,1208 \
      --call $2 $3 $4; then
        return 0
    fi
  }
  Extract_DCM_Tag_Values_From_FindSCU_Response() {
    findscu_response="$1"
    NumberOfStudyRelatedInstances="$(printf "%s" "$findscu_response" | grep "(0020,1208)\|NumberOfStudyRelatedInstances" | cut -c 16- | tr '(' '[' | tr ')' ']' | awk -F '[][]' '{print $2}')"
    echo "$NumberOfStudyRelatedInstances"
  }
  Compare_Study_ObjCnt() {
    _numofobj_on_target="$1"
    # Study records should exist for both source & target at this point.
    _numofobj_on_source="$(sql.sh "SELECT numofobj FROM ${migration_database}.LocalExams WHERE styiuid='$SUID'" -N)"
    # printf "%s says there are %s objects on the source.\n" "${FUNCNAME[0]}" "$_numofobj_on_source"
    # printf "%s says there are %s objects on the target.\n" "${FUNCNAME[0]}" "$_numofobj_on_target"

    if [ "${_numofobj_on_target:=0}" -eq 0 ]; then
      return 0
    elif [ "${_numofobj_on_target:=0}" -lt "${_numofobj_on_source:=0}" ]; then # Study is desynchronized
      return 0
    else # Study is synchronized
      return 1
    fi
  }

executedByUser=True
[ $# -eq 0 ] && DisplayUsage
while [ -n "$1" ]; do
	case $1 in
    --help)   DisplayUsage ;;
    -h)       DisplayUsage ;;
    --script) executedByUser=False ;;
    --study)  SUID="$2"; shift ;;
    -S)       SUID="$2"; shift ;;
    -s)       SUID="$2"; shift ;;
    --target-aet)       Target_AET="$2"; shift ;;
    --target-ip)       Target_IP="$2"; shift ;;
    --target-port)       Target_Port="$2"; shift ;;
    *)        printf "Unknown option (ignored): %s" "$1"; DisplayUsage ;;
  esac
  shift
done

check_and_source_config "universal.lib" "universal.cfg" /home/medsrv/var/dicom/pb-scp.cfg
Check_Required_Variables Target_AET Target_IP Target_Port SUID AE_TITLE
Compare_Study_ObjCnt "$(Extract_DCM_Tag_Values_From_FindSCU_Response "$(CFind_StudyInfo_For_SUID "$SUID" "$Target_AET" "$Target_IP" "$Target_Port")")"

