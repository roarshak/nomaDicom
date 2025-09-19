#!/bin/bash

DisplayUsage() {
  printf "Usage: %s [OPTION]... [SUID]...\n" "$(basename "$0")"
  printf "Check if a study is PbR-Only.\n"
  printf "\n"
  printf "  -h, --help\t\tDisplay this help and exit\n"
  printf "  -S, -s, --study\tSpecify the SUID of the study to check\n"
  printf "  --remote-host\t\tSpecify the remote host to check\n"
  exit 0
}

# LOCAL STY INFO
getLocalInfo() {
  Dcstudy_D_Local="$(sql.sh "SELECT Dcstudy_D FROM Dcstudy WHERE STYIUID='$suid'" -N 2>/dev/null)"
  StudyDir_Local="$(/home/medsrv/component/repositoryhandler/scripts/locateStudy.sh -d "$suid" 2>/dev/null)"
  Storestate_ProcessMode_Local="$(grep -i ProcessMode "$StudyDir_Local"/.info/storestate.rec | cut -d'=' -f2)"
  NumofObj_DB_Local="$(sql.sh "SELECT NUMOFOBJ FROM Dcstudy WHERE STYIUID='$suid'" -N)"
  NumofImg_DB_Local="$(sql.sh "SELECT NUMOFIMG FROM Dcstudy WHERE STYIUID='$suid'" -N)"
  NumofObj_FS_Local="$(ls "$StudyDir_Local" 2>/dev/null | wc -l)"
  if [ "$verbose" = "v" ]; then
    NumofFilesIN_VarLock_Local="$(find /home/medsrv/var/lock -name "*$suid*" 2>/dev/null | wc -l)"
    NumofFilesIN_TMP_Local1="$(find /home/medsrv/tmp/ -name "*$suid*" 2>/dev/null | wc -l)"
    NumofFilesIN_TMP_Local2="$(find /home/medsrv/tmp/ -type f | xargs grep -il "$suid" 2>/dev/null | wc -l)"
    NumofTasks_cpuQ_Local="$(find /home/medsrv/var/cpuqueue/ -type f 2>/dev/null | xargs grep -il "$suid" 2>/dev/null | wc -l)"
    NumofTasks_netQ_Local="$(find /home/medsrv/var/netqueue/ -type f 2>/dev/null | xargs grep -il "$suid" 2>/dev/null | wc -l)"
    NumofTasks_TaskQ_Sched_Local="$(find /home/medsrv/var/taskqueue/.scheduled -type f 2>/dev/null | xargs grep -il "$suid" 2>/dev/null | wc -l)"
    NumofTasks_TaskQ_Retry_Local="$(find /home/medsrv/var/taskqueue/.retry -type f 2>/dev/null | xargs grep -il "$suid" 2>/dev/null | wc -l)"
    NumofTasks_TaskQ_Failed_Local="$(find /home/medsrv/var/taskqueue/.failed -type f 2>/dev/null | xargs grep -il "$suid" 2>/dev/null | wc -l)"
    NumofTasks_DB_Q_Local="$(sql.sh "SELECT COUNT(*) FROM TaskQueue WHERE STYIUID='$suid'" -N 2>/dev/null)"
  fi
}

