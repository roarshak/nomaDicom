#!/bin/bash
#Install
# - put unit file to /etc/systemd/system/voyager-autostart.service
# - reload & restart systemd
[[ ! "$(whoami)" == "root" ]] && { echo "installVoyagerService.sh nust be ran as root, exiting"; exit ; }

. /home/medsrv/work/jbooth/.voyager/init/voyager-service.cfg

if [[ -e /etc/systemd/system/voyager.service ]]; then
  echo "Error: voyager service has already been installed. To re-install fresh, rm /etc/systemd/system/voyager.service, exiting"
  exit
fi

if -z "$JB_ACTIVE_MIG_CASE_NUMBERS" ]]; then
  echo
  echo "WARN: There are currently no migration (cases) configured for monitoring/auto-restarting."
  echo "      Add the case number to JB_ACTIVE_MIG_CASE_NUMBERS variable in /home/medsrv/work/jbooth/.voyager/init/voyager-service.cfg"
  echo
  read -p "Continue installing service and add case number later [y/n]? " resp
  if [[ "$resp" == "n" || "$resp" == "no" ]]; then
    exit
  fi
fi

echo -n "creating /etc/systemd/system/voyager.server..."
cat <<-EOF > /etc/systemd/system/voyager.service 
[Unit]
Description=DICOM Migration Service

[Service]
Type=simple
User=medsrv
Group=medsrv
WorkingDirectory="/home/medsrv/work/jbooth/.voyager/init"
ExecStart="/home/medsrv/work/jbooth/.voyager/init/migration-monitor.sh"

[Install]
WantedBy=multi-user.target
EOF
echo "done"


#Reload the systemd daemon to pickup changes
echo "Reloading systemd with 'systemctl daemon-reload'"
systemctl daemon-reload

#Start your service
echo "Starting service with 'systemctl start voyager.service"
systemctl start voyager.service

#Check the status of your service
echo "Checking status with 'systemctl status voyager.service"
systemctl status voyager.service

#Enable your service to start on boot
echo "Enabling service with 'systemctl enable voyager.service"
systemctl enable voyager.service


