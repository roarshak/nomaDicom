#!/bin/sh
# shellcheck disable=SC3043
# PURPOSE: A run control script that sleeps if outside of a time window.
# AUTHOR: Joel Booth
# DATE: May 2023

if [ "$(whoami)" != "medsrv" ]; then
	echo "Script must be run as user: medsrv, exiting"
	exit 1
fi

if [ -f ./checkLoad.cfg ]; then
	. ./checkLoad.cfg
else
	_OVERRIDE_RUNTIME_HOURS="true"
	runtime_hours="18 19 20 21 22 23 00 01 02 03 04 05"
  checkTime_sleep_interval=1800
fi

# Convert seconds to minutes
checkTime_sleep_interval_minutes=$((checkTime_sleep_interval / 60))

OutsideRuntimeWindow() {
  # Called like: while OutsideRuntimeWindow; do sleep 1; done
  # 0 = outside of runtime window
  # 1 = within runtime window
	local h
	local hour=$(date "+%H")
	for h  in $runtime_hours; do
    if [ "$hour" == "$h" ]; then
      # printf "\n"
      return 1
    fi
	done
	return 0
}

while OutsideRuntimeWindow; do
  if [ -f ./checkLoad.cfg ]; then . ./checkLoad.cfg; fi
  if [ "$_OVERRIDE_RUNTIME_HOURS" = "false" ]; then
    printf "Not within runtime hours. Sleeping for %i minutes.\n" "$checkTime_sleep_interval_minutes"
    sleep "$checkTime_sleep_interval"
  else
    break
  fi
done