# REMOTE STY INFO
getRemoteInfo() {
  if [ -n "$remote_ep" ]; then
    Dcstudy_D_Remote="$(ssh -n "$remote_ep" "sql.sh \"SELECT Dcstudy_D FROM Dcstudy WHERE STYIUID='$suid'\" -N" 2>/dev/null)"
    StudyDir_Remote="$(ssh -n "$remote_ep" "/home/medsrv/component/repositoryhandler/scripts/locateStudy.sh -d $suid" 2>/dev/null)"
    Storestate_ProcessMode_Remote="$(ssh -n "$remote_ep" "grep -i ProcessMode \"$StudyDir_Remote/.info/storestate.rec\" 2>/dev/null" | cut -d'=' -f2)"
    NumofObj_DB_Remote="$(ssh -n "$remote_ep" "sql.sh \"SELECT NUMOFOBJ FROM Dcstudy WHERE STYIUID='$suid'\" -N" 2>/dev/null)"
    NumofImg_DB_Remote="$(ssh -n "$remote_ep" "sql.sh \"SELECT NUMOFIMG FROM Dcstudy WHERE STYIUID='$suid'\" -N" 2>/dev/null)"
    NumofObj_FS_Remote="$(ssh -n "$remote_ep" "ls \"$StudyDir_Remote\" 2>/dev/null" | wc -l)"
    if [ "$verbose" = "v" ]; then
      NumofFilesIN_VarLock_Remote="$(ssh -n "$remote_ep" "find /home/medsrv/var/lock -name \"*$suid*\" 2>/dev/null" | wc -l)"
      NumofFilesIN_TMP_Remote1="$(ssh -n "$remote_ep" "find /home/medsrv/tmp/ -name \"*$suid*\" 2>/dev/null" | wc -l)"
      NumofFilesIN_TMP_Remote2="$(ssh -n "$remote_ep" "find /home/medsrv/tmp/ -type f | xargs grep -il \"$suid\" 2>/dev/null" | wc -l)"
      NumofTasks_cpuQ_Remote="$(ssh -n "$remote_ep" "find /home/medsrv/var/cpuqueue/ -type f 2>/dev/null | xargs grep -il \"$suid\" 2>/dev/null" | wc -l)"
      NumofTasks_netQ_Remote="$(ssh -n "$remote_ep" "find /home/medsrv/var/netqueue/ -type f 2>/dev/null | xargs grep -il \"$suid\" 2>/dev/null" | wc -l)"
      NumofTasks_TaskQ_Sched_Remote="$(ssh -n "$remote_ep" "find /home/medsrv/var/taskqueue/.scheduled -type f 2>/dev/null | xargs grep -il \"$suid\" 2>/dev/null" | wc -l)"
      NumofTasks_TaskQ_Retry_Remote="$(ssh -n "$remote_ep" "find /home/medsrv/var/taskqueue/.retry -type f 2>/dev/null | xargs grep -il \"$suid\" 2>/dev/null" | wc -l)"
      NumofTasks_TaskQ_Failed_Remote="$(ssh -n "$remote_ep" "find /home/medsrv/var/taskqueue/.failed -type f 2>/dev/null | xargs grep -il \"$suid\" 2>/dev/null" | wc -l)"
      NumofTasks_DB_Q_Remote="$(ssh -n "$remote_ep" "sql.sh \"SELECT COUNT(*) FROM TaskQueue WHERE STYIUID='$suid'\" -N" 2>/dev/null)"
    fi
  else
    Dcstudy_D_Remote="N/A"
    StudyDir_Remote="N/A"
    Storestate_ProcessMode_Remote="N/A"
    NumofObj_DB_Remote="N/A"
    NumofImg_DB_Remote="N/A"
    NumofObj_FS_Remote="N/A"
    NumofFilesIN_VarLock_Remote="N/A"
    NumofFilesIN_TMP_Remote1="N/A"
    NumofFilesIN_TMP_Remote2="N/A"
    NumofTasks_cpuQ_Remote="N/A"
    NumofTasks_netQ_Remote="N/A"
    NumofTasks_TaskQ_Sched_Remote="N/A"
    NumofTasks_TaskQ_Retry_Remote="N/A"
    NumofTasks_TaskQ_Failed_Remote="N/A"
    NumofTasks_DB_Q_Remote="N/A"
  fi
}

compareObjects() {
  if [ -n "$remote_ep" -a -n "$StudyDir_Local" -a -n "$StudyDir_Remote" ]; then
    local local_objects=$(ls "$StudyDir_Local" 2>/dev/null)
    local remote_objects=$(ssh -n "$remote_ep" "ls \"$StudyDir_Remote\" 2>/dev/null")
    
    echo "Objects present in source filesystem but missing in target filesystem:"
    local result="$(comm -23 <(echo "$local_objects" | sort) <(echo "$remote_objects" | sort))"

    if [ -n "$result" ]; then
      echo "$result"
    else
      echo "No missing objects found."
    fi
  else
    echo "Missing required information to compare objects. Ensure both local and remote directories are specified."
  fi
}

