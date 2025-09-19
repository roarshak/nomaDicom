#! /bin/bash

. ~/etc/setenv.sh
. $DICOM_VAR/pb-scp.cfg
. scripttools.new.shi

STUDY_LIST=$1
#TARGET=$2

cat $STUDY_LIST | while read suid
  do
    unset sdir
        if /home/medsrv/component/repositoryhandler/scripts/locateStudy.sh -d $suid
          then
            sdir=$(/home/medsrv/component/repositoryhandler/scripts/locateStudy.sh -d $suid)
          else
            continue
    fi
        cd $sdir
        echo "Sending study ${suid} at $(date)"
          ls | while read obj
            do
              #echo "Sending ${obj}...(dry-run)"
              echo "Sending obj with cmd: /home/medsrv/component/dicom/bin/storescu --debug --aetitle ERAD --call ERAD_MRG 104 ${obj}"
              /home/medsrv/component/dicom/bin/storescu \
                --verbose-pc \
                --required \
                --aetitle ERAD \
                --call ERAD_MIG 192.147.160.100 4321 \
                ${obj};
          done
echo;echo;echo;
. ./dynsleep.cfg
sleep $sleep_time
done;

