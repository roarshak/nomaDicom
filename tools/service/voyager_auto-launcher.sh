#/bin/bash
#Put this line in crontab
#* * * * * /home/medsrv/work/jbooth/launch-migration-testing.sh >>/home/medsrv/work/jbooth/cron-testing.log 2>&1
if ! screen -list | grep -q "jwb.auto-launch-testing"; then
  screen -dmS jwb.auto-launch-testing bash -c "/home/medsrv/work/jbooth/script-emulating-migration.sh"
fi
