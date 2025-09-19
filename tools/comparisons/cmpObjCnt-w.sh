#!/bin/bash

input_file="$1"
[ -z $input_file ] && exit

while read -r suid; do
  if ./cmpObjCnt.sh -s $suid; then
    # Mismatched
    echo "$(date) $suid verify fail"
    sql.sh "UPDATE case_62098.LocalExams SET migrate='y'"
  else
    # Migrated
    echo "$(date) $suid verify pass"
    sql.sh "UPDATE case_62098.LocalExams SET migrate='y' AND verification='pass'"
  fi
done <$input_file
