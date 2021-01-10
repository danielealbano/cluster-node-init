function user_exist() {
    local USER_NAME=$1

    if id "${USER_NAME}" >/dev/null 2>&1;
    then
        return 0
    else
        return 1
    fi
}

function user_get_home_path() {
    local USER_NAME="$1"

    eval "echo ~${USER_NAME}"
}

function user_has_ssh_auth_key() {
    local USER_NAME="$1"
    local USER_SSH_AUTH_KEY="$2"

    local USER_HOME_PATH=$(user_get_home_path "${USER_NAME}")

    if cat "${USER_HOME_PATH}/.ssh/authorized_keys" 2>&1 | grep "${USER_SSH_AUTH_KEY}" >/dev/null 2>&1;
    then
        return 0
    else
        return 1
    fi
}

function user_add_ssh_auth_key() {
    local USER_NAME="$1"
    local USER_SSH_AUTH_KEY="$2"

    local USER_HOME_PATH=$(user_get_home_path "${USER_NAME}")

    if [ ! -d ${USER_HOME_PATH}/.ssh ];
    then
        log_i "Creating <${USER_HOME_PATH}/.ssh>"
        mkdir ${USER_HOME_PATH}/.ssh
        chown ${USER_NAME}.${USER_NAME} ${USER_HOME_PATH}/.ssh
        chmod 700 ${USER_HOME_PATH}/.ssh
    fi

    if [ ! -f ${USER_HOME_PATH}/.ssh/authorized_keys ];
    then
        log_i "Creating <${USER_HOME_PATH}/.ssh/authorized_keys>"
        touch ${USER_HOME_PATH}/.ssh/authorized_keys
        chown ${USER_NAME}.${USER_NAME} ${USER_HOME_PATH}/.ssh/authorized_keys
        chmod 600 ${USER_HOME_PATH}/.ssh/authorized_keys
    fi

    echo "${USER_SSH_AUTH_KEY}" >> "${USER_HOME_PATH}/.ssh/authorized_keys"
}

LOOP_INDEX=-1
while [ true ];
do
    LOOP_INDEX=$((LOOP_INDEX + 1))
    USER_NAME=$(get_env_var "USER_${LOOP_INDEX}_NAME")
    if [ -z "${USER_NAME}" ];
    then
        break;
    fi

    if user_exist "${USER_NAME}";
    then
        log_i "User <${USER_NAME}> already existing, skipping creation but syncing settings"

        USER_MOD_CREATE_OPTS="";

        USER_SHELL=$(get_env_var "USER_${LOOP_INDEX}_SHELL")
        if [ ! -z "${USER_SHELL}" ];
        then
            log_i "Shell <${USER_SHELL}> requested"

            USER_MOD_CREATE_OPTS="-s ${USER_SHELL}";
        fi

        USER_GROUP=$(get_env_var "USER_${LOOP_INDEX}_GROUP")
        if [ ! -z "${USER_GROUP}" ];
        then
            log_i "User group set to <${USER_GROUP}>"
            USER_MOD_CREATE_OPTS="${USER_MOD_CREATE_OPTS} -g ${USER_GROUP}";
        fi

        USER_GROUPS=$(get_env_var "USER_${LOOP_INDEX}_GROUPS")
        if [ ! -z "${USER_GROUPS}" ];
        then
            log_i "User additional groups set to <${USER_GROUPS}>"
            USER_MOD_CREATE_OPTS="${USER_MOD_CREATE_OPTS} -G ${USER_GROUPS}";
        fi

        log_i "Syncing user settings"
        eval "usermod ${USER_MOD_CREATE_OPTS} ${USER_NAME}"
        log_i "User settings synced"
    else
        log_i "The user <${USER_NAME}> must be created"

        USER_ADD_CREATE_OPTS=$(get_env_var "USER_${LOOP_INDEX}_ADD_CREATE_OPTS_OVERRIDE")
        if [ -z "${USER_ADD_CREATE_OPTS}" ];
        then
            USER_ADD_CREATE_OPTS="";

            USER_SHELL=$(get_env_var "USER_${LOOP_INDEX}_SHELL")
            if [ ! -z "${USER_SHELL}" ];
            then
                log_i "Shell <${USER_SHELL}> requested"

                USER_ADD_CREATE_OPTS="-s ${USER_SHELL}";
            fi

            USER_CREATE_HOME=$(get_env_var "USER_${LOOP_INDEX}_CREATE_HOME")
            if [ ! -z "${USER_CREATE_HOME}" ];
            then
                log_i "Home folder creation requested"

                USER_ADD_CREATE_OPTS="${USER_ADD_CREATE_OPTS} -m";
            fi

            USER_GROUP=$(get_env_var "USER_${LOOP_INDEX}_GROUP")
            if [ ! -z "${USER_GROUP}" ];
            then
                log_i "User group set to <${USER_GROUP}>"
                USER_ADD_CREATE_OPTS="${USER_ADD_CREATE_OPTS} -g ${USER_GROUP}";
            else
                log_i "Using default user group"
            fi

            USER_GROUPS=$(get_env_var "USER_${LOOP_INDEX}_GROUPS")
            if [ ! -z "${USER_GROUPS}" ];
            then
                log_i "User additional groups set to <${USER_GROUPS}>"
                USER_ADD_CREATE_OPTS="${USER_ADD_CREATE_OPTS} -G ${USER_GROUPS}";
            else
                log_i "No additional user groups"
            fi
        else
            log_i "User add options overriden <${USER_ADD_CREATE_OPTS}>"        
        fi

        log_i "Creating user"
        eval "useradd ${USER_ADD_CREATE_OPTS} ${USER_NAME}"
        log_i "User created"
    fi

    USER_SUDO_NOPASSWD=$(get_env_var "USER_${LOOP_INDEX}_SHELL")
    if [ ! -z "${USER_SUDO_NOPASSWD}" ];
    then
        SUDO_LINE="${USER_NAME} ALL=(ALL:ALL) NOPASSWD:ALL"

        if ! (cat /etc/sudoers 2>&1 | grep "${SUDO_LINE}" >dev/null);
        then
            log_i "Setting sudo NOPASSWD flag for the user"
            echo "${SUDO_LINE}" >> /etc/sudoers
        else
            log_i "Sudo NOPASSWD flag for the user already set, skipping"
        fi
    fi

    LOOP_INDEX_SSH_AUTH_KEYS=-1
    while [ true ];
    do
        LOOP_INDEX_SSH_AUTH_KEYS=$((LOOP_INDEX_SSH_AUTH_KEYS + 1))
        USER_AUTH_KEY=$(get_env_var "USER_${LOOP_INDEX}_SSH_AUTH_KEYS_${LOOP_INDEX_SSH_AUTH_KEYS}")
        if [ -z "${USER_AUTH_KEY}" ];
        then
            break
        fi

        if user_has_ssh_auth_key "${USER_NAME}" "${USER_AUTH_KEY}";
        then
            log_i "User <${USER_NAME}> has already auth key <${LOOP_INDEX_SSH_AUTH_KEYS}>, skipping creation"
            continue
        else
            log_i "Adding auth key <${LOOP_INDEX_SSH_AUTH_KEYS}> to user <${USER_NAME}>"
            user_add_ssh_auth_key "${USER_NAME}" "${USER_AUTH_KEY}"
            log_i "Auth key added"
        fi
    done
done
