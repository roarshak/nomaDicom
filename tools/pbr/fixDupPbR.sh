#! /bin/bash
#shellcheck disable=SC2068,SC2145,SC2155,SC2206,SC2124,SC2086,SC2004,SC2181,SC2048,SC2207,SC2034
styiuid=$1
debug=$2
pid=$$
backuploc="/home/medsrv/work/fixmultipbr.backup"
[ ! -d "$backuploc" ] && mkdir -p $backuploc
#1.2.276.0.26.1.1.1.2.2009.201.65463.130420

#[medsrv@erad fixDupPbR]$ printStudyInfo.sh -s 1.2.276.0.26.1.1.1.2.2009.201.65463.130420
#Study Directory:
#Cache Directory:
#Processed Directory:
#Archive Directory: /home/medsrv/var/archive/a5/201606/5/1.2.276.0.26.1.1.1.2.2009.201.65463.130420
#storestate.rec:
#    !!! storestate.rec file does not exist !!!
#Study table entries: 0; Object table entries: 0; Report table entries: 0
#Study Data:
#

## Study locations
function getStudyLocation() {
    # Paramters:
    #  locationtype - either dicom (for repository) or archive (for old style archive)
    #  styiuid - study instance uid of the study to find

    # Returns:
    #  the location of the study or nothing if the study does not exist at <locationtype>
    local locationtype=$1
    local styiuid=$2
    local res; unset res
    local archdir; unset archdir
    local hasarchive=$(ls /home/medsrv/var/mysql/imagemedical/Archive.* 2>/dev/null)

    if [ "$locationtype" == "dicom" ]; then
        res=$(~/component/repositoryhandler/scripts/locateStudy.sh -d $styiuid)
    elif [ "$locationtype" == "archive" -a -n "$hasarchive" ]; then
        archdir=$(sql.sh "select archdir from Archive where styiuid = '$styiuid';" -N)
        if [ -n "$archdir" ]; then
            res="/home/medsrv/var/archive/${archdir}/${styiuid}/"
        fi
    fi
    [ -n "$res" ] && echo $res
}

## List of PbRs oldest to newest
function listPbRs() {
    local location=$1
    local pbrs

    ls -1tr ${location}| grep PbR
}


## List of non-PbR objects
function listNonPbRs() {
    local location=$1

    ls -1tr ${location}/|grep -v PbR
}


## Convert: ~/component/utils/bin/convert --pbr-file <path to the PbR> <object file> <output file>
function applyPbR(){
    local styiuid=$1
    local loc=$2
    local PbR=$3
    local obj=$4

    [ ! -d ~/tmp/${styiuid}."${pid}" ] && { mkdir ~/tmp/${styiuid}.${pid} ; echo "~/tmp/${styiuid}.${pid}" ; }
    ~/component/utils/bin/convert --pbr-file "${loc}/${PbR}" "${loc}/${obj}" ~/tmp/${styiuid}.${pid}/${obj}
    if [ $? -ne 0 ]; then
        echo "Error applying PbR $PbR to ${styiuid}/${obj}"
        return 1
    else
        cp -va ~/tmp/${styiuid}.${pid}/${obj} ${loc}/
        return 0
    fi
}

