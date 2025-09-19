#!/bin/bash
# shellcheck disable=SC1090,SC1091

Usage() {
    echo "Usage: $0 [options]..."
    echo ""
    echo "This script is designed to perform backups of DICOM studies that have not been migrated correctly."
    echo "It verifies necessary conditions, prepares backup directories, and rsyncs study data."
    echo ""
    echo "Options:"
    echo "  -h, --help            Display this help message and exit."
    echo "  --script              Indicate that the script is executed programmatically (suppresses certain user interactions)."
    echo "  --ip <source_ip>      Specify the IP address of the source system from which to backup the study."
    echo "  -S, --study <SUID>    Specify the Study UID that needs to be backed up."
    echo ""
    echo "Examples:"
    echo "  $0 --ip 192.168.1.100 --study 1.2.3.4.5"
    echo "  $0 --script --ip 192.168.1.100 --study 1.2.3.4.5"
    echo ""
    echo "Make sure to run this script as the 'medsrv' user and to provide all required arguments."
}

# Configuration and setup
configure_environment() {
    backup_directory="$(pwd)/backups/dcm/failed2migrate"
    backup_sty_directory="$backup_directory/$SUID"
    file_for_source_obj_info="$backup_sty_directory/objinfo.source"
    file_for_target_obj_info="$backup_sty_directory/objinfo.target"
}

user_check() {
		[ "$USER" != "medsrv" ] && echo "This script must be run as medsrv!" && exit 1
}

userConfirmation() {
	# Ask user for confirmation
	read -r -p "Are you sure you want to rsync this study? (y/n) " < /dev/tty
	echo
	if [[ ! $REPLY =~ ^[Yy]$ ]]; then
		exit 1
	fi
}

# Validate the setup and check requirements
validate_environment() {
    Check_Required_Variables SUID source_ip
    SSH_is_Enabled
}

SSH_is_Enabled() {
	# Test the ssh connection using the provided keypair
	# if ssh -q -o PasswordAuthentication=no -o BatchMode=yes -o StrictHostKeyChecking=no -i "$keypair" "${user}@${ip}" "w" >/dev/null 2>&1; then
	if ! ssh -n -q -o PasswordAuthentication=no -o BatchMode=yes -o StrictHostKeyChecking=no "medsrv@${source_ip}" "w" >/dev/null 2>&1; then
		printf "Failed ssh connection to medsrv@%s\n" "$source_ip"
		exit 1
	fi
}

Check_Required_Variables() {
	# Take a list of variables as arguments and check that they are all set
	# If any are not set, exit with an error
	local var
	for var in "$@"; do
			eval "value=\$$var"
			if [ -z "$value" ]; then
					printf "ERROR: %s is not set\n" "$var" >&2
					exit 1
			fi
	done
}

checkStudyDirValidity() {
	# When source stydir is empty
	if [ -z "$_source_stydir" ]; then
		echo "$(date) skipped rsync. reason: source study directory empty ($_source_stydir). Exam $SUID"
		exit 1
	
	# When source has multiple stydirs
	elif [ "$(echo "$_source_stydir" | wc -l)" -gt 1 ]; then
		item1="$(echo "$_source_stydir" | head -1 | awk '{print $2}' | sed 's/\/.info\/storestate.rec//g')"
		item2="$(echo "$_source_stydir" | head -1 | awk '{print $4}' | sed 's/\/.info\/storestate.rec//g')"
		# Use sed to print the second line of $_source_stydir
		item3=$(echo "$_source_stydir" | sed -n '2p')
	
	# When source has one stydir
	else
		item3="$_source_stydir"
	fi
}

rsync_unmigrated_study() {
	local this_is_a_variable
	this_is_a_variable="some value"
	for remote_dir in "$item3" "$item1" "$item2"; do
		if [ -n "$remote_dir" ]; then
			echo "Command: rsync -avz $source_ip:$remote_dir/ $backup_sty_directory/"
			userConfirmation
			if rsync -az $source_ip:$remote_dir/ $backup_sty_directory/ > $backup_sty_directory/rsync.log; then
				# TELL USER WE ARE FINISHED AND GIVE SUMMARY
				echo "$(date) successfully rsyncd unmigrated exam $SUID"
			else
				echo "$(date) rsync failed for $SUID"
			fi
		fi
	done
}

document_source_sty_info() {
	ssh -n $source_ip "sql.sh \"SELECT STYIUID, SOPCLUID, SERIUID, SERNUMBER, SOPIUID, FNAME FROM Dcobject WHERE STYIUID='$SUID'\" -t" > $file_for_source_obj_info
}

document_target_sty_info() {
	sql.sh "SELECT STYIUID, SOPCLUID, SERIUID, SERNUMBER, SOPIUID, FNAME FROM Dcobject WHERE STYIUID='$SUID'" -t > $file_for_target_obj_info
}

getStyLocFromSource() {
	# Get the location of the study on the source server
	ssh -n $source_ip "/home/medsrv/component/repositoryhandler/scripts/locateStudy.sh -d $SUID"
}

# Main operational functions
perform_backup() {
    make_backup_dir
    make_backup_sty_dir
    document_source_sty_info
    document_target_sty_info
    local _source_stydir=$(getStyLocFromSource)
    checkStudyDirValidity
    rsync_unmigrated_study
}

# Utility functions
make_backup_dir() {
    [ ! -d "$backup_directory" ] && mkdir -p "$backup_directory"
}

make_backup_sty_dir() {
    [ ! -d "$backup_sty_directory" ] && mkdir -p "$backup_sty_directory"
}

# More utility functions here...

# Main execution logic
main() {
    user_check
    [ $# -eq 0 ] && { echo "No arguments provided"; exit 1; }
    parse_arguments "$@"
    configure_environment
    validate_environment
    perform_backup
}

# Argument parsing
parse_arguments() {
    while [ -n "$1" ]; do
        case $1 in
            --help|-h)   Usage; exit 0 ;;
            --script) executedByUser=False ;;
            --ip)  source_ip="$2"; shift ;;
            --study|-S|-s)  SUID="$2"; shift ;;
            *)        echo "Unknown option (ignored): $1"; exit 1 ;;
        esac
        shift
    done
}

main "$@"