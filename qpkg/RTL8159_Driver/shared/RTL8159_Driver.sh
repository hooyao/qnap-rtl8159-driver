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
    # Driver is loaded during installation via package_routines
    # Nothing to do here at service start
    echo "$QPKG_NAME started (driver is kernel module, always active)"
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
