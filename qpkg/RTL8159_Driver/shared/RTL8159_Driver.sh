#!/bin/sh
CONF=/etc/config/qpkg.conf
QPKG_NAME="RTL8159_Driver"
QPKG_ROOT=$(/sbin/getcfg $QPKG_NAME Install_Path -f ${CONF})
export QNAP_QPKG=$QPKG_NAME

case "$1" in
  start)
    ENABLED=$(/sbin/getcfg $QPKG_NAME Enable -u -d FALSE -f $CONF)
    if [ "$ENABLED" != "TRUE" ]; then
        echo "$QPKG_NAME is disabled."
        exit 1
    fi

    # Load driver from QPKG directory on startup
    DRIVER_PATH="${QPKG_ROOT}/r8152.ko"

    if [ -f "${DRIVER_PATH}" ]; then
        # Unload old module if loaded
        if lsmod | grep -q "^r8152 "; then
            rmmod r8152 2>/dev/null || true
        fi

        # Load driver from QPKG directory
        echo "Loading r8152 driver from QPKG directory..."
        insmod "${DRIVER_PATH}" 2>/dev/null || true
    fi

    if lsmod | grep -q "^r8152 "; then
        echo "$QPKG_NAME started successfully (driver loaded)"
    else
        echo "$QPKG_NAME started (driver load may have failed, check dmesg)"
    fi
    ;;

  stop)
    # Driver stays loaded as kernel module
    # Don't unload on stop to avoid network interruption
    echo "$QPKG_NAME stopped (driver remains loaded)"
    ;;

  restart)
    $0 stop
    $0 start
    ;;

  remove)
    # Removal is handled by package_routines
    ;;

  *)
    echo "Usage: $0 {start|stop|restart|remove}"
    exit 1
esac

exit 0
