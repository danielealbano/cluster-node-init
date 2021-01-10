#!/bin/bash

# Copyright 2021 Daniele Salvatore Albano <d.albano@gmail.com>
# 
# Redistribution and use in source and binary forms, with or without modification, are permitted
# provided that the following conditions are met:
# 
# 1. Redistributions of source code must retain the above copyright notice, this list of conditions
# and the following disclaimer.
# 
# 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions
# and the following disclaimer in the documentation and/or other materials provided with the distribution.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED
# WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
# PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR
# ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
# LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR
# TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
# ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

set -e 

CLUSTER_NODE_INIT_DIR=$(dirname $0)

. ${CLUSTER_NODE_INIT_DIR}/functions.sh

BASH_CMD="/bin/bash"

# cluster node init variables
MODULES_PATH=""
CONFIG_PATH=""

log_i "cluster-node-init.sh v0.1"
log_i "Daniele Albano <d.albano@gmail.com>"
log_i "---"

# Parse arguments
while getopts "hm:c:" opt;
do
    case ${opt} in
        h)
            help
            ;;
        m)
            MODULES_PATH="$OPTARG"
            ;;
        c)
            CONFIG_PATH="$OPTARG"
            ;;
    esac
done
shift $((OPTIND -1))

# Check if the expected arguments have been passed
if [ -z "${MODULES_PATH}" ];
then
    fatal_with_help "Modules folder path not defined"
elif [ ! -d "${MODULES_PATH}" ];
then
    fatal_with_help "The modules path <${MODULES_PATH}> is not a folder"
fi

if [ -z "${CONFIG_PATH}" ];
then
    fatal_with_help "Config file path not defined"
elif [ ! -f "${CONFIG_PATH}" ];
then
    fatal_with_help "The config path <${CONFIG_PATH}> is not a file"
fi

# Report the modules path
log_i "The modules directory path is <${MODULES_PATH}>"
log_i "The config file path is <${CONFIG_PATH}>"

# Import the config file
log_i "Loading configuration"
. ${CONFIG_PATH}
log_i "Configuration loaded"

log_i "Searching modules <${MODULE_LIST}>"
MODULE_SEARCH_ERROR=0
for $MODULE_NAME in $MODULE_LIST;
do
    MODULE_PATH="${MODULES_PATH}/${MODULE_NAME}.sh"

    if ! [ -e $MODULE_PATH ];
    then
        log_e "Unable to find module <${MODULE_NAME}>"
        MODULE_SEARCH_ERROR=1
    fi
done

if [ $MODULE_SEARCH_ERROR == 1 ];
then
    fatal "One or more modules are missing, unable to continue"
fi

log_i "All requested modules are available"

# Iterate over the modules to execute
for MODULE_NAME in $MODULE_LIST;
do
    MODULE_RETRIES=$MODULE_EXECUTION_MAX_RETRIES
    MODULE_EXECUTION_SUCCESSFUL=0

    while [ $MODULE_RETRIES -gt 0 ];
    do
        MODULE_FILE="${MODULE_NAME}.sh"
        MODULE_PATH="${MODULES_PATH}/${MODULE_FILE}"

        log_i "Starting <${MODULE_NAME}>, retry <$(($MODULE_EXECUTION_MAX_RETRIES - $MODULE_RETRIES + 1))> of <${MODULE_EXECUTION_MAX_RETRIES}>"

        log_set_message_prefix "${MODULE_NAME}"

        set +e
        MODULE_CONTENT=$(cat $MODULE_PATH)

        bash --noprofile --norc -e <<TRY
            . ${CLUSTER_NODE_INIT_DIR}/functions.sh
            . ${CONFIG_PATH}
            LOG_MESSAGE_PREFIX="${LOG_MESSAGE_PREFIX}"
            $(cat $MODULE_PATH)
TRY
        MODULE_EXIT_CODE=$?

        set -e

        log_clear_message_prefix

        if [ $MODULE_EXIT_CODE -ne 0 ];
        then
            log_e "Module execution failed"
            MODULE_RETRIES=$(($MODULE_RETRIES - 1))

            if [ $MODULE_RETRIES = 0 ];
            then
                break
            fi

            log_e "Retrying the module in <${MODULE_EXECUTION_RETRY_WAIT}> seconds"
            sleep $MODULE_EXECUTION_RETRY_WAIT
            continue
        fi

        log_i "Module executed successfully"
        MODULE_EXECUTION_SUCCESSFUL=1

        break
    done

    if [ $MODULE_EXECUTION_SUCCESSFUL == 0 ];
    then
        fatal "Failed to execute the module <${MODULE_NAME}>, unable to continue"
    fi
done
