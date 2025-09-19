#!/bin/bash
#
#

#TODO:
# - Load Aware
# - Verbose/Non-verbose
# - Progress indicator [123 of 456]
workDir="$PWD"
thisScript="$(basename $0)"
. "$HOME/etc/setenv.sh" && echo "$(date) Sourced ~/etc/setenv.sh" # Source setenv.sh for $MYSQL_ROOT_PW
. "${workDir}/sa-compression.cfg" && echo "$(date) Sourced sa-compression.cfg"


function exitTrap () {
  exit
}
trap exitTrap EXIT

executeInScreen="$1"

function src_saCompressionCFG () {
  if [[ -e sa-compression.cfg ]]; then
    if [[ -n $saCompressionCFG_modifiedTimeLast ]]; then
      saCompressionCFG_modifiedTimeNow=$(stat -c "%Y" sa-compression.cfg)
      if [[ $saCompressionCFG_modifiedTimeNow -gt $saCompressionCFG_modifiedTimeLast ]]; then #if its been modified
        . sa-compression.cfg && saCompressionCFG_modifiedTimeLast=$saCompressionCFG_modifiedTimeNow
      else # This will source the drop file even if sa-compression.cfg hasn't changed
        [[ -f sa-compression.cfg.d ]] && . sa-compression.cfg.d
      fi
    else #if it IS empty
      saCompressionCFG_modifiedTimeLast=$(stat -c "%Y" sa-compression.cfg)
      . sa-compression.cfg
    fi
  fi
}

function add_sql_privileges () {
  # Requires (1) positional parameter
  # 1) DB Name
  ENTER2CONTINUE "Function [${FUNCNAME[0]}] called..."
  local database="$1"
  if [[ -z $database ]]; then
    echo -e "${RED}ERROR${NC}: Required argument (${YELLOW}\$database${NC} name) missing from add_sql_privileges function call, exiting"
    echo
    exit 1
  fi 
  echo "GRANT ALL PRIVILEGES ON ${database}.* TO 'medsrv'@'localhost';" | /home/medsrv/component/mysql/bin/mysql --user=root --password="$MYSQL_ROOT_PW" &>/dev/null
  echo "flush privileges;" | /home/medsrv/component/mysql/bin/mysql --user=root --password="$MYSQL_ROOT_PW" &>/dev/null
  #ENTER2CONTINUE "Just executed \"GRANT\FLUSH PRIVILEGES\" against ${database}."
}

function hasdb () {
  # Requires (1) positional parameter
  # 1) DB Name
  ENTER2CONTINUE "Function [${FUNCNAME[0]}] called..."
  local database="$1"
  if [[ -z $database ]]; then
    echo -e "${RED}ERROR${NC}: Required argument (${YELLOW}\$database${NC} name) missing from hasdb function call, exiting"
    echo
    exit 1
  fi
  local dbPresent
  dbPresent=$(echo "show databases;"  | ~/component/mysql/bin/mysql | grep "$database" )
  if [ -z "$dbPresent" ]; then
    echo -e "${database} Database does not exist, creating it"
    echo "create database if not exists $database;" | ~/component/mysql/bin/mysql
    add_sql_privileges "$database"
    dbPresent=$(echo "show databases;"  | ~/component/mysql/bin/mysql | grep "$database" )
    if [ -z "$dbPresent" ]; then
      echo "${RED}ERROR${NC}: failed to create database, exiting"
      exit 1
    fi
    #Do this in hasdbtble function
    #cat "$dbSqlFile" | ~/component/mysql/bin/mysql $database
  else
    echo -e "The $database Database already exists, no need to create it"
  fi
}

