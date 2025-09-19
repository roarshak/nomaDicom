#!/bin/bash
#shellcheck disable=SC2267
# FUNC PREFIXES:
  #  - yn: Yes/No question
  #  - wf: Write file
  #  - rf: Read file
  #  - rm: Remove file
  #  - mv: Move file
  #  - cp: Copy file
  #  - exe: Execute command
  #  - puf: Prompt user for...
#
## PARAMETERS, POSITIONAL
  numOfArguments=$#
  executeInScreen="$1"
  tqscriptname="$2"
  tqqueue="$3"
  tqpeer="$4"
#
## VARIABLES
  debugging=0
  numof_CPU_Cores=$(grep -c ^processor /proc/cpuinfo)
  thisScript="$(basename "$0")"
#
## USER CHECK: RUN AS ROOT
  usrChk_root() {
    if [[ "$(whoami)" != "root" ]]; then echo "Script must be run as user: root, exiting"; return 1; fi
  }
  usrChk_medsrv() {
    if [[ "$(whoami)" != "medsrv" ]]; then echo "Script must be run as user: medsrv, exiting"; return 1; fi
  }
#
## SCREEN CALL CHECK
  scrnChk() {
    if [[ $numOfArguments -gt 0 ]]; then
      # Validate provided values
      input_list="$1"
      if [[ ! -f $input_list ]]; then
        echo "ERROR: cleanSpecificTasks.sh called as a screen but required positional parameter input list file does not exist, exiting."
        exit 1
      fi
      cat $input_list | xargs -i -P "$numof_CPU_Cores" -n 1 /home/medsrv/component/taskd/cleanupTaskDbase.sh {}

      #Testing
      #while loop counting to 10
      # for i in {1..10}; do
      #   echo "Looping $i"
      #   sleep 3
      # done
    fi
  }
#
## VERIFY TASKNAME DATABASE INDEX
  exe_restartMedsrv() {
    read -rp "Changes to dcfldndx.conf require medsrv restart. Restart now? (y/n) " resp
    if [[ $resp == "y" ]]; then
      echo "Restarting medsrv..."
      systemctl restart medsrv
      echo -en "Stopping MedSrv..."
      if ! service medsrv stop; then 
        echo -en "FAILED\n"
        echo "ERROR: Could not stop MedSrv, exiting"
        exit 1
      else 
        echo -en "done\n"
      fi

      echo -en "Starting MedSrv..."; sleep 3
      if ! service medsrv start; then
        echo -en "FAILED\n"
        echo "ERROR: Could not start MedSrv, exiting"
        exit 1
      else
        echo -en "done\n"
      fi
    else
      echo "Exiting..."
      exit 1
    fi
  }
  checkTasknameIndex() {
    if ! grep "'xxTASKNAME', 'TQNAME', 'TaskQueue', 'UNIQUE'" /home/medsrv/var/conf/dcfldndx.conf; then
      [[ debugging -ge 1 ]] && echo "DEBUG: ERROR - Did not find 'xxTASKNAME', 'TQNAME', 'TaskQueue', 'UNIQUE' in dcfldndx.conf"
      sleep 0.5
      [[ debugging -ge 1 ]] && echo "DEBUG: FIX - Adding 'xxTASKNAME', 'TQNAME', 'TaskQueue', 'UNIQUE' to dcfldndx.conf"
      echo "'xxTASKNAME', 'TQNAME', 'TaskQueue', 'UNIQUE'" >> /home/medsrv/var/conf/dcfldndx.conf
      #exe_restartMedsrv
      echo "Please exit to ROOT user and restart medsrv for the database index addition to take effect!"
      exit 1
    else
      [[ debugging -ge 1 ]] && echo "DEBUG: Found 'xxTASKNAME', 'TQNAME', 'TaskQueue', 'UNIQUE' in dcfldndx.conf"
      # Extended check
      key_present_in_db="$(sql.sh "SHOW INDEX FROM imagemedical.TaskQueue WHERE column_name='TQNAME' AND key_name like '%TASKNAME%';" -N|awk '{print $3}')"
      if [[ "$key_present_in_db" != "xxTASKNAME" ]]; then
        # The key has been added in ~/var/conf/dcfldndx.conf but has been applied to the database
        echo "ERROR: The \"TaksName\" key/index is present in ~/var/conf/dcfldndx.conf but has not been applied to the database!"
        echo "Contents of ~/var/conf/dcfldndx.conf:"
        cat ~/var/conf/dcfldndx.conf
        echo
        echo "sql.sh \"SHOW INDEX FROM imagemedical.TaskQueue WHERE column_name='TQNAME'\" -t"
        sql.sh "SHOW INDEX FROM imagemedical.TaskQueue WHERE column_name='TQNAME'" -t
        echo
        echo "There is nothing stopping one from executing the task clean-up without"
        echo "having the index applied, but it will be MUCH slower. Exiting."
        exit 1
      else
        [[ debugging -ge 1 ]] && echo "DEBUG: Found 'xxTASKNAME' INDEX applied to 'TQNAME' column in the imagemedical DB"
      fi
    fi
  }
