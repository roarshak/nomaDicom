#! /bin/bash

# Find studies in repo with no images
## Find studies in repo in deleted status
## Find studies in multiple repo locations
## Find studies with more than one PbR

. $HOME/etc/setenv.sh

styiuid=$1
[ -z "$styiuid" ] && { echo "$0 <styiuid>" ; exit 1 ; }

function checkMultiRepo() {

    local styiuid=$1

    . $HOME/data/dicom.repository/repository.cfg
    local mountpoints="$(echo $mountPoints | sed 's/\\/ /g')"
    local count=0
    local hashdir=$($HOME/component/utils/bin/getHashDirectory -i $styiuid)

    for mount in $mountpoints; do
        local loctocheck="/home/medsrv/data/dicom.repository/${mount}/${hashdir}"
        if [ -d "$loctocheck" ]; then
            #echo "$mount : $loctocheck" >&2
            (( count += 1 ))
            [ -z "$mounts" ] && mounts="$mount" || mounts="$mounts $mount"
        fi
    done
    if [ $count -gt 1 -o $count -eq 0 ]; then
        echo "$styiuid: multirepo : $count : $mounts"
        return 1
    fi
    
}

## List of PbRs oldest to newest
function listPbRs() {
    local location=$1
    local pbrs

    ls -1tr ${location}| grep PbR
}

## List of objects oldest to newest
function listObjects() {
    local location=$1
    local objects

    ls -1tr ${location}
}


function checkNoObjects() {
    local styiuid=$1

    local studydir=$($HOME/component/repositoryhandler/scripts/locateStudy.sh -d $styiuid)
    local objlist=($(listObjects ${studydir}))
    local numobjs=${#objlist[@]}

    if [ "${numobjs}" -eq "0" ]; then
        echo "$styiuid : zerobjects"
    fi
}

function checkMultiplePbR() {

    local styiuid=$1

    local studydir=$($HOME/component/repositoryhandler/scripts/locateStudy.sh -d $styiuid)
    local pbrlist=($(listPbRs ${studydir}))
    local numpbrs=${#pbrlist[@]}

    if [ "${numpbrs}" -gt "1" ]; then
        echo "$styiuid : multiPbR : $numpbrs"
    fi
}

function checkDeleted() {

    local styiuid=$1

    local studydir=$($HOME/component/repositoryhandler/scripts/locateStudy.sh -d $styiuid)
    if grep 'ProcessMode="Deleted"' ${studydir}/.info/storestate.rec > /dev/null 2>&1 ; then
        echo "$styiuid : ProcessmodeDeleted"
    fi
}

function usage() {
    echo "Usage: $0 [-s styiuid] [-f filename]"
    echo "  -s styiuid : Specify a single study instance UID"
    echo "  -f filename : Specify a file containing a list of study instance UIDs"
    exit 1
}

function processStudies() {
    local styiuid=$1

    if [ -z "$styiuid" ]; then
        echo "No study UID provided."
        exit 1
    fi

    checkNoObjects "$styiuid" | tee -a sa-output-noObjects.log
    checkDeleted "$styiuid" | tee -a sa-output-deletedStudies.log
    checkMultiplePbR "$styiuid" | tee -a sa-output-multiPbr.log
    checkMultiRepo "$styiuid" | tee -a sa-output-multiRepo.log
}

while getopts ":s:f:" opt; do
    case $opt in
        s)
            single_styiuid="$OPTARG"
            ;;
        f)
            filename="$OPTARG"
            ;;
        *)
            usage
            ;;
    esac
done

if [ -n "$single_styiuid" ]; then
    processStudies "$single_styiuid"
elif [ -n "$filename" ]; then
    if [ -f "$filename" ]; then
        while IFS= read -r styiuid; do
            processStudies "$styiuid"
        done < "$filename"
    else
        echo "File '$filename' not found!"
        exit 1
    fi
else
    usage
fi
