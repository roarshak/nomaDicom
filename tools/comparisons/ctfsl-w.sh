#!/bin/bash

input_file="$1"
[ -z $input_file ] && exit

while read -r suid; do
  repo_loc=$(~/component/repositoryhandler/scripts/locateStudy.sh -d $suid)
  expo_loc=$(sql.sh "SELECT export_location FROM exportExams.LocalExams WHERE styiuid='$suid' AND export_location IS NOT NULL" -N)
  if [ -n "$repo_loc" ] && [ -n "$expo_loc" ]; then
    ./ctfsl.sh --script --study "$suid" --loc1 "$repo_loc" --loc2 "$expo_loc"
  else
    if [ -z "$repo_loc" ]; then
      # repo loc is empty
      echo "$suid sty_repo_loc is empty, skipping" | tee -a ctfsl.log
    fi
    if [ -z "$expo_loc" ]; then
      # expo loc is empty
      echo "$suid export_loc is empty, skipping" | tee -a ctfsl.log
    fi
  fi
done <$input_file