function hasdbtbl () {
  # Requires (3) positional parameters
  # 1) DB Name
  # 2) DB Table Name
  # 3) DB sql File
  ENTER2CONTINUE "Function [${FUNCNAME[0]}] called..."
  local database="$1"
  local table="$2"
  local dbSqlFile="$3"
  if [[ -z $database || -z $table || -z $dbSqlFile ]]; then
    echo -e "${RED}ERROR${NC}: Required arguments (${YELLOW}\$database${NC} name, ${YELLOW}\$table${NC} name, and ${YELLOW}\$dbSqlFile${NC} file) missing from hasdbtbl function call, exiting"
    echo
    exit 1
  fi 
  tblPresent=$(echo "show tables;" | ~/component/mysql/bin/mysql "$database" | grep "$table")
  if [ -z "$tblPresent" ]; then
    echo -e "${database} Database table ${table} does not exist, creating it"
    ~/component/mysql/bin/mysql --user=root --password="$MYSQL_ROOT_PW" "$database" <"${dbSqlFile}"
    add_sql_privileges "$database"
    tblPresent=$(echo "show tables;" | ~/component/mysql/bin/mysql "$database" | grep "$table")
    if [ -z "$tblPresent" ]; then
      echo "${RED}ERROR${NC}: Unable to create database table, exiting"
      exit 1
    fi
  else
    echo -e "${database} Database table ${table} already exists, no need to create it"
  fi
}

function importStyListToDB () {
  # Requires (1) positional parameter
  # 1) Sty List File Name
  ENTER2CONTINUE "Function [${FUNCNAME[0]}] called..."
  local styList_file="$1"
  local styList_file_fullpath
  styList_file_fullpath="$(find "$PWD" -xdev -name "$(basename "$styList_file")")"
  if [[ -z "$styList_file" ]] || [[ ! -f "$styList_file" ]]; then
    echo -e "${RED}ERROR${NC}: Required arguments (${YELLOW}\$styList_file${NC}, and ${YELLOW}\$styList_file_fullpath${NC}) missing from importStyListToDB function call, exiting..."
    exit
  elif [[ -z "$styList_file_fullpath" ]] || [[ ! -f "$styList_file_fullpath" ]]; then
    echo -e "${RED}ERROR${NC}: importStyListToDB function unable to identify fullpath of study list for import. Exiting..."
    exit
  fi

  #Load the extract
  echo -e "Loading in the study level export..."
  echo "LOAD DATA LOCAL INFILE '${styList_file_fullpath}' INTO TABLE jbsacompression.jbc (styiuid);" | ~/component/mysql/bin/mysql --local-infile jbsacompression
}

function insertStyFSLocToDB () {
  ENTER2CONTINUE "Function [${FUNCNAME[0]}] called..."
  while read -r suid; do
    unset stydir
    local stydir
    stydir=$(~/component/repositoryhandler/scripts/locateStudy.sh -d "$suid")
    if [[ -z "$stydir" || ! -d "$stydir" ]]; then
      sql.sh "update jbsacompression.jbc set error='y', comment='unable to get study dir / FS Loc' where styiuid='$suid'"
      #echo "ERROR: Unable to get study directory from locateStudy.sh, skipping"
    elif [[ "$stydir" =~ "differ" ]]; then 
      sql.sh "update jbsacompression.jbc set error='y', comment='multi-repo exam' where styiuid='$suid'"
      #echo "ERROR: Multi-repo exam, skipping"
      #echo "Study Dir: $stydir"
    else
      sql.sh "update jbsacompression.jbc set stydir='$stydir' where styiuid='$suid'"
    fi
    if shopt -po xtrace >/dev/null; then sleep 1; fi
  #done <"$styList"
  done < <(echo "select styiuid from jbsacompression.jbc where stydir IS NULL and error!='y';" | /home/medsrv/component/mysql/bin/mysql -N --database=jbsacompression)
}

