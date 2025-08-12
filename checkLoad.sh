#!/bin/sh
# shellcheck disable=SC3043
# AUTHER: Joel Booth
# DATE: May 2023

remote_mode=false # Default to normal (non-remote) mode. False means it will execute checkLoad.sh on the defined remote_ip
checkLoad_interval_seconds=10
# system_label="Localhost"
  system_label="Localhost"
  primary_ip="127.0.0.1"
  remote_ip=""
  remote_dir=""
  counter_file="$(pwd)/.migration_counter"
  fallback_hourly_limit=500

# Set defaults
  mysql_check=1
  taskd_check=1
  tq_sched_check=1
  tq_unsched_check=1
  tq_retry_check=1
  system_load_check=1
  diskfull_dicom_check=1
  diskfull_cache_check=1
  diskfull_proc_check=1
  mysql_limit_str=OK
  taskd_limit_str=OK
  tq_sched_limit_int=1500
  tq_unsched_limit_int=50
  tq_retry_limit_int=5000
  system_load_limit_int=10
  diskfull_dicom_limit_str="WARN2|WARN3|FULL|CANNOTMOVE"
  diskfull_cache_limit_str="WARN2|WARN3|FULL"
  diskfull_proc_limit_str="WARN2|WARN3|FULL|CANNOTMOVE"

