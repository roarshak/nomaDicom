#!/bin/sh

# Verify a single argument was provided.
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <STYIUID>" >&2
    exit 1
fi

study_uid="$1"

# Call the locateStudy script from the repositoryhandler component to obtain the filesystem location.
result=$(~/component/repositoryhandler/scripts/locateStudy.sh -d "$study_uid")

# Output the study filesystem location.
echo "$result"
