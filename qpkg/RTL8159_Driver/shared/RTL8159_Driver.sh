#!/bin/sh

PATH="${PATH:-/bin}:/sbin:/usr/sbin:/usr/bin"
export PATH

CONF="${RTL8159_TEST_CONF:-/etc/config/qpkg.conf}"
QPKG_NAME="RTL8159_Driver"
SYS_MODULE_ROOT="${RTL8159_SYS_MODULE_ROOT:-/sys/module}"
RC_LOCAL="${RTL8159_RC_LOCAL:-/etc/rc.local}"
AUTORUN_CONF="${RTL8159_AUTORUN_CONF:-/etc/config/autorun.conf}"

if [ -n "${RTL8159_QPKG_ROOT:-}" ]; then
    QPKG_ROOT="${RTL8159_QPKG_ROOT}"
elif [ -n "${RTL8159_TEST_QPKG_ROOT:-}" ]; then
    QPKG_ROOT="${RTL8159_TEST_QPKG_ROOT}"
else
    QPKG_ROOT=$(/sbin/getcfg "${QPKG_NAME}" Install_Path -f "${CONF}")
fi

DRIVER_PATH="${QPKG_ROOT}/r8152.ko"
export QNAP_QPKG="${QPKG_NAME}"

module_field() {
    RTL8159_FIELD="$1"
    RTL8159_MODULE="$2"
    RTL8159_VALUE=""

    if command -v modinfo >/dev/null 2>&1; then
        RTL8159_VALUE=$(modinfo -F "${RTL8159_FIELD}" "${RTL8159_MODULE}" 2>/dev/null | head -1)
    fi

    if [ -z "${RTL8159_VALUE}" ] && command -v strings >/dev/null 2>&1; then
        RTL8159_VALUE=$(strings "${RTL8159_MODULE}" 2>/dev/null |
            sed -n "s/^${RTL8159_FIELD}=//p" | head -1)
    fi

    printf '%s\n' "${RTL8159_VALUE}"
}

module_loaded() {
    lsmod 2>/dev/null | grep -q '^r8152[[:space:]]'
}

loaded_srcversion() {
    if [ -r "${SYS_MODULE_ROOT}/r8152/srcversion" ]; then
        tr -d '\r\n' < "${SYS_MODULE_ROOT}/r8152/srcversion"
    fi
}