Source_CheckLoad_cfg() {
  # Source config file if present
  if [ -f "$(pwd)"/checkLoad.cfg ]; then
    . "$(pwd)"/checkLoad.cfg
  fi
}
_log_prefix() {
    printf '%s [CheckLoad] ' "$(date '+%F %T')"
}
DetermineLocalhostMedsrvVer() {
  # Determine localhost medsrv version
  # localhost_Medsrv_Ver="$1"
  # If the value of localhost_Medsrv_Ver is not a valid version (6, 7, or 8), or is not set/empty, then attempt to determine it.
  if [ -z "$localhost_Medsrv_Ver" ] || [ "$localhost_Medsrv_Ver" -ne 6 ] || [ "$localhost_Medsrv_Ver" -ne 7 ] || [ "$localhost_Medsrv_Ver" -ne 8 ]; then
    if [ "$(sql.sh "show tables from imagemedical" -N | grep TaskQueue)" = "TaskQueue" ]; then
      localhost_Medsrv_Ver=8
    elif [ -d ${VAR}/taskqueue/.scheduled ]; then
      localhost_Medsrv_Ver=7
    else
      localhost_Medsrv_Ver=6
    fi
  fi
}
calcSleepTime() {
	#######################################
	# DESCRIPTION: Calculates an appropriate sleep time based on the load value provided
	# GLOBAL VARIABLES: <none>
	# ARGUMENTS:
	#   $1 = load value
	# OUTPUTS:
	#   Number of seconds to sleep
	# RETURNS:
	#   <none>
	# EXAMPLE USAGE: calcSleeptime 688
	# CALLED BY: checkLoad_getParam_curValue
	# CALLS: <none>
	#######################################
	local _num_defc15e="$1"
	if [ "$_num_defc15e" -ge 80000 ]; then
		echo 3000
	elif [ "$_num_defc15e" -ge 40000 ]; then
		echo 1200
	elif [ "$_num_defc15e" -ge 20000 ]; then
		echo 600
	elif [ "$_num_defc15e" -ge 10000 ]; then
		echo 300
	elif [ "$_num_defc15e" -ge 5000 ]; then
		echo 120
	elif [ "$_num_defc15e" -ge 2500 ]; then
		echo 60
	elif [ "$_num_defc15e" -ge 1000 ]; then
		echo 30
	elif [ "$_num_defc15e" -ge 500 ]; then
		echo 15
	elif [ "$_num_defc15e" -ge 250 ]; then
		echo 10
	elif [ "$_num_defc15e" -ge 125 ]; then
		echo 8
	else
		echo 5
	fi
}
create_checkLoad_timestamp_file() {
  echo "checkLoad_LastChecked=$(date +%s)" > .checkLoad.tmp
}
LoadNeedsToBeChecked() {
  local checkLoad_LastChecked
  local current_epoch_seconds
  local difference

  if [ ! -f "$(pwd)"/.checkLoad.tmp ]; then
    # echo "Load needs to be checked."
    return 0
  else
    # Retrieve the value of checkLoad_LastChecked from .checkLoad.tmp file
    . "$(pwd)"/.checkLoad.tmp
  fi


  current_epoch_seconds=$(date +%s)
  difference=$((current_epoch_seconds - checkLoad_LastChecked))

  if [ "$difference" -gt "$checkLoad_interval_seconds" ]; then
    # echo "Load needs to be checked. Difference is greater than interval."
    return 0
  else
    # echo "No need to check load. Difference is within the interval."
    return 1
  fi
}
checkLoad_local() {
  _is_idle=1
  while [ "$_is_idle" -eq 1 ]; do
    for _check_id in mysql_check taskd_check tq_sched_check tq_unsched_check tq_retry_check system_load_check diskfull_dicom_check diskfull_cache_check diskfull_proc_check; do
      # Identify the check's limit string/integer.
      # Determine the check's current value. Compare them.
      case "$_check_id" in
        mysql_check)
          if [ $mysql_check -eq 0 ]; then
            continue
          fi
          _mysql_current=$(/home/medsrv/component/mysql/ctrl status)
          while [ "$_mysql_current" != "$mysql_limit_str" ]; do
            _mysql_service_loaded="true"
            _sleep_time=300 # 5 minutes
            _sleep_affix=", SLEEP : ${_sleep_time}"
            # printf "Localhost (127.0.0.1), PARAMETER: mysql, CURRENT: %s%s\n" "$_mysql_current" "$_sleep_affix"
            _log_prefix
            printf "%s (%s), PARAMETER: mysql, CURRENT: %s%s\n" "$system_label" "$primary_ip" "$_mysql_current" "$_sleep_affix"
            # printf "%i %s\n" "$_sleep_time" "$_check_id" >> metrics.log
            sleep "$_sleep_time"
            _mysql_current=$(/home/medsrv/component/mysql/ctrl status)
          done
          if [ "$_mysql_service_loaded" = "true" ]; then
            _mysql_service_loaded="false"
            # printf "Localhost (127.0.0.1), PARAMETER: mysql, CURRENT: %s [Recovered!]\n" "$_mysql_current"
            _log_prefix
            printf "%s (%s), PARAMETER: mysql, CURRENT: %s [Recovered!]\n" "$system_label" "$primary_ip" "$_mysql_current"
          else
            # printf "Localhost (127.0.0.1), PARAMETER: mysql, CURRENT: %s\n" "$_mysql_current"
            _log_prefix
            printf "%s (%s), PARAMETER: mysql, CURRENT: %s\n" "$system_label" "$primary_ip" "$_mysql_current"
          fi
          ;;
        taskd_check)
          if [ $taskd_check -eq 0 ]; then
            continue
          fi
          _taskd_current=$(/home/medsrv/component/taskd/ctrl status)
          while [ "$_taskd_current" != "$taskd_limit_str" ]; do
            _taskd_service_loaded="true"
            _sleep_time=300 # 5 minutes
            _sleep_affix=", SLEEP : ${_sleep_time}"
            # printf "Localhost (127.0.0.1), PARAMETER: taskd, CURRENT: %s%s\n" "$_taskd_current" "$_sleep_affix"
            _log_prefix
            printf "%s (%s), PARAMETER: taskd, CURRENT: %s%s\n" "$system_label" "$primary_ip" "$_taskd_current" "$_sleep_affix"
            # printf "%i %s\n" "$_sleep_time" "$_check_id" >> metrics.log
            sleep "$_sleep_time"
            _taskd_current=$(/home/medsrv/component/taskd/ctrl status)
          done
          if [ "$_taskd_service_loaded" = "true" ]; then
            _taskd_service_loaded="false"
            # printf "Localhost (127.0.0.1), PARAMETER: taskd, CURRENT: %s [Recovered!]\n" "$_taskd_current"
            _log_prefix
            printf "%s (%s), PARAMETER: taskd, CURRENT: %s [Recovered!]\n" "$system_label" "$primary_ip" "$_taskd_current"
          else
            # printf "Localhost (127.0.0.1), PARAMETER: taskd, CURRENT: %s\n" "$_taskd_current"
            _log_prefix
            printf "%s (%s), PARAMETER: taskd, CURRENT: %s\n" "$system_label" "$primary_ip" "$_taskd_current"
          fi
          ;;
        tq_sched_check)
          if [ $tq_sched_check -eq 0 ]; then
            continue
          fi
          # Converting if statement below to case statement
          case "$localhost_Medsrv_Ver" in
            8*)
              # _tq_sched_current=$(sql.sh "select count(*) from TaskQueue where TQQUEUE='scheduled'" -N) ;;
              _tq_sched_current=$(sql.sh "$tq_sched_v8_qry" -N) ;;
            7*)
              _tq_sched_current=$(find ${VAR}/taskqueue/.scheduled/ -type f | wc -l)
              # Excludes scheduled tasks for other devices
              # _tq_sched_current_specific_device=$(grep -R -s -- '-H "DR_LOS_PB123"' ~/var/taskqueue/.scheduled | wc -l)
              # _tq_sched_current=$_tq_sched_current_specific_device
              ;;
            6*)
              _tq_sched_current=$(find ${VAR}/cpuqueue/.scheduled/ -mindepth 1 -maxdepth 1 -type f | wc -l)
              _tq_sched_current2=$(find ${VAR}/netqueue/.scheduled/ -mindepth 1 -maxdepth 1 -type f | wc -l)
              _tq_sched_current=$((_tq_sched_current + _tq_sched_current2))
              ;;
            *)
              _tq_sched_current=$(999999) ;;
          esac
          while [ "$_tq_sched_current" -gt "$tq_sched_limit_int" ]; do
            _tq_sched_service_loaded="true"
            _sleep_time=$(calcSleepTime "$_tq_sched_current")
            _sleep_affix=", SLEEP : ${_sleep_time}"
            # printf "Localhost (127.0.0.1), PARAMETER: tq_sched, CURRENT: %s%s\n" "$_tq_sched_current" "$_sleep_affix"
            _log_prefix
            printf "%s (%s), PARAMETER: tq_sched, CURRENT: %s%s\n" "$system_label" "$primary_ip" "$_tq_sched_current" "$_sleep_affix"
            # printf "%i %s\n" "$_sleep_time" "$_check_id" >> metrics.log
            sleep "$_sleep_time"
            case "$localhost_Medsrv_Ver" in
              8*)
                # _tq_sched_current=$(sql.sh "select count(*) from TaskQueue where TQQUEUE='scheduled'" -N) ;;
                _tq_sched_current=$(sql.sh "$tq_sched_v8_qry" -N) ;;
              7*)
                _tq_sched_current=$(find ${VAR}/taskqueue/.scheduled/ -type f | wc -l)
                # Excludes scheduled tasks for other devices
                # _tq_sched_current_specific_device=$(grep -R -s -- '-H "DR_LOS_PB123"' ~/var/taskqueue/.scheduled | wc -l)
                # _tq_sched_current=$_tq_sched_current_specific_device
                ;;
              6*)
                _tq_sched_current=$(find ${VAR}/cpuqueue/.scheduled/ -type f | wc -l)
                _tq_sched_current2=$(find ${VAR}/netqueue/.scheduled/ -type f | wc -l)
                _tq_sched_current=$((_tq_sched_current + _tq_sched_current2))
                ;;
              *)
                _tq_sched_current=$(999999) ;;
            esac
            Source_CheckLoad_cfg
          done
          if [ "$_tq_sched_service_loaded" = "true" ]; then
            _tq_sched_service_loaded="false"
            # printf "Localhost (127.0.0.1), PARAMETER: tq_sched, CURRENT: %s [Recovered!]\n" "$_tq_sched_current"
            _log_prefix
            printf "%s (%s), PARAMETER: tq_sched, CURRENT: %s [Recovered!]\n" "$system_label" "$primary_ip" "$_tq_sched_current"
          else
            # printf "Localhost (127.0.0.1), PARAMETER: tq_sched, CURRENT: %s\n" "$_tq_sched_current"
            _log_prefix
            printf "%s (%s), PARAMETER: tq_sched, CURRENT: %s\n" "$system_label" "$primary_ip" "$_tq_sched_current"
          fi
          ;;
        tq_unsched_check)
          if [ $tq_unsched_check -eq 0 ]; then
            continue
          fi
          case "$localhost_Medsrv_Ver" in
            8*)
              # _tq_unsched_current=$(sql.sh "select count(*) from TaskQueue where TQQUEUE='unprocessed'" -N)
              _tq_unsched_current=$(sql.sh "$tq_unsch_v8_qry" -N)
              _tq_unsched_current2=$(find "$TASKD_GLOBALQUEUE"/ -mindepth 1 -maxdepth 1 -type f | wc -l)
              [ "$_tq_unsched_current2" -gt "$_tq_unsched_current" ] && _tq_unsched_current="$_tq_unsched_current2"
              ;;
            7*)
              _tq_unsched_current=$(find ${VAR}/taskqueue/ -mindepth 1 -maxdepth 1 -type f | wc -l) ;;
            6*)
              _tq_unsched_current=$(find ${VAR}/cpuqueue/ -mindepth 1 -maxdepth 1 -type f | wc -l)
              _tq_unsched_current2=$(find ${VAR}/netqueue/ -mindepth 1 -maxdepth 1 -type f | wc -l)
              _tq_unsched_current=$((_tq_unsched_current + _tq_unsched_current2))
              ;;
            *) _tq_unsched_current=$(999999) ;;
          esac
          while [ "$_tq_unsched_current" -gt "$tq_unsched_limit_int" ]; do
            _tq_unsched_service_loaded="true"
            _sleep_time=$(calcSleepTime "$_tq_unsched_current")
            _sleep_affix=", SLEEP : ${_sleep_time}"
            # printf "Localhost (127.0.0.1), PARAMETER: tq_unsched, CURRENT: %s%s\n" "$_tq_unsched_current" "$_sleep_affix"
            _log_prefix
            printf "%s (%s), PARAMETER: tq_unsched, CURRENT: %s%s\n" "$system_label" "$primary_ip" "$_tq_unsched_current" "$_sleep_affix"
            # printf "%i %s\n" "$_sleep_time" "$_check_id" >> metrics.log
            sleep "$_sleep_time"
            case "$localhost_Medsrv_Ver" in
              8*)
                # _tq_unsched_current=$(sql.sh "select count(*) from TaskQueue where TQQUEUE='unprocessed'" -N)
                _tq_unsched_current=$(sql.sh "$tq_unsch_v8_qry" -N)
                _tq_unsched_current2=$(find "$TASKD_GLOBALQUEUE"/ -mindepth 1 -maxdepth 1 -type f | wc -l)
                [ "$_tq_unsched_current2" -gt "$_tq_unsched_current" ] && _tq_unsched_current="$_tq_unsched_current2"
                ;;
              7*)
                _tq_unsched_current=$(find ${VAR}/taskqueue/ -mindepth 1 -maxdepth 1 -type f | wc -l) ;;
              6*)
                _tq_unsched_current=$(find ${VAR}/cpuqueue/ -mindepth 1 -maxdepth 1 -type f | wc -l)
                _tq_unsched_current2=$(find ${VAR}/netqueue/ -mindepth 1 -maxdepth 1 -type f | wc -l)
                _tq_unsched_current=$((_tq_unsched_current + _tq_unsched_current2))
                ;;
              *) _tq_unsched_current=$(999999) ;;
            esac
            Source_CheckLoad_cfg
          done
          if [ "$_tq_unsched_service_loaded" = "true" ]; then
            _tq_unsched_service_loaded="false"
            # printf "Localhost (127.0.0.1), PARAMETER: tq_unsched, CURRENT: %s [Recovered!]\n" "$_tq_unsched_current"
            _log_prefix
            printf "%s (%s), PARAMETER: tq_unsched, CURRENT: %s [Recovered!]\n" "$system_label" "$primary_ip" "$_tq_unsched_current"
          else
            # printf "Localhost (127.0.0.1), PARAMETER: tq_unsched, CURRENT: %s\n" "$_tq_unsched_current"
            _log_prefix
            printf "%s (%s), PARAMETER: tq_unsched, CURRENT: %s\n" "$system_label" "$primary_ip" "$_tq_unsched_current"
          fi
          ;;
        tq_retry_check)
          if [ $tq_retry_check -eq 0 ]; then
            continue
          fi
          case "$localhost_Medsrv_Ver" in
            8*)
              # _tq_retry_current=$(sql.sh "select count(*) from TaskQueue where TQQUEUE='retry'" -N) ;;
              _tq_retry_current=$(sql.sh "$tq_retry_v8_qry" -N) ;;
            7*)
              _tq_retry_current=$(find ${VAR}/taskqueue/.retry/ -type f | wc -l) ;;
            6*)
              _tq_retry_current=$(find ${VAR}/cpuqueue/.retry/ -mindepth 1 -maxdepth 1 -type f | wc -l)
              _tq_retry_current2=$(find ${VAR}/netqueue/.retry/ -mindepth 1 -maxdepth 1 -type f | wc -l)
              _tq_retry_current=$((_tq_retry_current + _tq_retry_current2))
              ;;
            *)
              _tq_retry_current=$(999999) ;;
          esac
          while [ "$_tq_retry_current" -gt "$tq_retry_limit_int" ]; do
            _tq_retry_service_loaded="true"
            _sleep_time=300 # 5 minutes
            _sleep_time=$(calcSleepTime "$_tq_retry_current")
            _sleep_affix=", SLEEP : ${_sleep_time}"
            # printf "Localhost (127.0.0.1), PARAMETER: tq_retry, CURRENT: %s%s\n" "$_tq_retry_current" "$_sleep_affix"
            _log_prefix
            printf "%s (%s), PARAMETER: tq_retry, CURRENT: %s%s\n" "$system_label" "$primary_ip" "$_tq_retry_current" "$_sleep_affix"
            # printf "%i %s\n" "$_sleep_time" "$_check_id" >> metrics.log
            sleep "$_sleep_time"
            case "$localhost_Medsrv_Ver" in
              8*)
                # _tq_retry_current=$(sql.sh "select count(*) from TaskQueue where TQQUEUE='retry'" -N)
                _tq_retry_current=$(sql.sh "$tq_retry_v8_qry" -N) ;;
              7*)
                _tq_retry_current=$(find ${VAR}/taskqueue/.retry/ -type f | wc -l) ;;
              6*)
                _tq_retry_current=$(find ${VAR}/cpuqueue/.retry/ -mindepth 1 -maxdepth 1 -type f | wc -l)
                _tq_retry_current2=$(find ${VAR}/netqueue/.retry/ -mindepth 1 -maxdepth 1 -type f | wc -l)
                _tq_retry_current=$((_tq_retry_current + _tq_retry_current2))
                ;;
              *)
                _tq_retry_current=$(999999) ;;
            esac
            Source_CheckLoad_cfg
          done
          if [ "$_tq_retry_service_loaded" = "true" ]; then
            _tq_retry_service_loaded="false"
            # printf "Localhost (127.0.0.1), PARAMETER: tq_retry, CURRENT: %s [Recovered!]\n" "$_tq_retry_current"
            _log_prefix
            printf "%s (%s), PARAMETER: tq_retry, CURRENT: %s [Recovered!]\n" "$system_label" "$primary_ip" "$_tq_retry_current"
          else
            # printf "Localhost (127.0.0.1), PARAMETER: tq_retry, CURRENT: %s\n" "$_tq_retry_current"
            _log_prefix
            printf "%s (%s), PARAMETER: tq_retry, CURRENT: %s\n" "$system_label" "$primary_ip" "$_tq_retry_current"
          fi
          ;;
        system_load_check)
          if [ $system_load_check -eq 0 ]; then
            continue
          fi
          _system_load_current=$(printf "%.0f" "$(awk '{print $1}' /proc/loadavg)")
          while [ "$_system_load_current" -gt "$system_load_limit_int" ]; do
            _system_load_service_loaded="true"
            _sleep_time=120 # 2 minutes
            _sleep_affix=", SLEEP : ${_sleep_time}"
            # printf "Localhost (127.0.0.1), PARAMETER: system_load, CURRENT: %s%s\n" "$_system_load_current" "$_sleep_affix"
            _log_prefix
            printf "%s (%s), PARAMETER: system_load, CURRENT: %s%s\n" "$system_label" "$primary_ip" "$_system_load_current" "$_sleep_affix"
            # printf "%i %s\n" "$_sleep_time" "$_check_id" >> metrics.log
            sleep "$_sleep_time"
            _system_load_current=$(printf "%.0f" "$(awk '{print $1}' /proc/loadavg)")
            Source_CheckLoad_cfg
          done
          if [ "$_system_load_service_loaded" = "true" ]; then
            _system_load_service_loaded="false"
            # printf "Localhost (127.0.0.1), PARAMETER: system_load, CURRENT: %s [Recovered!]\n" "$_system_load_current"
            _log_prefix
            printf "%s (%s), PARAMETER: system_load, CURRENT: %s [Recovered!]\n" "$system_label" "$primary_ip" "$_system_load_current"
          else
            # printf "Localhost (127.0.0.1), PARAMETER: system_load, CURRENT: %s\n" "$_system_load_current"
            _log_prefix
            printf "%s (%s), PARAMETER: system_load, CURRENT: %s\n" "$system_label" "$primary_ip" "$_system_load_current"
          fi
          ;;
        diskfull_dicom_check)
          if [ $diskfull_dicom_check -eq 0 ]; then
            continue
          fi
          _DcmWarnFlags="$(~/component/repositoryhandler/bin/getRepositoryStatus /home/medsrv/data/dicom.repository/)"
          if [ -n "$_DcmWarnFlags" ]; then
            _DcmWarnFlags="$(echo "$_DcmWarnFlags" | tr '\n' ' ')"
          fi
          while [ -n "$(echo "$_DcmWarnFlags" | grep -E "$diskfull_dicom_limit_str")" ]; do
            _dcm_service_loaded="true"
            _sleep_time=1800 # 30 minutes
            _sleep_affix=", SLEEP : ${_sleep_time}"
            # printf "Localhost (127.0.0.1), PARAMETER: diskfull_dicom, CURRENT: %s%s\n" "$_DcmWarnFlags" "$_sleep_affix"
            _log_prefix
            printf "%s (%s), PARAMETER: diskfull_dicom, CURRENT: %s%s\n" "$system_label" "$primary_ip" "$_DcmWarnFlags" "$_sleep_affix"
            # printf "%i %s\n" "$_sleep_time" "$_check_id" >> metrics.log
            sleep "$_sleep_time"
            _DcmWarnFlags="$(~/component/repositoryhandler/bin/getRepositoryStatus /home/medsrv/data/dicom.repository/)"
            if [ -n "$_DcmWarnFlags" ]; then
              _DcmWarnFlags="$(echo "$_DcmWarnFlags" | tr '\n' ' ')"
            fi
          done
          _DcmWarnFlags="<none>"
          if [ "$_dcm_service_loaded" = "true" ]; then
            # printf "Localhost (127.0.0.1), PARAMETER: diskfull_dicom, CURRENT: %s [Recovered!]\n" "$_DcmWarnFlags"
            _log_prefix
            printf "%s (%s), PARAMETER: diskfull_dicom, CURRENT: %s [Recovered!]\n" "$system_label" "$primary_ip" "$_DcmWarnFlags"
          else
            # printf "Localhost (127.0.0.1), PARAMETER: diskfull_dicom, CURRENT: %s\n" "$_DcmWarnFlags"
            _log_prefix
            printf "%s (%s), PARAMETER: diskfull_dicom, CURRENT: %s\n" "$system_label" "$primary_ip" "$_DcmWarnFlags"
          fi
          ;;
        diskfull_cache_check)
          if [ $diskfull_cache_check -eq 0 ]; then
            continue
          fi
          _CacheWarnFlags="$(~/component/repositoryhandler/bin/getRepositoryStatus ${VAR}/cache.repository/)"
          if [ -n "$_CacheWarnFlags" ]; then
            _CacheWarnFlags="$(echo "$_CacheWarnFlags" | tr '\n' ' ')"
          fi
          while [ -n "$(echo "$_CacheWarnFlags" | grep -E "$diskfull_cache_limit_str")" ]; do
            _cache_service_loaded="true"
            _sleep_time=1800 # 30 minutes
            _sleep_affix=", SLEEP : ${_sleep_time}"
            # printf "Localhost (127.0.0.1), PARAMETER: diskfull_cache, CURRENT: %s%s\n" "$_CacheWarnFlags" "$_sleep_affix"
            _log_prefix
            printf "%s (%s), PARAMETER: diskfull_cache, CURRENT: %s%s\n" "$system_label" "$primary_ip" "$_CacheWarnFlags" "$_sleep_affix"
            # printf "%i %s\n" "$_sleep_time" "$_check_id" >> metrics.log
            sleep "$_sleep_time"
            _CacheWarnFlags="$(~/component/repositoryhandler/bin/getRepositoryStatus ${VAR}/cache.repository/)"
            if [ -n "$_CacheWarnFlags" ]; then
              _CacheWarnFlags="$(echo "$_CacheWarnFlags" | tr '\n' ' ')"
            fi
          done
          _CacheWarnFlags="<none>"
          if [ "$_cache_service_loaded" = "true" ]; then
            # printf "Localhost (127.0.0.1), PARAMETER: diskfull_cache, CURRENT: %s [Recovered!]\n" "$_CacheWarnFlags"
            _log_prefix
            printf "%s (%s), PARAMETER: diskfull_cache, CURRENT: %s [Recovered!]\n" "$system_label" "$primary_ip" "$_CacheWarnFlags"
          else
            # printf "Localhost (127.0.0.1), PARAMETER: diskfull_cache, CURRENT: %s\n" "$_CacheWarnFlags"
            _log_prefix
            printf "%s (%s), PARAMETER: diskfull_cache, CURRENT: %s\n" "$system_label" "$primary_ip" "$_CacheWarnFlags"
          fi
          ;;
        diskfull_proc_check)
          if [ $diskfull_proc_check -eq 0 ]; then
            continue
          fi
          _ProcWarnFlags="$(~/component/repositoryhandler/bin/getRepositoryStatus ${VAR}/processed.repository/)"
          if [ -n "$_ProcWarnFlags" ] || [ "$_ProcWarnFlags" != "" ]; then
            _ProcWarnFlags="$(echo "$_ProcWarnFlags" | tr '\n' ' ')"
          fi
          while echo "$_ProcWarnFlags" | grep -qE "$diskfull_proc_limit_str"; do
            _proc_service_loaded="true"
            _sleep_time=1800 # 30 minutes
            _sleep_affix=", SLEEP : ${_sleep_time}"
            # printf "Localhost (127.0.0.1), PARAMETER: diskfull_proc, CURRENT: %s%s\n" "$_ProcWarnFlags" "$_sleep_affix"
            _log_prefix
            printf "%s (%s), PARAMETER: diskfull_proc, CURRENT: %s%s\n" "$system_label" "$primary_ip" "$_ProcWarnFlags" "$_sleep_affix"
            # printf "%i %s\n" "$_sleep_time" "$_check_id" >> metrics.log
            sleep "$_sleep_time"
            _ProcWarnFlags="$(~/component/repositoryhandler/bin/getRepositoryStatus ${VAR}/processed.repository/)"
            if [ -n "$_ProcWarnFlags" ] || [ "$_ProcWarnFlags" != "" ]; then
              _ProcWarnFlags="$(echo "$_ProcWarnFlags" | tr '\n' ' ')"
            fi
          done
          _ProcWarnFlags="<none>"
          if [ "$_proc_service_loaded" = "true" ]; then
            _proc_service_loaded="false"
            # printf "Localhost (127.0.0.1), PARAMETER: diskfull_proc, CURRENT: %s [Recovered!]\n" "$_ProcWarnFlags"
            _log_prefix
            printf "%s (%s), PARAMETER: diskfull_proc, CURRENT: %s [Recovered!]\n" "$system_label" "$primary_ip" "$_ProcWarnFlags"
          else
            # printf "Localhost (127.0.0.1), PARAMETER: diskfull_proc, CURRENT: %s\n" "$_ProcWarnFlags"
            _log_prefix
            printf "%s (%s), PARAMETER: diskfull_proc, CURRENT: %s\n" "$system_label" "$primary_ip" "$_ProcWarnFlags"
          fi
          ;;
      esac
    done
    # Display result & sleep if value exceeds the limit.
    # Loop until the check's value is below the limit.
    # Move on to the next check.
    _is_idle=0
  done
}
checkLoad_remote() {
  local do_arbitrary_rate_check=false

  for ip in $remote_ip; do
    # Pass the --remote option to inform the script that it's being invoked remotely
    if ! ssh -o ConnectTimeout=10 -n "$ip" "cd $remote_dir; ./checkLoad.sh --remote"; then
      do_arbitrary_rate_check=true
    fi
  done

  if [ "$do_arbitrary_rate_check" = true ]; then
    check_migration_rate
    status_code=$? # Capture the return status explicitly in a variable
    output_migration_status $status_code
  fi
}
check_migration_rate() {
    local current_hour=$(date "+%H")
    local count=0

    if [ -f "$counter_file" ]; then
        read -r count last_hour < "$counter_file"
        if [ "$last_hour" != "$current_hour" ]; then
            count=0 # Reset count if it's a new hour
        fi
    fi

    # Increment and update the counter
    count=$((count + 1))
    echo "$count $current_hour" > "$counter_file"

    if [ "$count" -ge $fallback_hourly_limit ]; then
        return 1 # Return code 1: Hourly limit reached
    else
        return 0 # Return code 0: Under the limit
    fi
}
output_migration_status() {
    local status_code=$1
    local count=$(cut -d ' ' -f 1 < "$counter_file") # Extract the current count

    if [ "$status_code" -eq 1 ]; then
        _log_prefix
        echo "Hourly migration limit of $fallback_hourly_limit studies reached. Pausing until the next hour."
        sleep $((3600 - $(date "+%s") % 3600)) # Wait until the next hour
    else
        _log_prefix
        echo "Remote check unavailable. Used fallback limit: $fallback_hourly_limit/hr. Current count: $count."
    fi
}
update_iteration_count() {
    local current_hour=$(date "+%H")
    local count=0
    local counter_file="$1"  # Assuming counter_file path is passed as an argument

    if [ -f "$counter_file" ]; then
        read -r count last_hour < "$counter_file"
        if [ "$last_hour" != "$current_hour" ]; then
            count=0 # Reset count if it's a new hour
        fi
    fi

    # Increment and update the counter
    count=$((count + 1))
    echo "$count $current_hour" > "$counter_file"
}

# Check for the '--remote' or '-r' option
while [ $# -gt 0 ]; do
  case "$1" in
    --remote|-r)
      remote_mode=true
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
  shift
done

if LoadNeedsToBeChecked; then
  Source_CheckLoad_cfg
  DetermineLocalhostMedsrvVer
  
  # Always perform local checks
  checkLoad_local

  # If running in normal mode (i.e., not remotely invoked)
  if [ "$remote_mode" = false ]; then
    if [ -n "$remote_ip" ]; then
      _log_prefix
      echo "Performing remote load checks for IP(s): $remote_ip"
      checkLoad_remote
    else
      _log_prefix
      echo "Remote IP not set. Triggering arbitrary rate check."
      # Trigger the arbitrary rate check since no remote load checks are available
      check_migration_rate
      status_code=$? # Capture the return status explicitly in a variable
      output_migration_status $status_code
    fi
  else
    _log_prefix
    echo "Remote mode enabled. Skipping remote and arbitrary rate checks."
  fi

  # Update the timestamp after checks
  create_checkLoad_timestamp_file
fi
