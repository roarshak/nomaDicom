#!/bin/bash

# Enable debugging mode: additional output + pause breaks
debugging=0
#High-verbosity debugging
[[ $debugging -eq 1 ]] && export PS4='\033[0;33m+($(basename ${BASH_SOURCE}):${LINENO}):\033[0m ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

function ENTER2CONTINUE() {
  if [[ "$debugging" -eq 1 ]]; then
    local message="$1"
    read -r -n 1 -p "[DEBUGGING ENABLED] $message -Press enter to continue..." </dev/tty
  fi
}

function round () {
  echo $(printf %.$2f $(echo "scale=$2;(((10^$2)*$1)+0.5)/(10^$2)" | bc))
}

[ -f $HOME/etc/setenv.sh ] && . $HOME/etc/setenv.sh
diskDate=$(ls -l $VAR/disk_info | awk '{print$6,$7,$8}')
# BASE UNIT of ~/var/disk_info: Kibibytes
# Divide the Kibibytes value from ~/var/disk_info by 1024,
#   - twice, to get Gibibytes value
# Mlutiply the kibibytes value from ~/var/disk_info by 1024,
#   - to get bytes
# NOTE: disk_info does NOT include classic archive mounts
dicom_bytes=$(cat $VAR/disk_info | awk '/DATA:/,EOF' | grep MYUSED | sed -e 's/MYUSED=//g' | awk '{SUM += $1} END {printf "%.0f", SUM*1024}')
ENTER2CONTINUE
#dicom_kibibytes=$(cat $VAR/disk_info | awk '/DATA:/,EOF' | grep MYUSED | sed -e 's/MYUSED=//g')
cache_bytes=$(cat $VAR/disk_info | sed -n '/^CACHE:/,/^PROCESSED:/p;/^PROCESSED:/q' | grep MYUSED | sed -e 's/MYUSED=//g' | awk '{SUM += $1} END {printf "%.0f", SUM*1024}')
ENTER2CONTINUE
#cache_kibibytes=$(cat $VAR/disk_info | sed -n '/^CACHE:/,/^PROCESSED:/p;/^PROCESSED:/q' | grep MYUSED | sed -e 's/MYUSED=//g')
processed_bytes=$(cat $VAR/disk_info | sed -n '/^PROCESSED:/,/^DATA:/p;/^DATA:/q' | grep MYUSED | sed -e 's/MYUSED=//g' | awk '{SUM += $1} END {printf "%.0f", SUM*1024}')
ENTER2CONTINUE
#processed_kibibytes=$(cat $VAR/disk_info | sed -n '/^PROCESSED:/,/^DATA:/p;/^DATA:/q' | grep MYUSED | sed -e 's/MYUSED=//g')
total_bytes=$(cat $VAR/disk_info | grep MYUSED | sed -e 's/MYUSED=//g' | awk '{SUM += $1} END {printf "%.0f", SUM*1024}')
ENTER2CONTINUE
#total_kibibytes=$(cat $VAR/disk_info | grep MYUSED | sed -e 's/MYUSED=//g' | awk '{SUM += $1} END {print SUM}')

# NOTE: SUMSIZE from Dcstudy EXCLUDES classic archive mounts
totalDB_bytes=$(sql.sh "select SUM(SUMSIZE) from Dcstudy" -N | sed -e 's/,//g')
ENTER2CONTINUE
ratioarith=$(echo "$dicom_bytes/$totalDB_bytes" | bc -l)
ENTER2CONTINUE
ratioecho=$(echo "$ratioarith*100" | bc -l | cut -c1-4)
ENTER2CONTINUE

#"StoreMode" systems will have little-to-no Cache & Processed, causing the output
#+to look like "Cache: 4.19617e-05". Can be improved by changing $cacheGB by not
#+arbitrarily calculating for GB. Instead, calculate Bytes, and then make new
#+variables that represent other units. Then use logic to determine which unit
#+will make the most sense for displaying.
#The values in $VAR/disk_info are Base2 Binary (Kibibytes)

#How People/Marketers see storage
#CONVERSIONS; BASE-10 (1,000, not 1,024)
# Bytes -> KiloBytes: Divide the amount of bytes by 1,000. The result will be expressed in KiloBytes.
# Bytes -> MegaBytes: Divide the amount of bytes by 1,000,000. The result will be expressed in MegaBytes.
# Bytes -> GigaBytes: Divide the amount of bytes by 1,000,000,000. The result will be expressed in GigaBytes.
# Bytes -> TeraBytes: Divide the amount of bytes by 1,000,000,000,000. The result will be expressed in TeraBytes.

