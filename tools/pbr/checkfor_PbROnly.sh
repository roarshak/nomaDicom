#!/bin/bash
#shellcheck disable=SC2207,SC1091
if [ -z "$universalSource" ]; then
	MY_HOME="$(dirname "$0")"
	. "$MY_HOME/universal.lib"
fi

DisplayUsage() {
  printf "Usage: %s [OPTION]... [SUID]...\n" "$(getScriptName)"
  printf "Check if a study is PbR-Only.\n"
  printf "\n"
  printf "  -h, --help\t\tDisplay this help and exit\n"
  printf "  -S, -s, --study\tSpecify the SUID of the study to check\n"
  printf "  --script\t\tDo not log results to a file\n"
  exit 0
}
DetermineIfTrueOrNot() {
  Study_Directory="$(./getStudyLocation.sh --script -s "$SUID")"
  Study_PbR_List=($(find "${Study_Directory}" -mindepth 1 -maxdepth 1 -type f -name "*PbR*"))
  Study_NonPbR_List=($(find "${Study_Directory}" -mindepth 1 -maxdepth 1 -type f -not -name "*PbR*"))
  if [ ${#Study_NonPbR_List[@]} -eq 0 ] && [ ${#Study_PbR_List[@]} -gt 0 ]; then
    PbR_Only=True
  elif [ ${#Study_NonPbR_List[@]} -gt 0 ]; then
    PbR_Only=False
  fi
}
DeliverResults() {
  if [ "$executedByUser" = "True" ] && [ "$PbR_Only" = "True" ]; then
    printf "%s %s %s\n" "$(date "+%Y%m%d-%H%M%S")" "$SUID" "PbR-Only: True"
  elif [ "$executedByUser" = "True" ] && [ "$PbR_Only" = "False" ]; then
    printf "%s %s %s\n" "$(date "+%Y%m%d-%H%M%S")" "$SUID" "PbR-Only: False"
  elif [ "$executedByUser" = "False" ] && [ "$PbR_Only" = "True" ]; then
    printf "%s\n" "$SUID" >> "$(getLogName)"
  elif [ "$executedByUser" = "False" ] && [ "$PbR_Only" = "False" ]; then
    printf "%s\n" "$SUID" >> /dev/null
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
    *)        printf "Unknown option (ignored): %s" "$1"; DisplayUsage ;;
  esac
  shift
done

DetermineIfTrueOrNot
DeliverResults
