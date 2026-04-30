#!/bin/bash
. /home/medsrv/work/jbooth/.voyager/voyager-service.cfg

while true; do
  . /home/medsrv/work/jbooth/.voyager-service.cfg
  #
  for migration_case in $(echo "$JB_ACTIVE_MIG_CASE_NUMBERS"); do
    #check for a migrate.sh process running out of $migration 's wdir
    #A Case's work directory
    currentCase_WDir="${JB_DEFAULT_BASEDIR}/case_${migration_case}/voyager-migration"
    #Work dirs of all migrate.sh processes running
    migprocs_wdirs=$(for pid in $(ps aux | grep -v grep | grep migrate.sh | awk '{print $2}'); do lsof -p $pid | grep cwd | rev | cut -d ' ' -f 1 | rev ; done))
    #Check is the currentCase_WDir is in th elist of migrpocs_wdirs
    if grep -q "currentCase_WDir" "$migprocs_wdirs"; then
      #We found the currentCase_WDir in the list of works dirs of a running migrate.sh process
      #No need to restart it
      echo "all is well" >/dev/null
    else
      #currentCase_WDir not found in list of work dirs of any running migrate.sh processes
      #We need to restart the migrate.sh process for this currentCase_WDir
      echo "Case currentCase_WDir migrate.sh not found, restarting..." >/dev/null
      ( cd ${currentCase_WDir} && exec ./migrate.sh --quiet -M ) &
    fi
  done
  sleep JB_VOYAGER_SVC_SLEEP_DUR
done

# [medsrv@Migration-Team-PACS-Hub1-v8 conforMIS]$ ps aux | grep -v grep | grep migrate.sh
# medsrv    8466  0.0  0.0 114040  2504 pts/1    S+   11:49   0:00 /bin/bash ./migrate.sh -M
# [medsrv@Migration-Team-PACS-Hub1-v8 conforMIS]$ lsof -p 8466 | grep cwd | rev | cut -d ' ' -f 1 | rev

