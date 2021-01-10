# Update the hostname
if [ ! -z "${HOSTNAME_CMD}" ];
then
    log_i "Running cmd <${HOSTNAME_CMD}> to determine hostname"

    HOSTNAME=$(eval ${HOSTNAME_CMD})
fi

if [ -z "${HOSTNAME}" ];
then
    log_i "No hostname set, skipping"
else
    CURRENT_HOSTNAME=$(cat /etc/hostname)
    if [ "${CURRENT_HOSTNAME}" == "${HOSTNAME}" ];
    then
        log_i "Current hostname matches <${HOSTNAME}>, don't update the current configuration"
    else
        log_i "Setting hostname to <${HOSTNAME}>"

        echo "${HOSTNAME}" > /etc/hostname
        hostname -F /etc/hostname

        log_i "Mapping <${HOSTNAME}> to <127.0.0.1>"
        HOSTS_APPEND="${HOSTNAME}"
        if [ ! -z "${HOSTNAME_DOMAIN}" ];
        then
            log_i "Mapping <${HOSTNAME}.${HOSTNAME_DOMAIN}> to <127.0.0.1>"
            HOSTS_APPEND="${HOSTNAME}.${HOSTNAME_DOMAIN} ${HOSTS_APPEND}"
        fi

        sed -e "s/127.0.0.1 localhost/127.0.0.1 localhost ${HOSTS_APPEND}/" -i /etc/hosts
    fi
fi

# Rerun the dhcp client to update the hostname
if [ "${HOSTNAME_DHCLIENT_RERUN}" ];
then
    dhclient ${HOSTNAME_DHCLIENT_DEV} -n 2>&1 >/dev/null || true
fi