#
## GATHER REQUIRED INFO
  puf_tqscriptname() {
    echo; PS3="Select a \"TQSCRIPTNAME\" filter: "
    mapfile -t files < <(echo "select DISTINCT(TQSCRIPTNAME)
      FROM imagemedical.TaskQueue
      GROUP BY (1);" | /home/medsrv/component/mysql/bin/mysql -N -u medsrv imagemedical)
    # Enable extended globbing. This lets us use @(foo|bar) to
    # match either 'foo' or 'bar'.
    shopt -s extglob
    # Start building the string to match against.
    string="@(${files[0]}"
    # Add the rest of the files to the string
    for((i=1;i<${#files[@]};i++)); do string+="|${files[$i]}"; done
    # Close the parenthesis. $string is now @(file1|file2|...|fileN)
    string+=")"
    select file in "${files[@]}" "quit - I will come back later..."
    do
      case $file in
        $string)
          tqscriptname=$file
          tqscriptname="${file%% *}"
          sql_WhereClause="TQSCRIPTNAME='${file%% *}'"
          [[ debugging -ge 1 ]] && echo "DEBUG: You selected the [$tqscriptname] script name."
          break;;
        "quit - I will come back later...")
          exit;;
        *)
          echo "Please choose a number from 1 to $((${#files[*]}+1))"
          #echo "Please choose a number from 1 to ${#files[*]}"
          ;;
      esac
    done
    [[ -z "$tqscriptname" ]] && echo "ERROR: TQSCRIPTNAME variable is empty, exiting" && exit 1

    # We only clean tasks out of INACTIVE queues; failed & suspended.
    # Check the failed/suspended queue for tasks of the chosen "tqscriptname".
    # If none, display error and exit
    # numof_tasks="$(sql.sh "select count(*) from imagemedical.TaskQueue where TQSCRIPTNAME='$tqscriptname' and TQQUEUE IN('failed','suspended');" -N)"
    # if [[ "$numof_tasks" -eq 0 ]]; then
    #   echo "ERROR: No tasks found in the failed/suspended queue with the chosen TQSCRIPTNAME($tqscriptname), exiting"
    #   exit 1
    # fi
  }
  puf_tqqueue() {
    #echo "Select a \"TQQUEUE\" filter: "
    echo
    #runuser -l medsrv qst.sh
    qst.sh
    echo
    PS3="Select a \"TQQUEUE\" filter: "
    # Collect the files in the array $files
    # files=( $(
    #   echo "select DISTINCT(TQQUEUE)
    #   FROM imagemedical.TaskQueue
    #   GROUP BY (1);" | /home/medsrv/component/mysql/bin/mysql -N -u medsrv imagemedical))
    mapfile -t files < <(echo "select DISTINCT(TQQUEUE)
      FROM imagemedical.TaskQueue
      GROUP BY (1);" | /home/medsrv/component/mysql/bin/mysql -N -u medsrv imagemedical)
    
    # Enable extended globbing. This lets us use @(foo|bar) to
    # match either 'foo' or 'bar'.
    shopt -s extglob
    # Start building the string to match against.
    string="@(${files[0]}"
    # Add the rest of the files to the string
    for((i=1;i<${#files[@]};i++)); do string+="|${files[$i]}"; done
    # Close the parenthesis. $string is now @(file1|file2|...|fileN)
    string+=")"
    select file in "${files[@]}" "quit - I will come back later..."
    do
      case $file in
        #"${files[*]}")
        $string)
          #tqqueue=$file
          tqqueue="${file%% *}"
          sql_WhereClause="${sql_WhereClause} AND TQQUEUE='$tqqueue'"
          [[ debugging -ge 1 ]] && echo "DEBUG: You select the [$tqqueue] task queue."
          break;;
        "quit - I will come back later...")
          exit;;
        *)
          echo "Please choose a number from 1 to $((${#files[*]}+1))"
          #echo "Please choose a number from 1 to ${#files[*]}"
          ;;
      esac
    done
    [[ -z "$tqqueue" ]] && echo "ERROR: TQQUEUE is empty, exiting" && exit 1
  }
  puf_tqpeer() {
    echo
    PS3="Select a \"TQPEER\" filter: "
    # Collect the files in the array $files
    # files=( $(
    #   echo "select DISTINCT(TQPEER)
    #   FROM imagemedical.TaskQueue
    #   WHERE TQQUEUE='$tqqueue'
    #   GROUP BY (1);" | /home/medsrv/component/mysql/bin/mysql -N -u medsrv imagemedical))
    mapfile -t files < <(echo "select DISTINCT(TQPEER)
      FROM imagemedical.TaskQueue
      GROUP BY (1);" | /home/medsrv/component/mysql/bin/mysql -N -u medsrv imagemedical)
    
    # Enable extended globbing. This lets us use @(foo|bar) to
    # match either 'foo' or 'bar'.
    shopt -s extglob
    # Start building the string to match against.
    string="@(${files[0]}"
    # Add the rest of the files to the string
    for((i=1;i<${#files[@]};i++)); do string+="|${files[$i]}"; done
    # Close the parenthesis. $string is now @(file1|file2|...|fileN)
    string+=")"
    select file in "${files[@]}" "I don't want to filter by any of these peers." "quit - I will come back later..."
    do
      case $file in
        $string)
          tqpeer=$file
          tqpeer="${file%% *}"
          sql_WhereClause="${sql_WhereClause} AND TQPEER='$tqpeer'"
          [[ debugging -ge 1 ]] && echo "DEBUG: You selected the [$tqpeer] peer."
          isFilteringPeer="y"
          break;;
        "I don't want to filter by any of these peers.")
          isFilteringPeer="n"
          break;;
        "quit - I will come back later...")
          exit;;
        *)
          echo "Please choose a number from 1 to $((${#files[*]}+1))"
          #echo "Please choose a number from 1 to ${#files[*]}"
          ;;
      esac
    done
  }
  puf_isWorkDoneInAScreenSession() {
    PS3="How do you want to run this script: "
    ## Show the menu. This will list all options and the string "quit"
    select choice in "Execute task removal in THIS terminal" "Execute task removal in a seperate screen" "quit - I will come back later...";
    do
      case $choice in
      "Execute task removal in THIS terminal")
        areWeExecutingInScreen="n"
        break;;
      "Execute task removal in a seperate screen")
        areWeExecutingInScreen="y"
        break;;
      "quit - I will come back later...")
        exit;;
      *)
        choice=""
        echo "Please choose a number from 1 to 3";;
      esac
    done
  }
