#!/usr/bin/env bash
# movescu_dashboard.sh – lightweight live snapshot of movescu transfers
#
# Columns
#   QSIZE   Recv-Q/Send-Q from `ss` (bytes queued right now)
#   ELAPSED Run-time reported by `ps`
#
# Use `watch -n2 ./movescu_dashboard.sh` for a live dashboard.

shopt -s extglob          # enables ${var%% *} trimming

# ---------- find running movescu commands ----------
mapfile -t MOVESCU_LINES < <(pgrep -af '/movescu\b')
TOTAL=${#MOVESCU_LINES[@]}

printf '%s [movescu-dashboard] Active movescu: %d\n' \
       "$(date '+%F %T')" "$TOTAL"
(( TOTAL == 0 )) && exit 0

# ---------- table header ----------
printf '%-7s %-8s %-12s %-12s %-15s %-8s %-8s %s\n' \
       PID USER LOCAL_AET DESTINATION SOURCE QSIZE ELAPSED STUDY_UID
printf -- '%*s\n' 160 '' | tr ' ' -
# ----------------------------------

# helper: snapshot Recv-Q/Send-Q for first ESTAB socket owned by PID
qsize_for_pid() {
    local pid=$1 line recvq sendq
    line=$(ss -tanp 2>/dev/null | grep -m1 "ESTAB .*pid=${pid},")
    if [[ -n $line ]]; then
        # line format: ESTAB Recv-Q Send-Q Local:Port Peer:Port Users:(...)
        read -r _ recvq sendq _ <<<"$line"
        echo "${recvq}/${sendq}"
    else
        echo "-/-"
    fi
}

# ---------- main loop ----------
for LINE in "${MOVESCU_LINES[@]}"; do
    PID=${LINE%% *}
    CMD=${LINE#* }
    USER=$(ps -o user= -p "$PID" | xargs)

    LOCAL_AET=$(grep -oP '(?<=--aetitle )\S+'        <<<"$CMD")
    DESTINATION=$(grep -oP '(?<=--move )\S+'         <<<"$CMD")
    SOURCE=$(grep -oP '(?<=--call )\S+'              <<<"$CMD")
    STUDY_UID=$(grep -oP '(?<=--key 0020,000d=)\S+'  <<<"$CMD")
    ELAPSED=$(ps -o etime= -p "$PID" | xargs)

    QSIZE=$(qsize_for_pid "$PID")

    printf '%-7s %-8s %-12s %-12s %-15s %-8s %-8s %s\n' \
           "$PID" "$USER" "$LOCAL_AET" "$DESTINATION" "$SOURCE" \
           "$QSIZE" "$ELAPSED" "$STUDY_UID"
done
