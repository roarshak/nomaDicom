#!/bin/bash

# Function to display information
display_info() {
    local var_name=$1
    local var_value=$2
    local file=$3
    echo "${var_name}=${var_value} (found in ${file})"
}

echo "Collecting networking information..."

# /etc/sysconfig/network
if [ -f /etc/sysconfig/network ]; then
    while IFS= read -r line; do
        display_info "$(echo $line | cut -d '=' -f 1)" "$(echo $line | cut -d '=' -f 2)" "/etc/sysconfig/network"
    done < /etc/sysconfig/network
fi

# /sbin/ifconfig | grep -i inet
ifconfig_output=$(/sbin/ifconfig | grep -i inet)
while IFS= read -r line; do
    inet=$(echo $line | grep -oP '(?<=inet\s)\S+')
    netmask=$(echo $line | grep -oP '(?<=netmask\s)\S+')
    broadcast=$(echo $line | grep -oP '(?<=broadcast\s)\S+')
    if [ -n "$inet" ]; then
        display_info "inet" "$inet" "/sbin/ifconfig"
    fi
    if [ -n "$netmask" ]; then
        display_info "netmask" "$netmask" "/sbin/ifconfig"
    fi
    if [ -n "$broadcast" ]; then
        display_info "broadcast" "$broadcast" "/sbin/ifconfig"
    fi
done <<< "$ifconfig_output"

# /etc/hostname
if [ -f /etc/hostname ]; then
    hostname_value=$(cat /etc/hostname)
    display_info "HOSTNAME" "$hostname_value" "/etc/hostname"
fi

# /etc/hosts
if [ -f /etc/hosts ]; then
    while IFS= read -r line; do
        if [[ $line =~ ^[0-9] ]]; then
            ip=$(echo $line | awk '{print $1}')
            hostnames=$(echo $line | awk '{print $2}')
            display_info "HOST" "$hostnames" "/etc/hosts"
            display_info "IP" "$ip" "/etc/hosts"
        fi
    done < /etc/hosts
fi

# Custom configurations from ~/var/conf/dotcom.jcfg
if [ -f /home/medsrv/var/conf/dotcom.jcfg ]; then
    while IFS= read -r line; do
        if [[ $line =~ IP ]]; then
            ip=$(echo $line | awk '{print $2}')
            display_info "SERVERIP" "$ip" "/home/medsrv/var/conf/dotcom.jcfg"
        fi
    done < ~/var/conf/dotcom.jcfg
fi

# Additional IP and hostname information
server_ip=$(echo $SERVERIP)
if [ -n "$server_ip" ]; then
    display_info "SERVERIP" "$server_ip" "Environment variable"
fi

hostname_ip=$(hostname -i)
if [ -n "$hostname_ip" ]; then
    display_info "HOSTNAME_IP" "$hostname_ip" "hostname -i"
fi

echo "Networking information collected."
