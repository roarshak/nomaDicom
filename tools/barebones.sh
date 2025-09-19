#!/bin/bash
# Barebones dicom transfer script

# move a study (movescu)
  SUID="$1"
  AE_TITLE="PALO_MXR"
  TARGET="PALO_MXR"
  QRAE_TITLE="PALO_MXR"
  QRIP="192.168.7.69"
  QRPORT=104
  /home/medsrv/component/dicom/bin/movescu -S --move "$TARGET" --aetitle "$AE_TITLE" --key 0008,0052=STUDY --key 0020,000d="$SUID" --call $QRAE_TITLE $QRIP $QRPORT

# move an object/instance (movescu)
  DCM_Filename="$1"
  SUID="$(sql.sh "select styiuid from Dcobject where fname='$DCM_Filename'" -N)"
  SERIUID="$(sql.sh "select seriuid from Dcobject where fname='$DCM_Filename'" -N)"
  SOPIUID="$(sql.sh "select sopiuid from Dcobject where fname='$DCM_Filename'" -N)"
  AE_TITLE="PALO_MXR" # PVH-Old-Child (Localhost)
  TARGET="PALO_MXR" # PVH-New-Child
  QRAE_TITLE="PALO_MXR" # PVH-Old-Child (Localhost)
  QRIP="192.168.7.69" # PVH-Old-Child (Localhost)
  QRPORT=104
  printf "%s movescu -S --aetitle %s --move %s --call %s --key 0008,0052=IMAGE --key 0020,000D=%s --key 0020,000E=%s --key 0008,0018=%s \n" "$(date "+%Y%m%d-%H%M%S")" "$AE_TITLE" "$TARGET" "$QRAE_TITLE $QRIP $QRPORT" "$SUID" "$SERIUID" "$SOPIUID"
  /home/medsrv/component/dicom/bin/movescu --verbose -S --aetitle "$AE_TITLE" --move "$TARGET" --call $QRAE_TITLE $QRIP $QRPORT -k "0008,0052=IMAGE" -k "0020,000D=$SUID" -k "0020,000E=$SERIUID" -k "0008,0018=$SOPIUID"

# get a study (getscu)
  SUID="$1"
  AE_TITLE="PALO_MXR" # PVH-Old-Child (Localhost)
  QRAE_TITLE="PALO_MXR" # PVH-Old-Child (Localhost)
  QRIP="192.168.7.69" # PVH-Old-Child (Localhost)
  QRPORT=104
  /home/medsrv/component/dicom/bin/getscu -S --key QueryRetrieveLevel=STUDY --key StudyInstanceUID="$SUID" -aet "$AE_TITLE" -aec "$QRAE_TITLE" $QRIP $QRPORT

# forward a study (runjavacmd)
  SUID="$1"
  TARGET="PALO_MXR" # PVH-New-Child
  crm_case_number="$2"
  /home/medsrv/component/taskd/runjavacmd -c "0 cases.Forward -s $SUID -H $TARGET -u $crm_case_number"
#
