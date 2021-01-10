log_i "Removing the <cloud-init> package"
dpkg -P cloud-init
rm -rf /etc/cloud/ >/dev/null 2>&1
rm -rf /var/lib/cloud/ >/dev/null 2>&1