function compressExam () {
  ENTER2CONTINUE "Function [${FUNCNAME[0]}] called..."
  local skippedUS=""
  local suid="$1"
  local stydir="$2"
  
  function compress_study_xargs () {
    #compress study objects in parallel
    ENTER2CONTINUE "Function [${FUNCNAME[0]}] called..."
    [[ $verbose -ge 1 ]] && comprObj_OPTS="-v"
    echo "$allObjs_fullpath" | xargs -I {} -P "$numof_CPU_Cores" -n 1 "${PWD}"/compressObject.sh "$comprObj_OPTS" -i {}
  }
  # function compress_study_xargs () {
  #   #compress study objects in parallel
  #   ENTER2CONTINUE "Function [${FUNCNAME[0]}] called..."
  #   if [[ $Verbose ]]; then
  #     [[ $debugging -ge 1 ]] && { echo "Cmd: echo \"$allObjs_fullpath\" | xargs -I {} -P \"$numof_CPU_Cores\" -n 1 \"${PWD}\"/compressObject.sh -v -i {}" ; ENTER2CONTINUE ; }
  #     echo "$allObjs_fullpath" | xargs -I {} -P "$numof_CPU_Cores" -n 1 "${PWD}"/compressObject.sh -v -i {}
  #   else
  #     [[ $debugging -ge 1 ]] && { echo "Cmd: echo \"$allObjs_fullpath\" | xargs -I {} -P \"$numof_CPU_Cores\" -n 1 \"${PWD}\"/compressObject.sh -i {}" ; ENTER2CONTINUE ; }
  #     echo "$allObjs_fullpath" | xargs -I {} -P "$numof_CPU_Cores" -n 1 "${PWD}"/compressObject.sh -i {}
  #   fi
  # }
  function updateDB_objSize_xargs () {
    #update obj size in DB
    ENTER2CONTINUE "Function [${FUNCNAME[0]}] called..."
    # shellcheck disable=SC2016
    echo "$allObjs_size_fullpath_fname_suid" | xargs -l -P "$numof_CPU_Cores" bash -c 'sql.sh "update Dcobject set SIZE='\''$0'\'' where STYIUID='\''$3'\'' and FNAME='\''$2'\''"'
    ENTER2CONTINUE "Function [${FUNCNAME[0]}] called..."
  }
  function updateDB_stySize () {
    #update sty size in DB
    ENTER2CONTINUE "Function [${FUNCNAME[0]}] called..."
    sql.sh "update Dcstudy s, (select SUM(SIZE) as newSum from Dcobject where STYIUID='$suid') as sum set s.SUMSIZE = sum.newSum where s.STYIUID='$suid'"
    ENTER2CONTINUE "Function [${FUNCNAME[0]}] called..."
  }
  function updateDB_migdb_stySize () {
    #update sty size in DB
    ENTER2CONTINUE "Function [${FUNCNAME[0]}] called..."
    sql.sh "update jbsacompression.jbc set compressed='y' where styiuid='$suid'"
  }
  
  [[ ! -d "$stydir" ]] && stydir=$(~/component/repositoryhandler/scripts/locateStudy.sh -d "$suid")
  if [[ -z "$stydir" || ! -d "$stydir" ]]; then
    sql.sh "update jbsacompression.jbc set error='y', comment='unable to get study dir / FS Loc' where styiuid='$suid'"
    [[ $verbose -ge 1 ]] && echo "ERROR: Unable to get study directory from locateStudy.sh, skipping"
  elif [[ "$stydir" =~ "differ" ]]; then 
    sql.sh "update jbsacompression.jbc set error='y', comment='multi-repo exam' where styiuid='$suid'"
    [[ $verbose -ge 1 ]] && echo "ERROR: Multi-repo exam, skipping"
    [[ $verbose -ge 1 ]] && echo "Study Dir: $stydir"
  else
    allObjs_fullpath="$(find "$stydir" -maxdepth 1 -type f)"
    # shellcheck disable=SC2016
    allObjs_size_fullpath_fname="$(echo "$allObjs_fullpath" | xargs -i du -b {} | xargs -l bash -c 'echo $0 $1 $(basename $1)')"
    ENTER2CONTINUE "Function [${FUNCNAME[0]}] called..."
    allObjs_size_fullpath_fname_suid="$(echo "$allObjs_size_fullpath_fname" | while read -r string; do echo "$string $suid"; done )"
    ENTER2CONTINUE "Function [${FUNCNAME[0]}] called..."
    compress_study_xargs || skippedUS="yes"
    updateDB_objSize_xargs
    updateDB_stySize
    updateDB_migdb_stySize
    ENTER2CONTINUE
  fi
  [[ $skippedUS == "yes" ]] && return 125
}

