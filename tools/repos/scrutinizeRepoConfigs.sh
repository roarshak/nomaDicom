#!/usr/bin/env bash
# Prevents accidental execution under a shell that lacks the features you’re using.

# Prevents the script from running if any command fails, if any variable is unset, or if any command in a pipeline fails.
# This is a good practice to ensure that your script behaves predictably and avoids unexpected errors.

# Read contents of repository configuration files into variables
RepoCFG_Data_File="/home/medsrv/data/dicom.repository/repository.cfg"
RepoCFG_Data=$(cat $RepoCFG_Data_File)
RepoPartCFG_Data0_File="/home/medsrv/data/dicom.repository/data0/repositorypart.cfg"
RepoPartCFG_Data0=$(cat $RepoPartCFG_Data0_File)
RepoCFG_Cache_File="/home/medsrv/var/cache.repository/repository.cfg"
RepoCFG_Cache=$(cat $RepoCFG_Cache_File)
RepoLimitsCFG_File="/home/medsrv/var/conf/limit.conf"
RepoLimitsCFG=$(cat $RepoLimitsCFG_File)

# STATIC FACTS
  # LIMITS
    # fullLimit: New resources may be inserted into mounts below this threshold only. Must be greater than switchLimit
    # moveLimit: If the space usage exceeds this threshold on a mount, the system moves the oldest resources to other mounts, which must be under fullLimit. Must be greater than cleanLimit
    # cleanLimit: When moving resources from a filled-up mount, move resources until space usage drops below this limit.
    # switchLimit: When creating new resources, the first mount is used that does not exceed this threshold. If all mounts exceed this threshold but there is at least one below fullLimit, the mount with the most space (in percentage) will be used. If all reachable mounts are above fullLimit, the repository will not allow to create new resources.
    # remindLimit: If the space usage on each available mounts exceeds this threshold, the system displays a warning message to all users in the admin group. In fact, the Repository Handler itself doesn't send any message, other parts of the system and/or the siteman server does this, but it asks the status of the repository via the getRepositoryStatus method.
    # warnLimit: The same as remind, but usually it's a greater limit, so a warning needs more care than a remind.
    # warn2Limit: Another level of warning.
    # warn3Limit: Another level of warning. These warning limits can be set independently. In case of the repository "REPOSITORY_DICOM_DATA" reaching this limit triggers the system's DISK_FULL flag, preventing the system from acception incoming data.
    # nomoveTime: Only resources older than nomoveTime days can be moved/deleted when cleaning. 'Older' means the resource wasn't created (createDirectory method) or located (getLocation) during this period. The resource's age is preserved when moving between mounts because of the cleaning process. Possible range: 0 or greater. 0 means: there is no "protected resource", any fresh resources can be moved or deleted.
    # nomoveTimeSeconds: The same as nomoveTime, it's just in seconds. Possible range: 0 or greater. 0 means: there is no "protected resource", any fresh resources can be moved or deleted.
    # isClearable: If true, the oldest resources will be deleted instead of moved when the mount is above moveLimit.
    # DISK_FULL Flags: WARN, WARN2, WARN3, FULL, CANNOTMOVE, INCOMPLETE
    # - WARN: The repository is above warnLimit, but below warn2Limit.
    # - WARN2: The repository is above warn2Limit, but below warn3Limit.
    # - WARN3: The repository is above warn3Limit, but below fullLimit.
    # - FULL: All mounts' data usage is above fullLimit (that means no new resources are allowed to create).
    # - CANNOTMOVE: The repository cannot move data into partitions because all mounts' data usage is above the fullLimit or moveLimit.
    # - INCOMPLETE: At least one of the configured mounts is not mounted (unreachable).
    # The SAFETY_FREE mechanism can also set the DISK_FULL flag if /home's free space is < SAFETY_FREE / 2. (SAFETY_FREE divided by two). When SAFETY_FREE equals 10, then the mechanism will set the DISK_FULL flag once /home reaches 95%...which is before/lower than the WARN2, WARN3, CANNOTMOVE & FULL values (all values were >= 97.5). MakeSpace.jsp would have cleared /home already except that in this case nomoveTimeSeconds was commented, making it take it's default which is 24 hours. Uncommenting the nomoveTimeSeconds allowed RH/MakeSpace to move data off /home and back down below the SAFETY_FREE threshold.
    #
  # STANDARD DEFAULT DATA REPOSITORY CONFIG
    # fullLimit=98
    # moveLimit=97
    # cleanLimit=96
    # switchLimit=95
    # warnLimit=75
    # warn2Limit=76
    # warn3Limit=94
    # nomoveTimeSeconds=300

  # STANDARD DEFAULT DATA0 REPOSITORYPART CONFIG
    # fullLimit=95
    # moveLimit=51
    # cleanLimit=50

  # STANDARD DEFAULT CACHE REPOSITORY CONFIG
    # fullLimit=96
    # moveLimit=93
    # cleanLimit=92
    # warnLimit=94
    # warn2Limit=95
    # warn3Limit=96

  # STANDARD DEFAULT LIMITS CONFIG
    # SAFETY_FREE_LIMIT="10"
    # MINIMAL_CACHE_SIZE="15"

