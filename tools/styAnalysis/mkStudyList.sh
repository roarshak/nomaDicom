#!/bin/bash
StudyListFileName="suid-list_$(date "+%Y%m%d-%H%M%S").txt"
echo -e "$(date "+%Y%m%d-%H%M%S")\tMaking study list. Excluding ORDERS and COPIES/SHORTCUTS."
sql.sh "SELECT STYIUID FROM Dcstudy WHERE MAINST>='0' AND DERIVED NOT IN('copy','shortcut')" -N > "$StudyListFileName"
echo -e "$(date "+%Y%m%d-%H%M%S")\tStudy List created. Filename is [$StudyListFileName]"
