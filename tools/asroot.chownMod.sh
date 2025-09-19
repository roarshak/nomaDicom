#!/bin/bash
# Executing this script will recursively change the owner and group to medsrv.
# It will also add execute permissions to all files ending with '.sh'

# Define Variables
  _WDIR="$(pwd)"

# Define Functions
  DisplayUsage() {
    printf "Usage: %s [OPTION]... [DIRECTORY]...\n" "$(getScriptName)"
    printf "Recursively change the owner and group to medsrv and sets '.sh' files as executable.\n"
    printf "\n"
    printf "  -h, --help\t\tDisplay this help and exit\n"
    printf "  --whatif\t\tDisplay what would be done\n"
    printf "  --imsure\t\tExecute the script\n"
    exit 0
  }
  getScriptName() {
    basename "$0"
  }
  dryRun() {
    if [ "$dryRun" = "true" ]; then
      return 0
    else
      return 1
    fi
  }
  changeOwner() {
    if dryRun; then
      echo "DRY RUN: find $1 -mindepth 0 -not -name $script_name -exec chown medsrv.medsrv {} \;"
      echo "  excluding '*.sh' files because they're already listed below"
      find "$1" -mindepth 0 -not -name "$script_name" -not -name "*.sh"
    else
      if ! find "$1" -mindepth 0 -not -name "$script_name" -exec chown medsrv.medsrv {} \;; then
        return 1
      fi
    fi
  }
  changeMode() {
    if dryRun; then
      echo "DRY RUN: find $1 -type f -name '*.sh' -exec chmod +x {} \;"
      find "$1" -type f -name "*.sh" 
    else
      if ! find "$1" -type f -name "*.sh" -exec chmod +x {} \;; then
        return 1
      fi
    fi
  }
  changeOwnerAndMode() {
    if ! changeOwner "$1"; then
      echo "ERROR: Could not change owner of $1"
    fi
    if ! changeMode "$1"; then
      echo "ERROR: Could not change mode of $1"
    fi
  }

script_name=$(getScriptName)
dryRun=true
# Get Options
while [ -n "$1" ]; do
	case $1 in
    --help|-h)   DisplayUsage ;;
    --whatif) dryRun=true ;;
    --imsure) dryRun=false ;;
    *)        printf "Unknown option (ignored): %s" "$1"; DisplayUsage ;;
  esac
  shift
done

# Main
changeOwnerAndMode "$_WDIR"
