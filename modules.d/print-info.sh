# Report the ip addresses and the hostname
log_i "Hostname"
log_i "> $(hostname)"
log_i ""
log_i "IP Address(es)"
for NET_DEV_PATH in /sys/class/net/*;
do
    NET_DEV_NAME=$(basename $NET_DEV_PATH)
    if [ "${NET_DEV_NAME}" = "lo" ];
    then
        continue;
    fi

    NET_DEV_STATE=$(cat $NET_DEV_PATH/operstate)
    if [ ! "${NET_DEV_STATE}" = "up" ];
    then
        continue;
    fi

    log_i "> ${NET_DEV_NAME}"
    NET_DEV_IP_ADDRESSES="$(ip addr show eth0 | grep inet | awk '{ print $2 }')"
    for NET_DEV_IP_ADDRESS in ${NET_DEV_IP_ADDRESSES};
    do
        log_i "* ${NET_DEV_IP_ADDRESS}"
    done
    log_i ""
done

# Report about the host keys
log_i "SSH host keys"
for HOST_PUB_KEY in /etc/ssh/ssh_host_*.pub;
do
    log_i "> $(basename $HOST_PUB_KEY)"
    log_i "> $(cat $HOST_PUB_KEY | awk '{ printf $2 }')"
    log_i ""
done
