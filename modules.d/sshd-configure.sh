function ssh_has_host_key() {
    local KEY_TYPE=$1

    # Not perfect check, potentially the public key is missing, but only if the system has been
    # messed up in the first place.
    if [ -f /etc/ssh/ssh_host_${KEY_TYPE}_key ];
    then
        return 0
    else
        return 1
    fi
}

SSHD_KEYS_REGENERATED=0
for KEY_TYPE in ecdsa ed25519 rsa;
do
    if ! (ssh_has_host_key "${KEY_TYPE}");
    then
        log_i "SSH daemon host key <${KEY_TYPE}> missing, reconfiguring openssh server"
        log_i "(will regenerate all the host keys)"

        SSHD_KEYS_REGENERATED=1
        /usr/sbin/dpkg-reconfigure openssh-server

        break
    fi
done

if [ $SSHD_KEYS_REGENERATED = "0" ];
then
    log_i "SSH daemon host keys already existing, nothing to do"
fi
