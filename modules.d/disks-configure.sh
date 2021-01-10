function disk_exists() {
    local DISK_DEV=$1

    if [ -b "${DISK_DEV}" ]
    then
        return 0
    else
        return 1
    fi
}

function disk_has_partition_table() {
    local DISK_DEV=$1

    PARTITION_TABLE_TYPE="$(parted -s -m ${DISK_DEV} print 2>/dev/null | grep ${DISK_DEV} | cut -d':' -f 6)"
    if [ "${PARTITION_TABLE_TYPE}" == "" ] || [ "${PARTITION_TABLE_TYPE}" == "unknown" ];
    then
        return 1
    else
        return 0
    fi
}

function fstab_has_partition_uuid() {
    local DISK_PARTITION_UUID=$1

    if ! ( cat /etc/fstab 2>&1 | grep "UUID=${DISK_PARTITION_UUID}" >/dev/null );
    then
        return 0
    else
        return 1
    fi
}


LOOP_INDEX=-1
while [ true ];
do
    LOOP_INDEX=$((LOOP_INDEX + 1))
    DISK_DEV=$(get_env_var "DISKS_${LOOP_INDEX}_DEV")
    DISK_PARTITIONS_SKIPPED=0

    if [ -z "${DISK_DEV}" ];
    then
        break;
    fi

    if ! ( disk_exists "${DISK_DEV}" );
    then
        log_w "Disk device <${DISK_DEV}> doesn't exist, skipping"
        continue
    fi

    if ( disk_has_partition_table "${DISK_DEV}" );
    then
        log_i "Disk device <${DISK_DEV}> has a partition table, skipping partition creation"
        DISK_PARTITIONS_SKIPPED=1
    else
        DISK_PARTITION_TABLE_TYPE=$(get_env_var "DISKS_${LOOP_INDEX}_PARTITION_TABLE_TYPE")
        if ! ( parted -s ${DISK_DEV} mklabel msdos );
        then
            fatal "Failed to create an <msdos> partition table on <${DISK_DEV}>"
        fi
    fi

    LOOP_INDEX_PARTITION=-1
    while [ true ];
    do
        LOOP_INDEX_PARTITION=$((LOOP_INDEX_PARTITION + 1))

        DISK_PARTITION_ID="$((${LOOP_INDEX_PARTITION} + 1))"
        DISK_PARTITION_DEV="${DISK_DEV}${DISK_PARTITION_ID}"
        DISK_PARTITION_FS=$(get_env_var "DISKS_${LOOP_INDEX}_PARTITION_${LOOP_INDEX_PARTITION}_FS")
        DISK_PARTITION_SIZE=$(get_env_var "DISKS_${LOOP_INDEX}_PARTITION_${LOOP_INDEX_PARTITION}_SIZE")
        DISK_PARTITION_MOUNT_POINT=$(get_env_var "DISKS_${LOOP_INDEX}_PARTITION_${LOOP_INDEX_PARTITION}_MOUNT_POINT")
        DISK_PARTITION_MKFS_EXTRA_PARAM=$(get_env_var "DISKS_${LOOP_INDEX}_PARTITION_${LOOP_INDEX_PARTITION}_MKFS_EXTRA_PARAM")

        if [ -z "${DISK_PARTITION_FS}" ] || [ -z "${DISK_PARTITION_SIZE}" ] || [ -z "${DISK_PARTITION_MOUNT_POINT}" ];
        then
            break
        fi

        if [ ${DISK_PARTITIONS_SKIPPED} == 0 ];
        then
            # Generate a new uuid for the filesystem, to be used later
            DISK_PARTITION_UUID=$(uuidgen)
            log_i "Creating new partition of size <${DISK_PARTITION_SIZE}> and type <${DISK_PARTITION_FS}> on <${DISK_DEV}>"

            # Creates the partition
            # fdisk is being preferred to create partitions instead of parted, it will not be necessary to deal with the
            # correct partition alignment, fdisk will take care of it
            DISK_PARTITION_SIZE_FSTAB=$([ "${DISK_PARTITION_SIZE}" = "all" ] && echo "" || echo "+${DISK_PARTITION_SIZE}" )
            DISK_PARTITION_TYPE_ID=$([ "${DISK_PARTITION_FS}" = "swap" ] && echo "82" || echo "83" )
            
            # This check is almost useless, if fdisk fails to execute the commands will not terminate with a >0 exit code
            if ! ( (echo n; echo p; echo ""; echo ""; echo "${DISK_PARTITION_SIZE_FSTAB}"; echo w) | fdisk ${DISK_DEV} >/dev/null );
            then
                fatal "Failed to create the partition"
            fi

            if [ ${DISK_PARTITION_ID} == 1 ];
            then
                # This check is almost useless, if fdisk fails to execute the commands will not terminate with a >0 exit code
                if ! ( (echo t; echo "${DISK_PARTITION_TYPE_ID}"; echo w) | fdisk ${DISK_DEV} >/dev/null );
                then
                    fatal "Failed to set the partition type on the partition"
                fi
            else
                # This check is almost useless, if fdisk fails to execute the commands will not terminate with a >0 exit code
                if ! ( (echo t; echo "$(($DISK_PARTITION_ID))"; echo "${DISK_PARTITION_TYPE_ID}"; echo w) | fdisk ${DISK_DEV} >/dev/null );
                then
                    fatal "Failed to set the partition type on the partition"
                fi
            fi
            log_i "Partition created"

            # Creates the filesystem
            log_i "Creating filesystem <${DISK_PARTITION_FS}> with UUID <${DISK_PARTITION_UUID}> on <${DISK_PARTITION_DEV}>"
            if [ "${DISK_PARTITION_FS}" = "swap" ];
            then
                if ! mkswap -U "${DISK_PARTITION_UUID}" ${DISK_PARTITION_MKFS_EXTRA_PARAM} ${DISK_PARTITION_DEV} >/dev/null >/dev/null;
                then
                    fatal "Failed create the swap"
                fi
            else
                if ! mkfs.${DISK_PARTITION_FS} -F -U "${DISK_PARTITION_UUID}" ${DISK_PARTITION_MKFS_EXTRA_PARAM} ${DISK_PARTITION_DEV} >/dev/null >/dev/null;
                then
                    fatal "Failed to create the filesystem"
                fi
            fi
            log_i "Filesystem created"
        fi

        # Creates the mount point if necessary
        if ! [ "${DISK_PARTITION_FS}" = "swap" ];
        then
            if ! [ -d "${DISK_PARTITION_MOUNT_POINT}" ];
            then
                log_i "Creating filesystem mountpoint <${DISK_PARTITION_MOUNT_POINT}> for <${DISK_PARTITION_DEV}>"
                mkdir -p "${DISK_PARTITION_MOUNT_POINT}" 2>&1 >/dev/null
                log_i "Filesystem created"
            fi
        fi

        # Fetch again the UUID for the partition device to be able to update the /etc/fstab even when the partitions
        # are not being recreated because they already exist.
        # No actual check on the partition type or size is performed, the configuration has to be kept in sync!
        DISK_PARTITION_UUID=$(blkid ${DISK_PARTITION_DEV} | sed -n 's/.* UUID=\"\([^\"]*\)\".*/\1/p')

        if [ -z "${DISK_PARTITION_UUID}" ];
        then
            fatal "Failed to retrieve the UUID for ${DISK_PARTITION_DEV}, unable to continue"
        fi

        if fstab_has_partition_uuid "${DISK_PARTITION_UUID}";
        then
            log_i "Adding <${DISK_PARTITION_DEV}> with UUID <${DISK_PARTITION_UUID}> to /etc/fstab"

            # Update fstab
            DISK_PARTITION_MOUNT_POINT_FSTAB=$([ "${DISK_PARTITION_FS}" = "swap" ] && echo "swap" || echo "${DISK_PARTITION_MOUNT_POINT}" )
            echo "# Disk device <${DISK_DEV}>, partition <${DISK_PARTITION_ID}>, size <${DISK_PARTITION_SIZE}>" >> /etc/fstab
            echo "UUID=${DISK_PARTITION_UUID} ${DISK_PARTITION_MOUNT_POINT_FSTAB} ${DISK_PARTITION_FS} defaults,errors=remount-ro 0 0" >> /etc/fstab
        else
            log_i "/etc/fstab already contains a record for <${DISK_PARTITION_DEV}> with UUID <${DISK_PARTITION_UUID}>, skipping"
        fi

        # If the partitions creation hasn't been skipped try to mount them / activate the swap
        if [ ${DISK_PARTITIONS_SKIPPED} == 0 ];
        then
            # Mount the new swap / filesystem
            if [ "${DISK_PARTITION_FS}" = "swap" ];
            then
                log_i "Activating swap for <${DISK_PARTITION_DEV}> with UUID <${DISK_PARTITION_UUID}>"
                if ! swapon "UUID=${DISK_PARTITION_UUID}" >/dev/null;
                then
                    fatal "Failed to activate the swap, unable to continue"
                fi
                log_i "Swap activated"
            else
                log_i "Mounting <${DISK_PARTITION_MOUNT_POINT}> with UUID <${DISK_PARTITION_UUID}>"
                if ! mount "UUID=${DISK_PARTITION_UUID}" >/dev/null;
                then
                    fatal "Failed to mount the volume, unable to continue"
                fi
                log_i "Mounted"
            fi
        fi
    done
done