#How Computers see storage
#CONVERSIONS; BASE-2 (1,024, not 1,000)
# Bytes -> KibiBytes: Divide the amount of bytes by 1024. The result will be expressed in KibiBytes.
# Bytes -> MebiBytes: Divide the amount of bytes by 1048576. The result will be expressed in MebiBytes.
# Bytes -> GibiBytes: Divide the amount of bytes by 1073741824. The result will be expressed in GibiBytes.
# Bytes -> TebiBytes: Divide the amount of bytes by 1099511627776. The result will be expressed in TebiBytes.


#Will arbitrarily use GB for now...
# multiplier_baseTwo=1073741824
# multiplier_baseTen=1000000000
divisor_baseTwo=1073741824
divisor_baseTen=1000000000
unit_baseTen="GB"
unit_baseTwo="GiB"

echo "$(date)"
echo
echo "### \$VAR/disk_info DATA ###"
echo "disk_info last updated: $diskDate"
#echo "-Disk usage physical (var/disk_info DATA): $dicom_bytes"
echo "Disk usage physical: $(echo $(round "$dicom_bytes / $divisor_baseTen" 2)) ${unit_baseTen} (Base2: $(echo $(round "$dicom_bytes / $divisor_baseTwo" 2)) ${unit_baseTwo})"
#echo "-Disk usage database (DB value from dcreg): $totalDB"
echo "Disk usage database: $(echo $(round "$totalDB_bytes / $divisor_baseTen" 2)) ${unit_baseTen} (Base2: $(echo $(round "$totalDB_bytes / $divisor_baseTwo" 2)) ${unit_baseTwo})"
echo "Ratio: $ratioecho% ($(echo $ratioarith | cut -c1-4))"
#echo "Cache: $cacheGB According to Linux [df -h; GiB Base2 Binary]"
#echo "       $cacheGB_base10_decimal According to everyone else [GB Base10 Decimal]"
echo
echo "### STORAGE UTILIZATION ###"
echo "Cache: $(echo $(round "$cache_bytes / $divisor_baseTen" 2)) ${unit_baseTen} (Base2: $(echo $(round "$cache_bytes / $divisor_baseTwo" 2)) ${unit_baseTwo})"
#echo "Proc:  $processedGB According to Linux [df -h; GiB Base2 Binary]"
#echo "       $processedGB_base10_decimal According to everyone else [GB Base10 Decimal]"
echo "Proc: $(echo $(round "$processed_bytes / $divisor_baseTen" 2)) ${unit_baseTen} (Base2: $(echo $(round "$processed_bytes / $divisor_baseTwo" 2)) ${unit_baseTwo})"
#echo "DCM:   $dataGB According to Linux [df -h; GiB Base2 Binary]"
#echo "       $dataGB_base10_decimal According to everyone else [GB Base10 Decimal]"
echo "DCM: $(echo $(round "$dicom_bytes / $divisor_baseTen" 2)) ${unit_baseTen} (Base2: $(echo $(round "$dicom_bytes / $divisor_baseTwo" 2)) ${unit_baseTwo})"
#echo "Total: $totalGB According to Linux [df -h; GiB Base2 Binary]"
#echo "       $totalGB_base10_decimal According to everyone else [GB Base10 Decimal]"
echo "Total: $(echo $(round "$total_bytes / $divisor_baseTen" 2)) ${unit_baseTen} (Base2: $(echo $(round "$total_bytes / $divisor_baseTwo" 2)) ${unit_baseTwo})"
echo
echo "### DCM DATA COMPOSITION ###"
#sql.sh "select MODALITY as Modality, format(SUM(SUMSIZE/1000000000*$ratioarith),3) TotalGB, format(SUM(SUMSIZE/1000000*$ratioarith),3) as TotalMB, count(*) Num, CAST(format(SUM(SUMSIZE/1000000*$ratioarith)/count(*),3) as DECIMAL(10,2)) AvgSizeMB from Dcstudy where NUMOFIMG >= 1 Group By MODALITY Order By AvgSizeMB DESC LIMIT 20" -t
sql.sh "select OMODALITY as Modality, format(SUM(SIZE/1000000000*$ratioarith),3) TotalGB, format(SUM(SIZE/1000000*$ratioarith),3) as TotalMB, count(*) Num, CAST(format(SUM(SIZE/1000000*$ratioarith)/count(*),3) as DECIMAL(10,2)) AvgSizeMB from Dcobject Group By OMODALITY Order By MODALITY DESC LIMIT 20" -t