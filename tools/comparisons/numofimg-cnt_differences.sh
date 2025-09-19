#!/bin/bash
# This script is to demonstrate:
# - img & obj counts from the database
# - juxtaposed against cfind results from same system

# NOTABLE EXAMPLES
# FNAME[SC]+CONVTYPE[SD] objects NOT included in NumOfImg count: 1.2.826.0.1.3680043.2.93.2.2831161374.15648.1592505813.1


. /home/medsrv/var/dicom/pb-scp.cfg
. /home/medsrv/var/conf/setenv.sh
. /home/medsrv/var/conf/self.rec

if [[ "$NoObjectTable" == "yes" ]] && [[ "$ProcessMode" == "Database" ]]; then
  echo "This script does not work without an Object table, exiting."
  echo "grep \"NoObjectTable\" /home/medsrv/var/conf/self.rec"
  grep "NoObjectTable" /home/medsrv/var/conf/self.rec
  exit
fi

# _SUID="$(sql.sh "SELECT STYIUID FROM Dcstudy WHERE (NUMOFIMG!=NUMOFOBJ) AND NUMOFIMG>'1' AND MAINST>='0' AND DERIVED NOT IN('copy','shortcut') AND Dcstudy_d!='yes' ORDER BY RAND() LIMIT 1" -N)"
_SUID="$(sql.sh "SELECT d.STYIUID
FROM Dcstudy d JOIN 
(
  SELECT STYIUID, COUNT(*) AS NUMOFPBR
  FROM imagemedical.Dcobject
  WHERE FNAME LIKE 'Pb%'
  GROUP BY STYIUID
) AS o
ON d.STYIUID=o.STYIUID
WHERE
  o.NUMOFPBR!='0' AND
  (d.NUMOFIMG!=d.NUMOFOBJ) AND
  d.NUMOFIMG>'1' AND
  d.MAINST>='0' AND
  d.DERIVED NOT IN('copy','shortcut') AND
  d.Dcstudy_d!='yes'
ORDER BY RAND()
LIMIT 1" -N)"
if [[ -z "$_SUID" ]]; then
  echo "Could not find suitable SUID, exiting."
  exit
fi
_Dcstudy_NumOfImg="$(sql.sh "SELECT numofimg FROM Dcstudy WHERE STYIUID='$_SUID'" -N)"
_Dcstudy_NumOfObj="$(sql.sh "SELECT numofobj FROM Dcstudy WHERE STYIUID='$_SUID'" -N)"
_NumOfPBObjects="$(sql.sh "SELECT COUNT(*) FROM Dcobject WHERE STYIUID='$_SUID' AND FNAME LIKE 'Pb%'" -N)"
_NumOfSRobjects="$(sql.sh "SELECT COUNT(*) FROM Dcobject WHERE STYIUID='$_SUID' AND FNAME LIKE 'SR%'" -N)"
# FNAME[SC] + CONVTYPE[WSD] = not included in IMG count
# FNAME[SC] + CONVTYPE[!WSD] = IS included in IMG count # CONVTYPEs; WSD,SI,SD,
_NumOfSCobjects_WSD="$(sql.sh "SELECT COUNT(*) FROM Dcobject WHERE STYIUID='$_SUID' AND FNAME LIKE 'SC%' AND CONVTYPE='WSD'" -N)"
_NumOfSCobjects_SD="$(sql.sh "SELECT COUNT(*) FROM Dcobject WHERE STYIUID='$_SUID' AND FNAME LIKE 'SC%' AND CONVTYPE='SD'" -N)"
_NumOfSCobjects_SI="$(sql.sh "SELECT COUNT(*) FROM Dcobject WHERE STYIUID='$_SUID' AND FNAME LIKE 'SC%' AND CONVTYPE='SI'" -N)"
_NumOfPDFobjects="$(sql.sh "SELECT COUNT(*) FROM Dcobject WHERE STYIUID='$_SUID' AND FNAME LIKE 'PDF%'" -N)"
_NumOfObj_MinusPB=$((_Dcstudy_NumOfObj - _NumOfPBObjects))
# sql.sh "SELECT STYIUID, NUMOFIMG, NUMOFOBJ, '$_NumOfPBObjects' AS NUMOFPB_, '$_NumOfSCobjects_WSD' AS NUMOFSC_WSD, '$_NumOfSCobjects_SD' AS NUMOFSC_SD, '$_NumOfSCobjects_SI' AS NUMOFSC_SI, '$_NumOfSRobjects' AS NUMOFSRT, '$_NumOfPDFobjects' AS NUMOFPDF FROM Dcstudy WHERE STYIUID='$_SUID'" -t
echo ""
echo "SUID: $_SUID"
sql.sh "SELECT NUMOFIMG, NUMOFOBJ, '$_NumOfPBObjects' AS NUMOFPB_, '$_NumOfSCobjects_WSD' AS NUMOFSC_WSD, '$_NumOfSCobjects_SD' AS NUMOFSC_SD, '$_NumOfSCobjects_SI' AS NUMOFSC_SI, '$_NumOfSRobjects' AS NUMOFSRT, '$_NumOfPDFobjects' AS NUMOFPDF FROM Dcstudy WHERE STYIUID='$_SUID'" -t
echo ""
echo "Below is an example of how eRAD PACS would respond to a cfind that is querying for number of instances:"
/home/medsrv/component/dicom/bin/findscu -S \
  --aetitle "$AE_TITLE" \
  --key 0008,0052=STUDY \
  --key 0020,000D="$_SUID" \
  --key 0020,1208 \
  --call $AE_TITLE $SERVERIP 104 | tail -n +3

