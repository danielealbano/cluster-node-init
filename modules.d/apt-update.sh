if [ -f /var/cache/apt/pkgcache.bin ];
then
    PKGCACHE_BIN_MOD_TIMESTAMP=$(stat -c %Y /var/cache/apt/pkgcache.bin)
else
    PKGCACHE_BIN_MOD_TIMESTAMP=0
fi

TIMESTAMP_DIFF=$(($(date +%s) - $PKGCACHE_BIN_MOD_TIMESTAMP))

log_i "Apt cache updated <${TIMESTAMP_DIFF}> seconds ago"

if [ $TIMESTAMP_DIFF -gt $APT_UPDATE_PKGCACHE_BIN_LAST_REFRESH_DIFF_IN_S ];
then
    log_i "Updating package cache"
    apt update
else
    log_i "Skipping package cache update, last update less than <${APT_UPDATE_PKGCACHE_BIN_LAST_REFRESH_DIFF_IN_S}> seconds ago"
fi
