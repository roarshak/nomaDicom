#!/bin/bash

# Accept movescu options from the command line
movescu_opts=("$@")

# Log start of the movescu command using Message()
# Message "INFO" "Starting movescu with options: ${movescu_opts[*]}"

# Run the movescu command
/home/medsrv/component/dicom/bin/movescu "${movescu_opts[@]}"
exit_code=$?

# Log success or failure using Message()
if [[ $exit_code -eq 0 ]]; then
  exit 0
else
  #shellcheck disable=SC2088
  Message --log-level "ERROR" --log-file "$_LOG_MIGRATION_ERROR" "~/component/dicom/bin/movescu ${movescu_opts[*]}"
  exit 1
fi
