if ! cat /etc/systemd/system/getty@tty1.service.d/override.conf 2>&1 | grep TTYVTDisallocate=no >/dev/null;
then
    log_i "Setting <TTYVTDisallocate> to <no> for <getty@tty1>"
    mkdir -p /etc/systemd/system/getty@tty1.service.d >/dev/null 2>&1
    echo -e "[Service]\nTTYVTDisallocate=no" > /etc/systemd/system/getty@tty1.service.d/override.conf
    systemctl daemon-reload
else
    log_i "The parameter <TTYVTDisallocate> for <getty@tty1> is already set to <no>"
fi