## Get current status
function getCurrentPBStatus(){
    local loc=$1
    local mpbrlist=($2)
    local lastpbrindex=$[ ${#mpbrlist[@]} - 1 ]

    local STAT=$(~/component/dcmtk/bin/dcmdump +P f215,1002 ${loc}/${mpbrlist[$lastpbrindex]} |\
          awk '
              BEGIN {} ( $3 != "" ) {
                  stat = int( gensub("[][]","","g",$3) );
              } END {print stat}' )
    echo "$STAT"
}

## Get max status
function getMaxPBStatus(){
    #Parameters:
    # Study location (full path)
    # List of PbRs

    #returns the max status in the PbR files.
    local loc=$1
    local mpbrlist=($2)
    local owd=$PWD

    cd $loc
    local MAX_STAT=$(~/component/dcmtk/bin/dcmdump +P f215,1002 ${mpbrlist[@]} |\
          awk '
              BEGIN {max = 0} ( $3 != "" ) {
                  stat = int( gensub("[][]","","g",$3) );
                  if (stat > max) {max = stat} 
              } END {print max}' )
    echo "$MAX_STAT"
    cd $owd
}


repolocation=$(getStudyLocation dicom $styiuid)
archivelocation=$(getStudyLocation archive $styiuid)

for location in repolocation archivelocation; do
  if [ -n "${!location}" ]; then
    echo "$location : ${!location}"
    pbrlist=($(listPbRs ${!location}))
    numpbrs=${#pbrlist[@]}
    getMaxPBStatusarg="${pbrlist[@]}"
    maxstat=$(getMaxPBStatus ${!location} "$getMaxPBStatusarg")
    currentpbstat=$(getCurrentPBStatus ${!location} "$getMaxPBStatusarg")
    echo "PbRs: ${pbrlist[@]}"
    echo "numpbrs: $numpbrs"
    if [ "${numpbrs}" -lt "2" ]; then
        echo "There are only $numpbrs PbRs, nothing to do"
        exit 0
    fi
    echo "Max PB status: $maxstat"
    echo "Current PB status: $currentpbstat"

    if [ -n "$debug" ]; then
        echo "Creating backup ${backuploc}/${styiuid}.tgz"
        tar -czvf ${backuploc}/${styiuid}.tgz ${!location}
    fi
    nonpbrlist=($(listNonPbRs ${!location}))
    numnonpbrs=${#nonpbrlist[@]}
    echo "Non PbRs: ${nonpbrlist[@]}"
    echo "numnonpbrs: $numnonpbrs"

    for n in $(seq 0 $[ $numpbrs - 2 ]); do
    # for every pbr except the newest one (which is the last one in the list)
    # n - 2 because the count starts at 0
        echo "Applying ${pbrlist[$n]}"
        for obj in ${nonpbrlist[*]}; do # for every nonpbr object
          echo "Applying ${pbrlist[$n]} to ${styiuid}/${obj}"
          applyPbR $styiuid ${!location} ${pbrlist[$n]} $obj
          [ $? -ne 0 ] && exit 1
        done
        echo "Remove tmp work directory ~/tmp/${styiuid}.${pid}"
        [[ -d ~/tmp/${styiuid}.${pid} ]] && rm -rf  ~/tmp/${styiuid}.${pid}
        echo "Remove PbR ${pbrlist[$n]}"
        if [ "$location" == "repolocation" ]; then
          echo "~/component/taskd/runjavacmd -c \"0 cases.RemoveFiles -s $styiuid -f ${pbrlist[$n]}\""
          ~/component/taskd/runjavacmd -c "0 cases.RemoveFiles -s $styiuid -f ${pbrlist[$n]}"
        elif [  "$location" == "archivelocation" ]; then
          echo "rm -f ${archivelocation}/${pbrlist[$n]}"
          [[ -f $archivelocation/${pbrlist[$n]} ]] && rm -f $archivelocation/${pbrlist[$n]}
        fi
    done
    if [ -n "$currentpbstat" ]; then
      if [ "$currentpbstat" -lt "$maxstat" ]; then
        lastpbr=${!location}/${pbrlist[$[ $numpbrs - 1 ]]}
        echo "Apply max stat to PbR $lastpbr"
        if [ -n "$maxstat" ] ; then
          echo "~/component/dcmtk/bin/dcmodify -i \"(f215,1002)=$maxstat\" $lastpbr" 
          ~/component/dcmtk/bin/dcmodify -i "(f215,1002)=$maxstat" $lastpbr 
          if [ $? -ne 0 ]; then
            echo "Error modifying $lastpbr"
            exit 1
          else
            # dcmodify will create a <PbR>.bak file. you may want to delete it
            echo "rm -f ${lastpbr}.bak"
            [[ -f ${lastpbr}.bak ]] && rm -f ${lastpbr}.bak
          fi
        fi
      fi
    fi
  fi
done