# Parse repository configuration files and extract relevant parameter values
# Data Repository
  fullLimit_Data=$(echo "$RepoCFG_Data" | grep ^fullLimit | tr -dc '0-9.')
  moveLimit_Data=$(echo "$RepoCFG_Data" | grep ^moveLimit | tr -dc '0-9.')
  cleanLimit_Data=$(echo "$RepoCFG_Data" | grep ^cleanLimit | tr -dc '0-9.')
  switchLimit_Data=$(echo "$RepoCFG_Data" | grep ^switchLimit | tr -dc '0-9.')
  warnLimit_Data=$(echo "$RepoCFG_Data" | grep ^warnLimit | tr -dc '0-9.')
  warn2Limit_Data=$(echo "$RepoCFG_Data" | grep ^warn2Limit | sed 's/^warn2Limit=//' | tr -dc '0-9.')
  warn3Limit_Data=$(echo "$RepoCFG_Data" | grep ^warn3Limit | sed 's/^warn3Limit=//' | tr -dc '0-9.')
  nomoveTime_Data=$(echo "$RepoCFG_Data" | grep ^nomoveTime= | tr -dc '0-9.') #Value is in Days
  nomoveTimeSeconds_Data=$(echo "$RepoCFG_Data" | grep ^nomoveTimeSeconds= | tr -dc '0-9.') #Value is in Seconds
# Data0 Repository
  fullLimit_Data0=$(echo "$RepoPartCFG_Data0" | grep ^fullLimit | tr -dc '0-9.')
  moveLimit_Data0=$(echo "$RepoPartCFG_Data0" | grep ^moveLimit | tr -dc '0-9.')
  cleanLimit_Data0=$(echo "$RepoPartCFG_Data0" | grep ^cleanLimit | tr -dc '0-9.')
# Cache Repository
  fullLimit_Cache=$(echo "$RepoCFG_Cache" | grep ^fullLimit | tr -dc '0-9.')
  moveLimit_Cache=$(echo "$RepoCFG_Cache" | grep ^moveLimit | tr -dc '0-9.')
  cleanLimit_Cache=$(echo "$RepoCFG_Cache" | grep ^cleanLimit | tr -dc '0-9.')
  warnLimit_Cache=$(echo "$RepoCFG_Cache" | grep ^warnLimit | tr -dc '0-9.')
  warn2Limit_Cache=$(echo "$RepoCFG_Cache" | grep ^warn2Limit | sed 's/^warn2Limit=//' | tr -dc '0-9.')
  warn3Limit_Cache=$(echo "$RepoCFG_Cache" | grep ^warn3Limit | sed 's/^warn3Limit=//' | tr -dc '0-9.')
  nomoveTime_Cache=$(echo "$RepoCFG_Cache" | grep ^nomoveTime= | tr -dc '0-9.') #Value is in Days
  nomoveTimeSeconds_Cache=$(echo "$RepoCFG_Cache" | grep ^nomoveTimeSeconds= | tr -dc '0-9.') #Value is in Seconds
# Parse limit.conf file and extract relevant parameter values
  # safetyFreeLimit=$(echo "$RepoLimitsCFG" | grep ^SAFETY_FREE_LIMIT | tr -dc '0-9.')
  # Swallows leading spaces and removes quotes in a single step.
  safetyFreeLimit=$(awk -F= '/^[[:space:]]*SAFETY_FREE_LIMIT/{gsub(/"/,"");print $2}' "$RepoLimitsCFG_File")
  minimalCacheSize=$(echo "$RepoLimitsCFG" | grep ^MINIMAL_CACHE_SIZE | tr -dc '0-9.')

