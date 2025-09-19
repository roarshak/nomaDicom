#!/bin/bash
workDir="/home/medsrv/work/jbooth/case_45353/voyager-migration"
cd "$workDir"
# 300 seconds = 5 minutes
sleeperTime="300"
function source_migrateCfg () {
  ### check4 & source migrate.cfg
  if [[ -f "${workDir}/cfg/migrate.cfg" ]]; then
    . "${workDir}/cfg/migrate.cfg"
    . "$MIG_SHARED_FUNCTION_LIBRARY_FULLPATH"
  elif [[ -f cfg/migrate.cfg ]]; then
    . "${workDir}/cfg/migrate.cfg"
    . "$MIG_SHARED_FUNCTION_LIBRARY_FULLPATH"
  else
    echo "Unable to find/source required files migrate.cfg and sharedMigrationLibrary.lib; exiting"
    exit 1
  fi
  
  ### Germane variables gained via migrate.cfg
  # WDIR="$PWD"
  # tmp_dir="${WDIR}/.tmp"
  # tmp_compression="${WDIR}/.tmp/compression"
  # checkLoadInterval="2"
  # memGBfree_limit="4"
  # memGBused_limit="4"
  # . ~/var/arch/archive.cfg
}

function tmpComprDirChk () {
  [[ ! -d "$tmp_compression" ]] && mkdir -p "$tmp_compression"
}

function isCompressScriptAvailable () {
  if [[ ! -f "${workDir}/tools/compressExam.sh" ]]; then
    echo "ERROR: compressExam.sh (${workDir}/tools/compressExam.sh) not found, exiting"
    exit 1
  fi
}

function isCompressionCurrentlyRunning () {
  set -x
  # Check4 pid file = it is already running
  compressionIsActive=$(find "${tmp_compression}" -type f | grep -i "compression_actively_running.pid_")
  if [[ -n "$compressionIsActive" ]]; then
    # If $compressionIsActive is not empty, it means compression is actively running
    # 0 = success
    return 0
  else
    # If $compressionIsActive is empty, it means compression is not currently running
    # 1 = failure
    return 1
  fi
  set +x
}

function exe_Study_Level_Validation () {
  ${workDir}/migrate.sh -S >/dev/null 2>&1
}

function compress_migrated_exams () {
  sql.sh "select styiuid from qrmigration.demoinfo where skip='y' and compressed='n'" -N | \
  while read suid; do
    [[ -z "$suid" ]] && continue
    echo "$(date) compressing $suid"
    ${workDir}/tools/compressExam.sh $suid
    # Below sql update already exists in compressExam.sh
    # sql.sh "update qrmigration.demoinfo set compressed='y' where styiuid='$suid'"
  done
}

function runCompression () {
  touch "${tmp_compression}/compression_actively_running.pid_$$"
  exe_Study_Level_Validation
  compress_migrated_exams
  [[ -f "${tmp_compression}/compression_actively_running.pid_$$" ]] && rm "${tmp_compression}/compression_actively_running.pid_$$"
}

# 0 - success; its running. 1 - failure; its not running
isCompressionCurrentlyRunning && exit 1
while :; do
  # Pre-run checks
  source_migrateCfg
  tmpComprDirChk
  isCompressScriptAvailable
  runCompression
  echo "Sleeping $sleeperTime seconds"
  sleep $sleeperTime
done