#
## PRE-EXECUTION QUEUE VALIDATION
  inactive_queues_only() {
    #numof_inactive_q_exams=$(sql.sh "SELECT count(*) FROM imagemedical.TaskQueue WHERE TQQUEUE IN('failed','suspended') AND ${sql_WhereClause};" -N)
    numof_active_q_exams=$(sql.sh "SELECT count(*) FROM imagemedical.TaskQueue WHERE TQQUEUE NOT IN('failed','suspended') AND ${sql_WhereClause};" -N)

    if [[ $numof_active_q_exams -gt 0 ]]; then
      sql.sh "UPDATE imagemedical.TaskQueue set TQQUEUE='suspended' WHERE TQQUEUE NOT IN('failed','suspended') AND ${sql_WhereClause};"
    fi
  }
#
## CLEAN TASKS
  pr_results() {
    echo "select TQSCRIPTNAME, TQPEER, TQQUEUE, COUNT(1) from TaskQueue where TQQUEUE IN('failed','suspended') AND ${sql_WhereClause} GROUP BY TQSCRIPTNAME, TQPEER, TQQUEUE ORDER BY TQSCRIPTNAME, TQPEER, TQQUEUE" | /home/medsrv/component/mysql/bin/mysql -t -u medsrv imagemedical
    echo "select TQCONTENT from TaskQueue where TQQUEUE IN('failed','suspended') AND ${sql_WhereClause} LIMIT 5\G" | /home/medsrv/component/mysql/bin/mysql -N -u medsrv imagemedical
  }
  countdown_timer() {
    echo -en "Executing in "
    #for i in {1..5}; do
    for i in {5..1}; do
      echo -en "${i}, "
      sleep 1
    done
    echo -en "GO!\n"
  }
  yn_continueCleaningTasks() {
    read -rp "Are you sure you want to clean these tasks? (y/n): " exeCleanConfirmation
    if [[ "$exeCleanConfirmation" = "y" ]]; then 
      inactive_queues_only
      filename="lsof_tqnames_for_cleaning_$(date "+%Y%m%d-%H%M%S").txt"
      sql.sh "select TQNAME from TaskQueue where TQQUEUE IN('failed','suspended') AND ${sql_WhereClause}" -N > "${PWD}/${filename}"
      if [[ "$areWeExecutingInScreen" == "y" ]]; then
        #echo -en "Executing in screen session for $tqscriptname on $tqqueue with $tqpeer, "
        countdown_timer
        #screen -dmS "cleaning_${tqscriptname}_tasks" bash "${PWD}/${thisScript}" inscreen "$tqscriptname" "$tqqueue" "$tqpeer"
        screen -dmS "cleaning_${tqscriptname}_tasks" bash "${PWD}/${thisScript}" "${PWD}/${filename}"
      else
        #echo -en "Executing in this terminal for $tqscriptname on $tqqueue with $tqpeer "
        countdown_timer
        #runuser -l medsrv -- sql.sh "select TQNAME from TaskQueue where TQQUEUE NOT IN('failed','suspended') AND ${sql_WhereClause}" -N | xargs -i -P "$numof_CPU_Cores" -n 1 /home/medsrv/component/taskd/cleanupTaskDbase.sh {}
        sql.sh "select TQNAME from TaskQueue where TQQUEUE IN('failed','suspended') AND ${sql_WhereClause}" -N | xargs -i -P "$numof_CPU_Cores" -n 1 /home/medsrv/component/taskd/cleanupTaskDbase.sh {}
      fi
    else
      echo "Exiting" && exit 1
    fi
  }
  yn_cleanTheseTasks() {
    echo
    pr_results
    if [[ "$areWeExecutingInScreen" == "y" ]]; then
      echo -en "\nThe above tasks will be cleaned in a SEPERATE SCREEN SESSION.\n"
    else
      echo -en "\nThe above tasks will be cleaned in THIS TERMINAL.\n"
    fi
    yn_continueCleaningTasks
  }
#
## MAIN
  usrChk_medsrv
  scrnChk
  checkTasknameIndex
  puf_isWorkDoneInAScreenSession
  puf_tqscriptname
  #puf_tqqueue
  puf_tqpeer
  yn_cleanTheseTasks