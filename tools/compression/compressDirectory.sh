#!/bin/sh
#
# Description:
#  Recursivcely compresses starting at the specified directory
#
# Usage:
#   compressDirectory.sh <full path to directory> [ nice ]
#
# If a file called "benice" exists in the same directory as this script, it will
# cause this script to run in a load aware way.

#When shopt -po xtrace returns 0 (success) it means set -x is enabled
if shopt -po xtrace >/dev/null ; then
  set +x
  . $HOME/etc/setenv.sh
  set -x
else
  . $HOME/etc/setenv.sh
fi

styRegex=([0-9]+\.[0-9]+\.[0-9]+\.?)
CompressionMode="None"
MinLossyRatio="Unconfigured"
MinLosslessRatio="Unconfigured"
[ -f "$ARCHIVE_VAR/archive.cfg" ] && . $ARCHIVE_VAR/archive.cfg


if [ -z "$1" ]; then
    echo;echo;echo
    echo "$0 <repository_dir> [ nice ]"
    echo
    echo "If the optional "nice" parameter is given, only compress when the"
    echo "server is not busy processing medsrv tasks"
    echo;echo;echo
    exit 1
fi

myrepository_dir="$1"

niceflag="$(dirname $0)/benice"
if [ -n "$2" -o -e "$niceflag" ]; then
    if [ -e ~/component/tools/scripttools.shi ]; then
        benice="yes"
    else
        echo
        echo "ERROR: The nice option requires ~/component/tools/scripttools.shi,"
        echo "which does not appear to exist on this server."
        echo
        exit 0
    fi
fi


if [ -n "$benice" ]; then
    . ~/component/tools/scripttools.shi
else
  #When shopt -po xtrace returns 0 (success) it means set -x is enabled
  if shopt -po xtrace >/dev/null; then
    set +x
    . $HOME/etc/setenv.sh
    set -x
  else
    . $HOME/etc/setenv.sh
  fi
fi


isFolder()
{
    currentDirectory=`pwd`
    cd "$1" 2>/dev/null
    [ $? != 0 ] && return 1
    cd - >/dev/null
    return 0
}

compressDir_()
{
    if [ -f $1 ] ; then
        if [ -n "$benice" ]; then
            niceme && break
        fi
        #$HOME/component/utils/bin/compressObject.sh -v -i $1 -t "..$tabulation" 
        #${startDir}/tools/compressObject.sh -v -i $1 -t "..$tabulation"
        ${startDir}/compressObject.sh -v -i $1 -t "..$tabulation"
        #${startDir}/tools/compressObject.sh -i $1 -t "..$tabulation"
        ret=$?
        objSize=$(du -b $1 | awk '{print $1}')
        #if [[ $MIGTYPE -eq 1 || $MIGTYPE -eq 15 || $MIGTYPE -eq 3 ]]; then
          echo "update Dcobject set SIZE = '$objSize' where STYIUID = '$styiuid' AND FNAME = '$i'" | /home/medsrv/component/mysql/bin/mysql -N imagemedical
        #fi
        return $ret
    fi
    #if [[ $MIGTYPE -eq 1 || $MIGTYPE -eq 15 || $MIGTYPE -eq 3 ]]; then
      if [[ "$styiuid" =~ $styRegex ]]; then
          echo "update Dcstudy s, (select SUM(SIZE) as newSum from Dcobject where STYIUID='$styiuid') as sum set s.SUMSIZE = sum.newSum where s.STYIUID='$styiuid'" | \
          /home/medsrv/component/mysql/bin/mysql -N imagemedical
      fi
    #fi
    isFolder $1
    [ $? != 0 ] && return 0
    cd "$1"
    echo "${tabulation}processing $1"
    styiuid="$1"
    tabulation="..$tabulation"
    for i in `ls 2>/dev/null` ; do
        if [ -n "$benice" ] ; then
            niceme 
            isstopped && break
        fi
	compressDir_ $i
    done
    tabulation="${tabulation:2}"
    cd ..
}

# Set this to whatever repository_dir you want to compress
RepositoryDir="$myrepository_dir"

startDir=$(pwd)
tabulation=".."

if [ ! -d "$RepositoryDir" ] ; then
    echo "The Repository Directory $RepositoryDir doesn't exist."
    exit 1
fi

echo "  Repository root = $RepositoryDir"

for p in CompressionMode MinLossyRatio MinLosslessRatio; do
    echo "$p = ${!p}"
done

echo "compressing $RepositoryDir"
compressDir_ "$RepositoryDir"

cd "$startDir"
echo "finished."