function updateSkippedUSexam () {
  local suid="$1"
  ENTER2CONTINUE "Function [${FUNCNAME[0]}] called..."
  sql.sh "update jbsacompression.jbc set compressed='n', error='y', comment='Skipped compressing US objects' where styiuid='$suid'"
}

function compressionLoop () {
  ENTER2CONTINUE "Function [${FUNCNAME[0]}] called..."
  local total
  local cnt=0
  local lsof_examsToCompress
  #lsof_examsToCompress="$(sql.sh "select styiuid, stydir from jbsacompression.jbc where error='n' and compressed='n'" -N)"
  lsof_examsToCompress="$(sql.sh "select c.styiuid, c.stydir from jbsacompression.jbc as c join imagemedical.Dcstudy as e on c.styiuid=e.styiuid where c.error='n' and c.compressed='n' and e.modality not like '%US%'" -N)"
  total=$(wc -l <<<"$lsof_examsToCompress")
  while read -r suid stydir; do
    if ! (( cnt % 5 )) ; then #if cnt is a multiple of 5
      src_saCompressionCFG
    fi
    ((cnt++))
    [[ -z "$suid" ]] && continue
    echo -e "$(date) [$cnt / $total] compressing $suid"
    compressExam "$suid" "$stydir"
    if [[ $? -eq 125 ]]; then
      updateSkippedUSexam "$suid"
    fi
    echo
  done <<<"$lsof_examsToCompress"
}

##########################################
##########################################
if [[ -z "$executeInScreen" ]]; then
  echo;echo
  PS3="Choose how to run this compression script: "
  ## Show the menu. This will list all options and the string "quit"
  select choice in "Execute compression in THIS terminal" "Execute compression in a seperate screen" "quit - I will come back later..."; do
    case $choice in
    "Execute compression in THIS terminal")
      break;;
    "Execute compression in a seperate screen")
      echo "Command: screen -dmS OOB_StandAlone_Compression bash \${PWD}/\${thisScript} inscreen"
      echo "Command: screen -dmS OOB_StandAlone_Compression bash ${PWD}/${thisScript} inscreen"
      screen -dmS OOB_StandAlone_Compression bash "${PWD}/${thisScript}" inscreen
      echo "The screen 'OOB_StandAlone_Compression' has been created to compress existing data. The screen will close once complete."
      exit;;
    "quit - I will come back later...")
      exit;;
    *)
      choice=""
      echo "Please choose a number from 1 to 3";;
    esac
  done
fi

hasdb jbsacompression
hasdbtbl jbsacompression jbc sa-compression.sql

while :; do
  [[ $verbose -ge 1 ]] && echo "$(date) Adding new exams to sa-compression databse"
  #echo "INSERT INTO jbsacompression.jbc (styiuid) SELECT STYIUID FROM imagemedical.Dcstudy where derived not in ('copy','shortcut') and mainst>='0' ON DUPLICATE KEY UPDATE jbsacompression.jbc.styiuid=jbsacompression.jbc.styiuid" | /home/medsrv/component/mysql/bin/mysql -N --database=jbsacompression
  src_saCompressionCFG
  $HOME/component/mysql/bin/mysql --batch --skip-column-names --database=$JBSAC_DB --execute "
  INSERT INTO jbsacompression.jbc (styiuid)
  SELECT    styiuid
  FROM      imagemedical.Dcstudy
  WHERE     derived NOT IN ('copy','shortcut')
  AND       mainst>='0'
  ON DUPLICATE KEY UPDATE 
            jbsacompression.jbc.styiuid=jbsacompression.jbc.styiuid;"

  compressionLoop
  echo -e "Sleeping $sleeperTime seconds between iterations..."
  sleep $sleeperTime
done
#set +x
