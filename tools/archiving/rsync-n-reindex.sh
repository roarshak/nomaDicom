#!/bin/bash

# Set variables
# CASE_NUMBER="case_67342"
TARGET="10.240.13.16" #FDG Old EVO PACS
suid="$1"

# Validate SUID
if [[ -z "$suid" ]]; then
    echo "Error: SUID not provided."
    echo "Usage: $0 [SUID]"
    exit 1
fi

# Locate local and remote directories
local_dir=$(~/component/repositoryhandler/scripts/locateStudy.sh -d $suid)
remote_dir=$(ssh -n $TARGET "~/component/repositoryhandler/scripts/locateStudy.sh -d $suid")

# Validate directories
if [[ -z "$local_dir" || ! -d "$local_dir" ]]; then
    echo "Error: Local directory '$local_dir' is not valid."
    exit 1
fi

if [[ -z "$remote_dir" ]]; then
    echo "Error: Remote directory path is empty."
    exit 1
fi

# Validate remote directory existence
if ! ssh -n $TARGET [[ -d "$remote_dir" ]]; then
    echo "Error: Remote directory '$remote_dir' does not exist on $TARGET."
    exit 1
fi

# Perform rsync operation
# rsync -vam -d --exclude='*/' "oldchild:$remote_dir/" "$local_dir/"
rsync -vcam -d --exclude='*/' "$TARGET:$remote_dir/" "$local_dir/"

# Reindex the study
~/component/cases/reindexStudy.sh -e $suid

echo "Sync and reindex completed for SUID: $suid"

