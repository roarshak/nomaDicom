#!/bin/bash
#shellcheck disable=SC1090


initialize_environment() {
    BatchMode="${BatchMode:-true}"
    if ! . universal.lib; then
        echo "Required library (universal.lib) not found. Exiting..."; exit 1
    else
        initialize_script_variables "MigAdmin.sh"  # Sets: _SCRIPT_NAME, _SCRIPT_CFG, _SCRIPT_LOG
        initialize_script_environment              # Verifies $USER, Verifies/Sources .default.cfg & migration.cfg
        verify_env || exit 1                       # Ensure all ${env_vars[@]} are set & not empty.
    fi
}
main() {
    initialize_environment

  # TAR
  # tar -vczf case-#####_Server_date.tgz <target_dir>
  # -v = verbose
  # -c = create
  # -z = apply gzip compression
  # -f = output to this file

  # ZIP
  zip_file_name="case-${CaseNumber:?}_$(hostname)_$(hostname -i)_$(date "+%Y%m%d").zip"
  zip -vr "../$zip_file_name" *

  # -v = verbose
  # -r = recursive
  # [ DON'T use ] -k = convert names/paths to MSDOS, store only MSDOS attributes, marks as made by MSDOS
}

main "$@"