# Compare parameter values against static facts
# Intra-File Checks: dicom repo
  # If any Data Repository parameter value is above the Data Repository fullLimit, then report a warning
    for i in moveLimit_Data cleanLimit_Data switchLimit_Data warnLimit_Data warn2Limit_Data warn3Limit_Data; do
      [ -z "${!i}" ] && continue
      if [ "$(echo "${!i} > $fullLimit_Data" | bc -l)" -eq 1 ]; then
        # Skip the warning if data0 moveLimit is less than the repository full limit
        # if [ "$i" = "moveLimit_Data" ] && [ "$(echo "$moveLimit_Data0 < $fullLimit_Data" | bc -l)" -eq 1 ]; then
        if [ "$i" = "moveLimit_Data" ]; then
          if [ $(echo "${moveLimit_Data0:-99} < $fullLimit_Data" | bc -l) -eq 1 ]; then
            continue
          fi
        else
          echo "WARNING: $i(${!i}) is above the Data Repository fullLimit($fullLimit_Data) - not allowed"
          Data_Warning=1
        fi
      fi
    done
  # If the Data Repository moveLimit is less than the Data Repository cleanLimit, then report a warning
    if [ "$(echo "$moveLimit_Data < $cleanLimit_Data" | bc -l)" -eq 1 ]; then
      echo "WARNING: Data Repository moveLimit($moveLimit_Data) is less than the Data Repository cleanLimit($cleanLimit_Data) - not allowed"
      Data_Warning=1
    fi
  # If the Data Repository nomoveTime is set, then report a warning
    if [ -n "$nomoveTime_Data" ] && [ "$(echo "$nomoveTime_Data > 0" | bc -l)" -eq 1 ]; then
      echo "WARNING: Data Repository nomoveTime(days) is set to $nomoveTime_Data - recommend setting nomoveTimeSeconds instead"
      Data_Warning=1
    fi
  # If the Data Repository nomoveTimeSeconds is greater than 600 (10 minutes), then report a warning
    if [ "$(echo "${nomoveTimeSeconds_Data:-0} > 600" | bc -l)" -eq 1 ]; then
      echo "WARNING: Data Repository nomoveTimeSeconds is set to ${nomoveTimeSeconds_Data:-"unset"} - recommend setting nomoveTimeSeconds to 1200 (20 minutes - interval at which checkOverload runs) or less"
      Data_Warning=1
    fi
# Inter-File checks: dicom repo
  # 100 - (SAFETY_FREE_LIMIT / 2)
    # safetyFreeLimitCheck=$(echo "100 - ($safetyFreeLimit / 2)" | bc)
    # Shell arithmetic is safer and avoids parse errors.
    safetyFreeLimitCheck=$(( 100 - (safetyFreeLimit / 2) ))

# If the safetyFreeLimitCheck is set at a value that is lower than each thing that triggers checkOverload, then DISK_FULL will be set and checkOverload will never run.
  # checkOverload runs when:
  #   disk usage > moveLimit
  if [ "$(echo "$safetyFreeLimitCheck < $moveLimit_Data && $safetyFreeLimitCheck < ${moveLimit_Data0:-99}" | bc -l)" -eq 1 ]; then
    echo "WARNING: safetyFreeLimitCheck($safetyFreeLimitCheck) is lower than the Data Repository moveLimit($moveLimit_Data) - DISK_FULL will be set and checkOverload will never run"
    Data_Warning=1
  fi
# Intra-file checks: cache repo
  # If any Cache Repository parameter value is above the Cache Repository fullLimit, then report a warning
    for i in moveLimit_Cache cleanLimit_Cache; do
      if [ "$(echo "${!i} > $fullLimit_Cache" | bc -l)" -eq 1 ]; then
        echo "WARNING: $i(${!i}) is above the Cache Repository fullLimit($fullLimit_Cache) - not allowed"
        Cache_Warning=1
      fi
    done
  # If the Cache Repository moveLimit is less than the Cache Repository cleanLimit, then report a warning
    if [ "$(echo "$moveLimit_Cache < $cleanLimit_Cache" | bc -l)" -eq 1 ]; then
      echo "WARNING: Cache Repository moveLimit($moveLimit_Cache) is less than the Cache Repository cleanLimit($cleanLimit_Cache) - not allowed"
      Cache_Warning=1
    fi
  # If the Cache Repository nomoveTime is set, then report a warning
    if [ -n "$nomoveTime_Cache" ] && [ "$(echo "$nomoveTime_Cache > 0" | bc -l)" -eq 1 ]; then
      echo "WARNING: Cache Repository nomoveTime(days) is set to $nomoveTime_Cache - recommend setting nomoveTimeSeconds instead"
      Cache_Warning=1
    fi
  # If the Cache Repository nomoveTimeSeconds is greater than 600 (10 minutes), then report a warning
    if [ "$(echo "${nomoveTimeSeconds_Cache:-0} > 600" | bc -l)" -eq 1 ]; then
      echo "WARNING: Cache Repository nomoveTimeSeconds is set to ${nomoveTimeSeconds_Cache:-"unset"} - recommend setting nomoveTimeSeconds to 1200 (20 minutes - interval at which checkOverload runs) or less"
      Cache_Warning=1
    fi
# Inter-file checks: cache repo
  if [ "$(echo "$safetyFreeLimitCheck < $moveLimit_Cache" | bc -l)" -eq 1 ]; then
    echo "WARNING: safetyFreeLimitCheck($safetyFreeLimitCheck) is lower than the Cache Repository moveLimit($moveLimit_Cache) - DISK_FULL will be set and checkOverload will never run"
    Cache_Warning=1
  fi

# If any warning was reported, then display the corresponding cfg file
  if [ -n "$Data_Warning" ] && [ "$Data_Warning" -eq 1 ]; then
    echo "DATA REPOSITORY CFG FILE:"
    echo "$RepoCFG_Data"
  fi
  if [ -n "$Cache_Warning" ] && [ "$Cache_Warning" -eq 1 ]; then
    echo "CACHE REPOSITORY CFG FILE:"
    echo "$RepoCFG_Cache"
  fi