stock_driver_path() {
    RTL8159_RUNNING_KERNEL=$(uname -r)
    RTL8159_MODULE_DIR="/lib/modules/${RTL8159_RUNNING_KERNEL}"
    RTL8159_STOCK_CANDIDATE=""

    if command -v modinfo >/dev/null 2>&1; then
        RTL8159_STOCK_CANDIDATE=$(modinfo -n r8152 2>/dev/null | head -1)
        case "${RTL8159_STOCK_CANDIDATE}" in
            ""|"(builtin)")
                RTL8159_STOCK_CANDIDATE=""
                ;;
            /*)
                ;;
            *)
                RTL8159_STOCK_CANDIDATE="${RTL8159_MODULE_DIR}/${RTL8159_STOCK_CANDIDATE}"
                ;;
        esac
    fi

    if [ -z "${RTL8159_STOCK_CANDIDATE}" ] &&
       [ -r "${RTL8159_MODULE_DIR}/modules.dep" ]; then
        RTL8159_STOCK_CANDIDATE=$(awk -F: '$1 ~ /(^|\/)r8152\.ko(\.(xz|gz|zst))?$/ { print $1; exit }' "${RTL8159_MODULE_DIR}/modules.dep")
        if [ -n "${RTL8159_STOCK_CANDIDATE}" ]; then
            case "${RTL8159_STOCK_CANDIDATE}" in
                /*) ;;
                *) RTL8159_STOCK_CANDIDATE="${RTL8159_MODULE_DIR}/${RTL8159_STOCK_CANDIDATE}" ;;
            esac
        fi
    fi

    if [ -z "${RTL8159_STOCK_CANDIDATE}" ]; then
        RTL8159_STOCK_CANDIDATE=$(find "${RTL8159_MODULE_DIR}" \( -name 'r8152.ko' -o -name 'r8152.ko.xz' -o -name 'r8152.ko.gz' -o -name 'r8152.ko.zst' \) 2>/dev/null | head -1)
    fi

    if [ -n "${RTL8159_STOCK_CANDIDATE}" ] &&
       [ ! -r "${RTL8159_STOCK_CANDIDATE}" ]; then
        RTL8159_STOCK_CANDIDATE=""
    fi

    printf '%s\n' "${RTL8159_STOCK_CANDIDATE}"
}

capture_stock_identity() {
    RTL8159_STOCK_PATH=$(stock_driver_path)
    if [ -z "${RTL8159_STOCK_PATH}" ]; then
        echo "ERROR: Cannot locate the stock r8152 module; refusing an unsafe switch." >&2
        return 1
    fi

    RTL8159_STOCK_SRC=$(module_field srcversion "${RTL8159_STOCK_PATH}")
    RTL8159_STOCK_VERMAGIC=$(module_field vermagic "${RTL8159_STOCK_PATH}")
    RTL8159_STOCK_KERNEL=${RTL8159_STOCK_VERMAGIC%% *}
    RTL8159_RUNNING_KERNEL=$(uname -r)

    if [ -z "${RTL8159_STOCK_SRC}" ] ||
       [ "${RTL8159_STOCK_KERNEL}" != "${RTL8159_RUNNING_KERNEL}" ]; then
        echo "ERROR: Cannot verify the stock r8152 module identity." >&2
        return 1
    fi

    return 0
}

loaded_is_stock() {
    module_loaded || return 1
    [ -n "${RTL8159_STOCK_SRC:-}" ] || capture_stock_identity || return 1
    RTL8159_CURRENT_SRC=$(loaded_srcversion)
    [ -n "${RTL8159_CURRENT_SRC}" ] &&
        [ "${RTL8159_CURRENT_SRC}" = "${RTL8159_STOCK_SRC}" ]
}

cleanup_legacy_autoload() {
    RTL8159_LEGACY_COMMENT="# RTL8159 Driver auto-load (with cache clear)"
    RTL8159_CLEANUP_FAILED=0

    for RTL8159_LEGACY_FILE in "${RC_LOCAL}" "${AUTORUN_CONF}"; do
        [ -e "${RTL8159_LEGACY_FILE}" ] || continue

        if [ ! -r "${RTL8159_LEGACY_FILE}" ]; then
            echo "ERROR: Cannot inspect ${RTL8159_LEGACY_FILE} for legacy auto-load entries." >&2
            RTL8159_CLEANUP_FAILED=1
            continue
        fi

        RTL8159_LEGACY_TMP=$(mktemp "${TMPDIR:-/tmp}/rtl8159-autoload.XXXXXX") || {
            echo "ERROR: Could not create a temporary cleanup file." >&2
            RTL8159_CLEANUP_FAILED=1
            continue
        }
        RTL8159_LEGACY_CHANGED=0

        if ! {
            while IFS= read -r RTL8159_LEGACY_LINE || [ -n "${RTL8159_LEGACY_LINE}" ]; do
                RTL8159_LEGACY_MATCH=0
                if [ "${RTL8159_LEGACY_LINE}" = "${RTL8159_LEGACY_COMMENT}" ]; then
                    RTL8159_LEGACY_MATCH=1
                else
                    case "${RTL8159_LEGACY_LINE}" in
                        "rmmod r8152 2>/dev/null; insmod "*"/RTL8159_Driver/r8152.ko 2>/dev/null")
                            RTL8159_LEGACY_MATCH=1
                            ;;
                        "rmmod r8152 2>/dev/null; insmod "*"/RTL8159_Driver/r8152.ko 2>/dev/null # RTL8159 Driver (forced reload)")
                            RTL8159_LEGACY_MATCH=1
                            ;;
                    esac
                fi

                if [ "${RTL8159_LEGACY_MATCH}" -eq 1 ]; then
                    RTL8159_LEGACY_CHANGED=1
                    continue
                fi
                printf '%s\n' "${RTL8159_LEGACY_LINE}"
            done
        } < "${RTL8159_LEGACY_FILE}" > "${RTL8159_LEGACY_TMP}"; then
            rm -f "${RTL8159_LEGACY_TMP}"
            echo "ERROR: Could not read ${RTL8159_LEGACY_FILE} completely." >&2
            RTL8159_CLEANUP_FAILED=1
            continue
        fi

        if [ "${RTL8159_LEGACY_CHANGED}" -eq 0 ]; then
            rm -f "${RTL8159_LEGACY_TMP}"
        elif [ ! -w "${RTL8159_LEGACY_FILE}" ]; then
            rm -f "${RTL8159_LEGACY_TMP}"
            echo "ERROR: Legacy auto-load entries remain in non-writable ${RTL8159_LEGACY_FILE}." >&2
            RTL8159_CLEANUP_FAILED=1
        elif cat "${RTL8159_LEGACY_TMP}" > "${RTL8159_LEGACY_FILE}"; then
            rm -f "${RTL8159_LEGACY_TMP}"
            echo "Removed legacy auto-load entries from ${RTL8159_LEGACY_FILE}."
        else
            rm -f "${RTL8159_LEGACY_TMP}"
            echo "ERROR: Could not clean ${RTL8159_LEGACY_FILE}." >&2
            RTL8159_CLEANUP_FAILED=1
        fi
    done

    if [ -f "${QPKG_ROOT}/rtl8159-autoload.sh" ] &&
       ! rm -f "${QPKG_ROOT}/rtl8159-autoload.sh"; then
        echo "ERROR: Could not remove legacy rtl8159-autoload.sh." >&2
        RTL8159_CLEANUP_FAILED=1
    fi

    return "${RTL8159_CLEANUP_FAILED}"
}

validate_driver() {
    if [ -z "${QPKG_ROOT}" ] || [ ! -r "${DRIVER_PATH}" ]; then
        echo "ERROR: QPKG driver not found: ${DRIVER_PATH}" >&2
        return 1
    fi

    RTL8159_RUNNING_ARCH=$(uname -m)
    if [ "${RTL8159_RUNNING_ARCH}" != "x86_64" ]; then
        echo "ERROR: Unsupported architecture: ${RTL8159_RUNNING_ARCH}" >&2
        return 1
    fi

    RTL8159_RUNNING_KERNEL=$(uname -r)
    RTL8159_VERMAGIC=$(module_field vermagic "${DRIVER_PATH}")
    RTL8159_MODULE_KERNEL=${RTL8159_VERMAGIC%% *}

    if [ -z "${RTL8159_MODULE_KERNEL}" ]; then
        echo "ERROR: Cannot read driver vermagic; refusing to unload the current module." >&2
        return 1
    fi

    if [ "${RTL8159_MODULE_KERNEL}" != "${RTL8159_RUNNING_KERNEL}" ]; then
        echo "ERROR: Driver/kernel mismatch: module=${RTL8159_MODULE_KERNEL}, running=${RTL8159_RUNNING_KERNEL}" >&2
        echo "The currently loaded r8152 module was left untouched." >&2
        return 1
    fi

    RTL8159_EXPECTED_SRC=$(module_field srcversion "${DRIVER_PATH}")
    if [ -z "${RTL8159_EXPECTED_SRC}" ]; then
        echo "ERROR: Cannot read driver srcversion; refusing an unverifiable load." >&2
        return 1
    fi

    return 0
}

qpkg_driver_loaded() {
    module_loaded || return 1

    RTL8159_FILE_SRC=$(module_field srcversion "${DRIVER_PATH}")
    RTL8159_LOADED_SRC=$(loaded_srcversion)
    [ -n "${RTL8159_FILE_SRC}" ] &&
        [ -n "${RTL8159_LOADED_SRC}" ] &&
        [ "${RTL8159_FILE_SRC}" = "${RTL8159_LOADED_SRC}" ]
}

unload_r8152() {
    module_loaded || return 0

    if ! rmmod r8152 2>/dev/null && ! modprobe -r r8152 2>/dev/null; then
        echo "ERROR: Could not unload the currently loaded r8152 module." >&2
        return 1
    fi

    if module_loaded; then
        echo "ERROR: r8152 is still loaded after the unload request." >&2
        return 1
    fi

    return 0
}

restore_stock_driver() {
    [ -n "${RTL8159_STOCK_SRC:-}" ] || capture_stock_identity || return 1

    if module_loaded; then
        if loaded_is_stock; then
            return 0
        fi
        echo "ERROR: An unexpected r8152 module is loaded; stock restore was not attempted." >&2
        return 1
    fi

    echo "Restoring the stock r8152 module..."
    if modprobe r8152 2>/dev/null && module_loaded &&
       [ "$(loaded_srcversion)" = "${RTL8159_STOCK_SRC}" ]; then
        echo "Stock r8152 module restored (srcversion ${RTL8159_STOCK_SRC})."
        return 0
    fi

    if module_loaded; then
        unload_r8152 || true
    fi

    case "${RTL8159_STOCK_PATH}" in
        *.ko)
            echo "modprobe did not restore the verified stock module; trying its absolute path..."
            if insmod "${RTL8159_STOCK_PATH}" 2>/dev/null && module_loaded &&
               [ "$(loaded_srcversion)" = "${RTL8159_STOCK_SRC}" ]; then
                echo "Stock r8152 module restored from ${RTL8159_STOCK_PATH}."
                return 0
            fi
            ;;
        *)
            echo "Stock module is compressed; direct insmod fallback is unavailable." >&2
            ;;
    esac

    # A direct load that produced the wrong identity must not block the
    # caller from restoring the QPKG module.
    if module_loaded; then
        unload_r8152 || true
    fi

    echo "ERROR: Unable to restore the verified stock r8152 module." >&2
    return 1
}

restore_qpkg_driver() {
    if module_loaded; then
        return 1
    fi

    RTL8159_QPKG_SRC=$(module_field srcversion "${DRIVER_PATH}")
    [ -n "${RTL8159_QPKG_SRC}" ] || return 1

    if ! insmod "${DRIVER_PATH}" 2>/dev/null; then
        module_loaded && unload_r8152 || true
        return 1
    fi

    if module_loaded &&
       [ "$(loaded_srcversion)" = "${RTL8159_QPKG_SRC}" ]; then
        return 0
    fi

    module_loaded && unload_r8152 || true
    return 1
}

start_driver() {
    validate_driver || return 1

    if qpkg_driver_loaded; then
        echo "${QPKG_NAME} is already running with the verified QPKG driver."
        return 0
    fi

    # A verified stock file is required before any active module is replaced.
    capture_stock_identity || return 1

    if module_loaded; then
        if ! loaded_is_stock; then
            echo "ERROR: The active r8152 module matches neither stock nor this QPKG; refusing to unload it." >&2
            return 1
        fi
        echo "Unloading the verified stock r8152 module..."
        unload_r8152 || return 1
    fi

    echo "Loading r8152 from ${DRIVER_PATH}..."
    if ! insmod "${DRIVER_PATH}" 2>/dev/null; then
        echo "ERROR: QPKG driver load failed; check dmesg." >&2
        if restore_stock_driver; then
            return 1
        fi
        return 2
    fi

    RTL8159_LOADED_SRC=$(loaded_srcversion)
    if ! module_loaded || [ "${RTL8159_LOADED_SRC}" != "${RTL8159_EXPECTED_SRC}" ]; then
        echo "ERROR: Loaded driver srcversion verification failed." >&2
        unload_r8152 || true
        if restore_stock_driver; then
            return 1
        fi
        return 2
    fi

    echo "${QPKG_NAME} started successfully (srcversion ${RTL8159_LOADED_SRC})."
    return 0
}

remove_driver() {
    if module_loaded && capture_stock_identity; then
        RTL8159_REMOVE_QPKG_SRC=$(module_field srcversion "${DRIVER_PATH}")
        RTL8159_REMOVE_LOADED_SRC=$(loaded_srcversion)
        if [ -n "${RTL8159_REMOVE_QPKG_SRC}" ] &&
           [ "${RTL8159_REMOVE_QPKG_SRC}" = "${RTL8159_STOCK_SRC}" ] &&
           [ "${RTL8159_REMOVE_LOADED_SRC}" = "${RTL8159_STOCK_SRC}" ]; then
            echo "Loaded r8152 is source-equivalent to both stock and QPKG; leaving it active."
            cleanup_legacy_autoload || return 1
            return 0
        fi
    fi

    if qpkg_driver_loaded; then
        # Do not unload the working QPKG driver unless a verifiable stock module
        # is ready to take its place.
        capture_stock_identity || return 1
        echo "Unloading the verified QPKG r8152 module..."
        unload_r8152 || return 1

        if ! restore_stock_driver; then
            echo "ERROR: Stock restore failed; attempting to put the QPKG driver back." >&2
            restore_qpkg_driver || echo "ERROR: QPKG driver recovery also failed." >&2
            return 1
        fi
    elif module_loaded; then
        if capture_stock_identity && loaded_is_stock; then
            echo "The verified stock r8152 module is already active."
        else
            echo "ERROR: The active r8152 module cannot be identified; leaving it and the QPKG files untouched." >&2
            return 1
        fi
    else
        capture_stock_identity || return 1
        restore_stock_driver || return 1
    fi

    cleanup_legacy_autoload || return 1
    return 0
}

case "$1" in
    start)
        if [ "${RTL8159_SKIP_ENABLE_CHECK:-FALSE}" != "TRUE" ]; then
            ENABLED=$(/sbin/getcfg "${QPKG_NAME}" Enable -u -d FALSE -f "${CONF}")
            if [ "${ENABLED}" != "TRUE" ]; then
                echo "${QPKG_NAME} is disabled."
                exit 1
            fi
        fi
        start_driver
        exit $?
        ;;

    stop)
        remove_driver
        exit $?
        ;;

    restart)
        remove_driver || exit $?
        start_driver
        exit $?
        ;;

    remove)
        remove_driver
        exit $?
        ;;

    validate)
        validate_driver
        exit $?
        ;;

    cleanup)
        cleanup_legacy_autoload
        exit $?
        ;;

    status)
        if qpkg_driver_loaded; then
            echo "${QPKG_NAME} is running with the QPKG driver."
            exit 0
        elif module_loaded; then
            echo "r8152 is loaded, but it is not the QPKG driver."
            exit 1
        else
            echo "r8152 is not loaded."
            exit 1
        fi
        ;;

    *)
        echo "Usage: $0 {start|stop|restart|remove|validate|cleanup|status}"
        exit 1
        ;;
esac
