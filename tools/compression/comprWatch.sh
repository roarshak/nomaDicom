#!/bin/bash

INTERVAL=5
THRESHOLD_MINUTES=5

while true; do
    clear
    echo "=== Compression Processes Dashboard ==="
    echo "Time: $(date)"
    echo
    echo -e "USER       PID\t\tSTART         ELAPSED   %CPU  %MEM   COMMAND"
    echo "--------------------------------------------------------------------------"

    processes=$(ps --no-headers -eo user,pid,start,etime,pcpu,pmem,cmd \
        | grep -E "compressObject.sh|objdiff|convert" \
        | grep -v grep)

    total_jobs=0
    total_cpu=0

    while read -r line; do
        [[ -z "$line" ]] && continue
        total_jobs=$((total_jobs + 1))

        user=$(echo "$line" | awk '{print $1}')
        pid=$(echo "$line" | awk '{print $2}')
        start=$(echo "$line" | awk '{print $3}')
        elapsed=$(echo "$line" | awk '{print $4}')
        cpu=$(echo "$line" | awk '{print $5}')
        mem=$(echo "$line" | awk '{print $6}')
        cmd=$(echo "$line" | awk '{$1=$2=$3=$4=$5=$6=""; print substr($0,7)}')

        # Add CPU to total (strip non-numeric)
        cpu_clean=$(echo "$cpu" | sed 's/[^0-9.]//g')
        total_cpu=$(echo "$total_cpu + $cpu_clean" | bc)

        # Convert elapsed to seconds for comparison
        # etime format: [[dd-]hh:]mm:ss
        IFS='-' read -r days rest <<< "$elapsed"
        if [[ -z "$rest" ]]; then
            rest=$days
            days=0
        fi
    IFS=':' read -r h m s <<< "$rest"
    h=${h:-0}; m=${m:-0}; s=${s:-0}
    # Strip leading zeros to avoid octal interpretation in arithmetic (e.g. 09)
    h=$(echo "$h" | sed 's/^0*//'); h=${h:-0}
    m=$(echo "$m" | sed 's/^0*//'); m=${m:-0}
    s=$(echo "$s" | sed 's/^0*//'); s=${s:-0}
    elapsed_seconds=$((days*86400 + h*3600 + m*60 + s))

        # (longest-job tracking removed)

        # Highlight if elapsed >= threshold
        if (( elapsed_seconds >= THRESHOLD_MINUTES*60 )); then
            printf "\e[31m%-10s %-6s\t%-13s %-9s %-5s %-5s %s\e[0m\n" "$user" "$pid" "$start" "$elapsed" "$cpu" "$mem" "$cmd"
        else
            printf "%-10s %-6s\t%-13s %-9s %-5s %-5s %s\n" "$user" "$pid" "$start" "$elapsed" "$cpu" "$mem" "$cmd"
        fi
    done <<< "$processes"

    echo
    echo "Summary: Active Jobs = $total_jobs | Total CPU = ${total_cpu}%"
    echo "Refresh every $INTERVAL seconds. Press Ctrl+C to exit."
    sleep $INTERVAL
done