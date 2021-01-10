LOG_MESSAGE_PREFIX=""
LOG_MESSAGE_SKIP_TIMESTAMP=0

function systemd_is_invocation_id_available() {
    if [ ! -z "${INVOCATION_ID}" ];
    then
        return 0
    else
        return 1
    fi
}

function log_disable_timestamp() {
    LOG_MESSAGE_SKIP_TIMESTAMP=1
}

function log_message() {
    local LEVEL="$1"
    shift
    local MESSAGE="$@"
    local MESSAGE_PREFIX=""
    
    if [ ${LOG_MESSAGE_SKIP_TIMESTAMP} == 0 ];
    then
        MESSAGE_PREFIX="[$(date +%c)]"
    fi

    MESSAGE_PREFIX="${MESSAGE_PREFIX}[${LEVEL}]"

    if [ ! -z "${LOG_MESSAGE_PREFIX}" ];
    then
        local MESSAGE_PREFIX="${MESSAGE_PREFIX}[${LOG_MESSAGE_PREFIX}]"
    fi

    if [ "${LEVEL}" = "ERROR" ];
    then
        echo -e "${MESSAGE_PREFIX} ${MESSAGE}" >&2
    else
        echo -e "${MESSAGE_PREFIX} ${MESSAGE}"
    fi
}

function log_set_message_prefix() {
    LOG_MESSAGE_PREFIX="$@"
}

function log_clear_message_prefix() {
    LOG_MESSAGE_PREFIX=""
}

function log_v() {
    log_message VERBOSE $@
}

function log_i() {
    log_message INFO $@
}

function log_w() {
    log_message WARNING $@
}

function log_e() {
    log_message ERROR $@
}

function help() {
cat << EOF
Usage:
cluster-node-init -h                                             Display this help message.
cluster-node-init -c /path/to/config.env -m /path/to/modules.d   Run the modules defined in the /path/to/modules.d
                                                                 folder with the config loaded from /path/to/config.env.
EOF
    exit 0
}

function fatal() {
    log_e $@
    exit 1
}

function fatal_with_help() {
    log_e $@
    echo ""
    help
    exit 1
}

function get_env_var() {
    local VAR_NAME=$1

    VAR_VALUE="${!VAR_NAME}"

    echo "${VAR_VALUE}"
}

function systemctl_service_is_running() {
    local SERVICE_NAME="$1"

    if systemctl list-units --type=service --state=running | grep "${SERVICE_NAME}.service" >/dev/null;
    then
        log_v "The service <${SERVICE_NAME}> is running"
        return 0
    else
        log_v "The service <${SERVICE_NAME}> is not running"
        return 1
    fi
}