compareDBObjects() {
  if [ -n "$remote_ep" -a -n "$suid" ]; then
    local local_objects=$(sql.sh "SELECT FNAME FROM Dcobject WHERE STYIUID='$suid'" -N)
    local remote_objects=$(ssh -n "$remote_ep" "sql.sh \"SELECT FNAME FROM Dcobject WHERE STYIUID='$suid'\" -N")

    echo "Objects present in source database but missing in target database:"
    local result="$(comm -23 <(echo "$local_objects" | sort) <(echo "$remote_objects" | sort))"

    if [ -n "$result" ]; then
      echo "$result"
    else
      echo "No missing database objects found."
    fi
  else
    echo "Missing required information to compare database objects. Ensure SUID and remote endpoint are specified."
  fi
}

printInfo() {
  printf "### STUDY INFO: (L/R) ###\n"
  printf ":TARGET: %s\n" "$remote_ep"
  printf "SUID: %s\n" "$suid"
  printf "StyDir Local: %s\n" "$StudyDir_Local"
  printf "StyDir Remote: %s\n" "$StudyDir_Remote"
  printf "\tProcessMode: %s/%s\n" "${Storestate_ProcessMode_Local//\"/}" "${Storestate_ProcessMode_Remote//\"/}"
  printf "\tDcstudy_D  : %s/%s\n" "$Dcstudy_D_Local" "$Dcstudy_D_Remote"
  printf "\tLock Files : %s/%s\n" "$NumofFilesIN_VarLock_Local" "$NumofFilesIN_VarLock_Remote"
  printf "\tTmp Files A: %s/%s\n" "$NumofFilesIN_TMP_Local1" "$NumofFilesIN_TMP_Remote1"
  printf "\tTmp Files B: %s/%s\n" "$NumofFilesIN_TMP_Local2" "$NumofFilesIN_TMP_Remote2"
  printf "\tNumofImg_DB: %s/%s\n" "$NumofImg_DB_Local" "$NumofImg_DB_Remote"
  printf "\tNumofObj_DB: %s/%s\n" "$NumofObj_DB_Local" "$NumofObj_DB_Remote"
  printf "\tNumofObj_FS: %s/%s\n" "$NumofObj_FS_Local" "$NumofObj_FS_Remote"
  printf "TASKS:\n"
  printf "\tCpuQ : %s/%s\n" "$NumofTasks_cpuQ_Local" "$NumofTasks_cpuQ_Remote"
  printf "\tNetQ : %s/%s\n" "$NumofTasks_netQ_Local" "$NumofTasks_netQ_Remote"
  printf "\tTQ Sched: %s/%s\n" "$NumofTasks_TaskQ_Sched_Local" "$NumofTasks_TaskQ_Sched_Remote"
  printf "\tTQ Retry: %s/%s\n" "$NumofTasks_TaskQ_Retry_Local" "$NumofTasks_TaskQ_Retry_Remote"
  printf "\tTQ Failed: %s/%s\n" "$NumofTasks_TaskQ_Failed_Local" "$NumofTasks_TaskQ_Failed_Remote"
  printf "\tTasks DB_Q : %s/%s\n" "$NumofTasks_DB_Q_Local" "$NumofTasks_DB_Q_Remote"
}

[ $# -eq 0 ] && DisplayUsage
while [ -n "$1" ]; do
  case $1 in
    --help|-h)   DisplayUsage ;;
    --study|-S|-s)  suid="$2"; shift ;;
    --verbose|-v)   verbose="v" ;;
    --remote-host)  remote_ep="$2"; shift ;;
    --show-missing-objects) show_missing_objects="yes" ;;
    *)        printf "Unknown option (ignored): %s\n" "$1"; DisplayUsage ;;
  esac
  shift
done

if [ -z "$suid" ]; then
  echo "ERROR: Missing SUID"
  exit 1
fi

getLocalInfo
getRemoteInfo
printInfo

if [ "$show_missing_objects" = "yes" ]; then
  compareObjects
  compareDBObjects
fi
