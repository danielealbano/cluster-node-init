# PRECONFIGURATION
# ---
# useradd -m -c "microk8s - remote add node user" -G microk8s microk8s-remote-add-node-user
# ssh-keygen -fmicrok8s-remote-add-node-user-key -t ed25519 -b 2096 -C "microk8s-remote-add-node-user-key@$(hostname)" -q -N ''
# mkdir ~microk8s-remote-add-node-user/.ssh
# chown microk8s-remote-add-node-user.microk8s-remote-add-node-user ~microk8s-remote-add-node-user/.ssh
# chmod 700 ~microk8s-remote-add-node-user/.ssh
# cp microk8s-remote-add-node-user-key.pub ~microk8s-remote-add-node-user/.ssh/authorized_keys
# chown microk8s-remote-add-node-user.microk8s-remote-add-node-user ~microk8s-remote-add-node-user/.ssh/authorized_keys
# chmod 600 ~microk8s-remote-add-node-user/.ssh/authorized_keys
#
# Update the configuration as follow
# MICROK8S_JOIN_REMOTE_USER to microk8s-remote-add-node-user
# MICROK8S_JOIN_MASTER_HOSTNAME to __MASTER_NODE_HOSTNAME__
# MICROK8S_JOIN_REMOTE_USER_SSH_KEY_BASE64 to $(cat microk8s-remote-add-node-user-key | base64 -w0)


# Check if microk8s is installed
if ! ( snap info microk8s | grep "installed" 2>&1 >/dev/null );
then
    log_i "Installing microk8s"
    snap install microk8s --classic --channel=1.19/stable

    log_i "Starting and stopping microk8s, first boot before fixing containerd"
    microk8s start
    microk8s stop

    log_i "Configuring containerd to run off the nvme storage"
    sed \
        -e 's|--root ${SNAP_COMMON}/var/lib/containerd|--root /mnt/data/microk8s/containerd/root|' \
        -e 's|--state ${SNAP_COMMON}/run/containerd|--state /mnt/data/microk8s/containerd/state|' \
        -i \
        /var/snap/microk8s/current/args/containerd

    mkdir -p /mnt/data/microk8s/containerd/root
    mkdir -p /mnt/data/microk8s/containerd/state
else
    log_i "microk8s is already installed"
fi

# Check if the service is running or not
if ! ( snap services microk8s | grep "microk8s.daemon-kubelet" | grep "active" 2>&1 >/dev/null );
then
    log_i "Starting microk8s"
    microk8s start
fi

# Check if the microk8s ha-cluster addon is enabled
MICROK8S_STATUS_HACLUSTER=$(microk8s status -a ha-cluster)
if [ "${MICROK8S_STATUS_HACLUSTER}" = "enabled" ];
then
    log_i "Waiting for the first boot, better to go and drink coffee"
    sleep 5 && microk8s status --wait-ready

    log_i "Removing microk8s ha-cluster module, go for a long walk"
    (sleep 1 && microk8s disable ha-cluster) || \
    (sleep 10 && microk8s disable ha-cluster) || \
    (sleep 10 && microk8s disable ha-cluster)

    log_i "Waiting for the first boot without the ha-cluster module, after a walk another coffee is always necessary"
    microk8s status --wait-ready
fi

# TODO: detect if the node has already been joined
if [ true ];
then
    echo "${MICROK8S_JOIN_REMOTE_USER_SSH_KEY_BASE64}" | base64 -d > temp.key
    chmod 600 temp.key

    NEW_JOIN_TOKEN="$(tr -dc A-Za-z0-9 </dev/urandom | head -c 32)"

    echo $NEW_JOIN_TOKEN

    log_i "Registering new token for joining"
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i temp.key "${MICROK8S_JOIN_REMOTE_USER}@${MICROK8S_JOIN_MASTER_HOSTNAME}" "microk8s add-node --token ${NEW_JOIN_TOKEN} --token-ttl 60; exit" || true

    rm temp.key

    log_i "Joining the microk8s cluster"
    microk8s join ${MICROK8S_JOIN_MASTER_HOSTNAME}:25000/${NEW_JOIN_TOKEN}
fi
