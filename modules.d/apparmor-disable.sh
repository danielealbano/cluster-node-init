if [ "${APPARMOR_DISABLE}" = "1" ];
then
    if (systemctl_service_is_running apparmor);
    then
        systemctl stop apparmor
        systemctl disable apparmor
    fi
else
    if ! (systemctl_service_is_running apparmor);
    then
        systemctl enable apparmor
        systemctl start apparmor
    fi
fi