Output_OutboundValidation() {
  # When validating from EP to Third-party archive.
  echo ""
  # echo "These counting strategies are in play even when going in the other direction; from EP out to a non-EP system."
  echo "VALIDATING FROM ERAD PACS TO THIRD PARTY ARCHIVE"
  echo "Study list extracts we produce for other vendors will, from their perspective, be almost entirely inaccurate"
  echo "unless we take this counting behavior into account."
  echo ""
  echo -e "EXAMPLE:\tThis study has [$_Dcstudy_NumOfObj] object(s) according to the eRAD PACS database."
  echo -e "\t\tIf we use NUMOFIMG[$_Dcstudy_NumOfImg] in our Source of Truth study list, then they will be receiving more objects than we"
  echo -e "\t\thave asserted for nearly every study."
  echo -e "\t\tIf we use NUMOFOBJ[$_Dcstudy_NumOfObj] in our Source of Truth study list, then they will be receiving fewer objects than we"
  echo -e "\t\thave asserted for nearly every study."
  echo -e "\t\tAdditionally, when they innevitably query our PACS for the number of instances, they will be given a number"
  echo -e "\t\tthat does not match the number we gave them."
  echo -e "\t\tObviously this creates a problem for both sides. They cannot be reasonably expected to do a validation while"
  echo -e "\t\tthis misrepresented data is in play."
  echo ""
  echo -e "\t\tWhen InteleRad is retrieving exams from us, this behavior adds another problem."
  echo -e "\t\tBefore they retrieve a study, the query the pacs (eRAD PACS) for the number of study related instances."
  echo -e "\t\tErad PACS will reply with the NUMOFOBJ value. In and of itself this is a good thing because it includes files,"
  echo -e "\t\tlike secondary captures or even reports, that are not included in IMAGE counts."
  echo -e "\t\tHowever, that NUMOFOBJ value returned as the number of study related instances will always be higher than"
  echo -e "\t\twhat other PACS systems are able to retrieve and store because of PB objects being included in the count."
  echo ""
}
Output_InboundValidation() {
  # When validating from Third-party archive to EP
  if [[ ${_NumOfPBObjects:-0} -ge 1 ]] || [[ ${_NumOfSCobjects_WSD:-0} -ge 1 ]]; then
    echo ""
    echo "VALIDATING FROM THIRD PARTY ARCHIVE TO ERAD PACS"
    echo "When validating from a third part archive to eRAD PACS (e.g. Retrieving from InteleRad archive for Precision)"
    echo "one would typically compare a study listing between the two systems to identify which ones from the archive"
    echo "would need to be retrieved because we either do not have it or do not have all of it."
    echo "Third-party archives generally do not accept our proprietary Practice Builder objects so when the exam is"
    echo "forwarded to the archive, it will have the study objects minus the PB objects."
    echo ""
    echo -e "EXAMPLE:\tThis study has [$_Dcstudy_NumOfObj] object(s) according to the eRAD PACS database."
    echo -e "\t\tThe third-party archive will receive and store only [$_NumOfObj_MinusPB] objects though, because it won't accept the PB files."
    echo -e "\t\tTheir study list for this exam will show [$_NumOfObj_MinusPB] objects."
    echo -e "\t\tWhen we compare this study against our own database, it will show [$_Dcstudy_NumOfObj] objects and [$_Dcstudy_NumOfImg] images."
    echo -e "\t\tTherefore, if we compare values directly, it will appear as if we are missing objects when using the NUMOFIMG"
    echo -e "\t\tvalue from the EP Database, and it will appear as if they are always missing 1 or 2 objects when using the NUMOFOBJ value."
    echo -e "\t\tIf instead you choose to work with an adjusted (calculated) value for the numofobj, then 90% of the \"mismatches\" go away"
  fi
}
Freds_Summary() {
  echo ""
  echo "Demonstration"
  echo "===================================================================="
  echo "From the other vendor's perspective, the study lists we produce will be"
  echo "almost completely inaccurate unless we account for our counting behavior."
  echo ""
  echo "EXAMPLE:"
  echo -e "\tThis study has [$_NumOfObj_MinusPB] (excluding PB files) objects according to the eRAD PACS database."
  # echo -e "\tUsing NUMOFIMG[$_Dcstudy_NumOfImg], recipients would receive more objects than stated for nearly every study."
  echo -e "\t$(my_func "NUMOFIMG" "$_Dcstudy_NumOfImg" "$(more_or_less "$_Dcstudy_NumOfImg" "$_NumOfObj_MinusPB")")"

  # echo -e "\tUsing NUMOFOBJ[$_Dcstudy_NumOfObj], recipients would receive fewer objects than stated."
  echo -e "\t$(my_func "NUMOFOBJ" "$_Dcstudy_NumOfObj" "$(more_or_less "$_Dcstudy_NumOfObj" "$_NumOfObj_MinusPB")")"

  echo -e "\tDiscrepancies during PACS queries will likely cause validation issues on both ends."
}
my_func() {
  _col=$1
  _val=$2
  _relative_qty_descriptor="$3"
  echo "When comparing against ${_col}[${_val}], recipients would receive $_relative_qty_descriptor objects ($_NumOfObj_MinusPB) than stated ($_val)."
}
more_or_less() {
  local _DB_value
  local _ADJ_value
  _DB_value=$1
  _ADJ_value=$2
  # if (( _DB_value > _ADJ_value )); then
  if [[ _DB_value -lt _ADJ_value ]]; then
    echo "more"
  else
    echo "fewer"
  fi
}
Footer() {
  echo "/\________________________________________________________________________________________________________________/\\"
}

# Output_OutboundValidation
# Output_InboundValidation
Freds_Summary
Footer