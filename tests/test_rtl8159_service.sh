#!/bin/sh
set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SERVICE_SCRIPT="${PROJECT_ROOT}/qpkg/RTL8159_Driver/shared/RTL8159_Driver.sh"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/rtl8159-service-test.XXXXXX")
MOCK_BIN="${TEST_ROOT}/mock-bin"
PASS_COUNT=0

cleanup() {
    rm -rf "${TEST_ROOT}"
}
trap cleanup EXIT HUP INT TERM

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_equal() {
    ASSERT_EXPECTED="$1"
    ASSERT_ACTUAL="$2"
    ASSERT_MESSAGE="$3"
    [ "${ASSERT_EXPECTED}" = "${ASSERT_ACTUAL}" ] ||
        fail "${ASSERT_MESSAGE}: expected [${ASSERT_EXPECTED}], got [${ASSERT_ACTUAL}]"
}

assert_success() {
    [ "${TEST_RC}" -eq 0 ] || fail "$1: expected success, rc=${TEST_RC}, output=${TEST_OUTPUT}"
}

assert_failure() {
    [ "${TEST_RC}" -ne 0 ] || fail "$1: expected failure, output=${TEST_OUTPUT}"
}

assert_output_contains() {
    case "${TEST_OUTPUT}" in
        *"$1"*) ;;
        *) fail "output does not contain [$1]: ${TEST_OUTPUT}" ;;
    esac
}

pass() {
    PASS_COUNT=$((PASS_COUNT + 1))
    echo "ok ${PASS_COUNT} - $1"
}

mkdir -p "${MOCK_BIN}"
cat > "${TEST_ROOT}/mock-command" <<'MOCK'
#!/bin/sh
set -eu

MOCK_COMMAND=${0##*/}

write_loaded_src() {
    rm -rf "${RTL8159_SYS_MODULE_ROOT}/r8152"
    if [ -n "$1" ]; then
        mkdir -p "${RTL8159_SYS_MODULE_ROOT}/r8152"
        printf '%s\n' "$1" > "${RTL8159_SYS_MODULE_ROOT}/r8152/srcversion"
    fi
}

case "${MOCK_COMMAND}" in
    uname)
        case "${1:-}" in
            -r) printf '%s\n' "${MOCK_UNAME_R}" ;;
            -m) printf '%s\n' "${MOCK_UNAME_M}" ;;
            *) exit 1 ;;
        esac
        ;;

    modinfo)
        if [ "${1:-}" = "-n" ] && [ "${2:-}" = "r8152" ]; then
            printf '%s\n' "${MOCK_STOCK_PATH}"
        elif [ "${1:-}" = "-F" ]; then
            case "${3:-}" in
                "${MOCK_STOCK_PATH}")
                    case "${2:-}" in
                        vermagic) printf '%s\n' "${MOCK_STOCK_VERMAGIC}" ;;
                        srcversion) printf '%s\n' "${MOCK_STOCK_SRC}" ;;
                        *) exit 1 ;;
                    esac
                    ;;
                *)
                    case "${2:-}" in
                        vermagic) printf '%s\n' "${MOCK_FILE_VERMAGIC}" ;;
                        srcversion) printf '%s\n' "${MOCK_FILE_SRC}" ;;
                        *) exit 1 ;;
                    esac
                    ;;
            esac
        else
            exit 1
        fi
        ;;

    strings)
        printf 'vermagic=%s\nsrcversion=%s\n' "${MOCK_FILE_VERMAGIC}" "${MOCK_FILE_SRC}"
        ;;

    lsmod)
        printf 'Module Size Used by\n'
        case "$(cat "${MOCK_STATE}")" in
            stock|qpkg) printf 'r8152 123 0\n' ;;
        esac
        ;;

    rmmod)
        printf 'rmmod %s\n' "$*" >> "${MOCK_TRACE}"
        [ "${MOCK_RMMOD_RC}" -eq 0 ] || exit "${MOCK_RMMOD_RC}"
        printf 'none\n' > "${MOCK_STATE}"
        write_loaded_src ""
        ;;

    insmod)
        printf 'insmod %s\n' "$*" >> "${MOCK_TRACE}"
        if [ "${1:-}" = "${MOCK_STOCK_PATH}" ]; then
            [ "${MOCK_STOCK_INSMOD_RC}" -eq 0 ] || exit "${MOCK_STOCK_INSMOD_RC}"
            printf 'stock\n' > "${MOCK_STATE}"
            write_loaded_src "${MOCK_LOADED_SRC_AFTER_STOCK_INSMOD}"
        else
            [ "${MOCK_INSMOD_RC}" -eq 0 ] || exit "${MOCK_INSMOD_RC}"
            printf 'qpkg\n' > "${MOCK_STATE}"
            write_loaded_src "${MOCK_LOADED_SRC_AFTER_INSMOD}"
        fi
        ;;

    modprobe)
        printf 'modprobe %s\n' "$*" >> "${MOCK_TRACE}"
        if [ "${1:-}" = "-r" ]; then
            printf 'none\n' > "${MOCK_STATE}"
            write_loaded_src ""
            exit 0
        fi
        [ "${MOCK_MODPROBE_RC}" -eq 0 ] || exit "${MOCK_MODPROBE_RC}"
        printf 'stock\n' > "${MOCK_STATE}"
        write_loaded_src "${MOCK_STOCK_SRC}"
        ;;

    *)
        echo "Unexpected mock command: ${MOCK_COMMAND}" >&2
        exit 1
        ;;
esac
MOCK

for MOCK_NAME in uname modinfo strings lsmod rmmod insmod modprobe; do
    cp "${TEST_ROOT}/mock-command" "${MOCK_BIN}/${MOCK_NAME}"
    chmod +x "${MOCK_BIN}/${MOCK_NAME}"
done

new_case() {
    CASE_DIR="${TEST_ROOT}/$1"
    QPKG_DIR="${CASE_DIR}/RTL8159_Driver"
    SYS_MODULE_DIR="${CASE_DIR}/sys/module"
    MOCK_STATE="${CASE_DIR}/state"
    MOCK_TRACE="${CASE_DIR}/trace"
    MOCK_STOCK_PATH="${CASE_DIR}/stock/r8152.ko"

    mkdir -p "${QPKG_DIR}" "${SYS_MODULE_DIR}" "$(dirname "${MOCK_STOCK_PATH}")"
    : > "${QPKG_DIR}/r8152.ko"
    : > "${MOCK_STOCK_PATH}"
    : > "${MOCK_TRACE}"

    MOCK_UNAME_R="5.10.60-qnap"
    MOCK_UNAME_M="x86_64"
    MOCK_FILE_VERMAGIC="5.10.60-qnap SMP mod_unload"
    MOCK_FILE_SRC="QPKG-SRC"
    MOCK_STOCK_SRC="STOCK-SRC"
    MOCK_STOCK_VERMAGIC="5.10.60-qnap SMP mod_unload"
    MOCK_LOADED_SRC_AFTER_INSMOD="${MOCK_FILE_SRC}"
    MOCK_LOADED_SRC_AFTER_STOCK_INSMOD="${MOCK_STOCK_SRC}"
    MOCK_RMMOD_RC=0
    MOCK_INSMOD_RC=0
    MOCK_STOCK_INSMOD_RC=0
    MOCK_MODPROBE_RC=0

    export MOCK_STATE MOCK_TRACE MOCK_UNAME_R MOCK_UNAME_M
    export MOCK_FILE_VERMAGIC MOCK_FILE_SRC MOCK_STOCK_SRC
    export MOCK_STOCK_PATH MOCK_STOCK_VERMAGIC
    export MOCK_LOADED_SRC_AFTER_INSMOD MOCK_RMMOD_RC
    export MOCK_LOADED_SRC_AFTER_STOCK_INSMOD
    export MOCK_STOCK_INSMOD_RC
    export MOCK_INSMOD_RC MOCK_MODPROBE_RC
    export RTL8159_SYS_MODULE_ROOT="${SYS_MODULE_DIR}"
    export RTL8159_TEST_QPKG_ROOT="${QPKG_DIR}"
    export RTL8159_SKIP_ENABLE_CHECK=TRUE
    export RTL8159_RC_LOCAL="${CASE_DIR}/rc.local"
    export RTL8159_AUTORUN_CONF="${CASE_DIR}/autorun.conf"
    unset RTL8159_QPKG_ROOT
}

set_state() {
    printf '%s\n' "$1" > "${MOCK_STATE}"
    rm -rf "${RTL8159_SYS_MODULE_ROOT}/r8152"
    if [ "$1" != "none" ]; then
        mkdir -p "${RTL8159_SYS_MODULE_ROOT}/r8152"
        printf '%s\n' "$2" > "${RTL8159_SYS_MODULE_ROOT}/r8152/srcversion"
    fi
}

run_service() {
    set +e
    TEST_OUTPUT=$(PATH="${MOCK_BIN}:${PATH}" sh "${SERVICE_SCRIPT}" "$1" 2>&1)
    TEST_RC=$?
    set -e
}

action_trace() {
    grep -E '^(rmmod|insmod|modprobe) ' "${MOCK_TRACE}" || true
}

new_case production-root-override
unset RTL8159_TEST_QPKG_ROOT
export RTL8159_QPKG_ROOT="${QPKG_DIR}"
run_service validate
assert_success "production root override"
assert_equal "" "$(action_trace)" "validation must not mutate modules"
pass "fresh-install validation accepts the QDK-provided QPKG root"

new_case vermagic-mismatch
set_state stock "${MOCK_STOCK_SRC}"
MOCK_UNAME_R="6.6.32-qnap"
export MOCK_UNAME_R
run_service start
assert_failure "vermagic mismatch"
assert_equal "stock" "$(cat "${MOCK_STATE}")" "stock state must be preserved"
assert_equal "" "$(action_trace)" "mismatch must not mutate modules"
pass "vermagic mismatch preserves the stock module"

new_case insmod-failure
set_state stock "${MOCK_STOCK_SRC}"
MOCK_INSMOD_RC=1
export MOCK_INSMOD_RC
run_service start
assert_failure "insmod failure"
EXPECTED_ACTIONS=$(printf 'rmmod r8152\ninsmod %s/r8152.ko\nmodprobe r8152' "${QPKG_DIR}")
assert_equal "${EXPECTED_ACTIONS}" "$(action_trace)" "fallback action order"
assert_equal "stock" "$(cat "${MOCK_STATE}")" "stock module must be restored"
pass "insmod failure restores stock and remains a failure"

new_case successful-start
set_state stock "${MOCK_STOCK_SRC}"
run_service start
assert_success "successful start"
EXPECTED_ACTIONS=$(printf 'rmmod r8152\ninsmod %s/r8152.ko' "${QPKG_DIR}")
assert_equal "${EXPECTED_ACTIONS}" "$(action_trace)" "successful start action order"
assert_equal "qpkg" "$(cat "${MOCK_STATE}")" "QPKG module must remain loaded"
assert_output_contains "srcversion ${MOCK_FILE_SRC}"
pass "successful start verifies srcversion"

new_case srcversion-mismatch
set_state stock "${MOCK_STOCK_SRC}"
MOCK_LOADED_SRC_AFTER_INSMOD="WRONG-SRC"
export MOCK_LOADED_SRC_AFTER_INSMOD
run_service start
assert_failure "srcversion mismatch"
EXPECTED_ACTIONS=$(printf 'rmmod r8152\ninsmod %s/r8152.ko\nrmmod r8152\nmodprobe r8152' "${QPKG_DIR}")
assert_equal "${EXPECTED_ACTIONS}" "$(action_trace)" "srcversion rollback order"
assert_equal "stock" "$(cat "${MOCK_STATE}")" "stock module must be restored after mismatch"
pass "srcversion mismatch rolls back"

new_case stop-stock
set_state stock "${MOCK_STOCK_SRC}"
run_service stop
assert_success "stop with stock"
assert_equal "" "$(action_trace)" "stop must not mutate the stock module"
assert_equal "stock" "$(cat "${MOCK_STATE}")" "stop must preserve stock"
pass "stop leaves the active stock module untouched"

new_case stop-qpkg
set_state qpkg "${MOCK_FILE_SRC}"
run_service stop
assert_success "stop with QPKG module"
EXPECTED_ACTIONS=$(printf 'rmmod r8152\nmodprobe r8152')
assert_equal "${EXPECTED_ACTIONS}" "$(action_trace)" "stop action order"
assert_equal "stock" "$(cat "${MOCK_STATE}")" "stop must restore stock"
pass "stop replaces the QPKG module with verified stock"

new_case restart-qpkg
set_state qpkg "${MOCK_FILE_SRC}"
run_service restart
assert_success "restart with QPKG module"
EXPECTED_ACTIONS=$(printf 'rmmod r8152\nmodprobe r8152\nrmmod r8152\ninsmod %s/r8152.ko' "${QPKG_DIR}")
assert_equal "${EXPECTED_ACTIONS}" "$(action_trace)" "restart action order"
assert_equal "qpkg" "$(cat "${MOCK_STATE}")" "restart must reload the QPKG module"
pass "restart performs a verified stock handoff and QPKG reload"

new_case remove-qpkg
set_state qpkg "${MOCK_FILE_SRC}"
run_service remove
assert_success "remove QPKG module"
EXPECTED_ACTIONS=$(printf 'rmmod r8152\nmodprobe r8152')
assert_equal "${EXPECTED_ACTIONS}" "$(action_trace)" "remove action order"
assert_equal "stock" "$(cat "${MOCK_STATE}")" "remove must restore stock"
pass "remove unloads only the QPKG module and restores stock"

new_case remove-stock
set_state stock "${MOCK_STOCK_SRC}"
run_service remove
assert_success "remove with stock already loaded"
assert_equal "" "$(action_trace)" "remove must not unload an existing stock module"
assert_equal "stock" "$(cat "${MOCK_STATE}")" "stock module must remain loaded"
pass "remove leaves an existing stock module untouched"

new_case unknown-active
set_state stock "UNKNOWN-SRC"
run_service start
assert_failure "unknown active module"
assert_equal "" "$(action_trace)" "unknown module must not be unloaded"
assert_equal "stock" "$(cat "${MOCK_STATE}")" "unknown active module state must be preserved"
pass "unknown active module is never unloaded"

new_case cleanup-legacy
LEGACY_COMMAND="rmmod r8152 2>/dev/null; insmod /share/OLD_DATA/.qpkg/RTL8159_Driver/r8152.ko 2>/dev/null"
{
    echo '# user line'
    echo '# RTL8159 Driver auto-load (with cache clear)'
    echo "${LEGACY_COMMAND}"
    echo 'echo keep-me'
} > "${RTL8159_RC_LOCAL}"
{
    echo 'echo keep-this-too'
    echo "${LEGACY_COMMAND} # RTL8159 Driver (forced reload)"
} > "${RTL8159_AUTORUN_CONF}"
run_service cleanup
assert_success "legacy cleanup"
assert_equal "$(printf '# user line\necho keep-me')" "$(cat "${RTL8159_RC_LOCAL}")" "rc.local cleanup"
assert_equal "echo keep-this-too" "$(cat "${RTL8159_AUTORUN_CONF}")" "autorun cleanup"
pass "legacy cleanup removes only exact package-generated lines"

new_case remove-stock-restore-failure
set_state qpkg "${MOCK_FILE_SRC}"
MOCK_MODPROBE_RC=1
MOCK_STOCK_INSMOD_RC=1
export MOCK_MODPROBE_RC
export MOCK_STOCK_INSMOD_RC
run_service remove
assert_failure "remove stock restore failure"
EXPECTED_ACTIONS=$(printf 'rmmod r8152\nmodprobe r8152\ninsmod %s\ninsmod %s/r8152.ko' "${MOCK_STOCK_PATH}" "${QPKG_DIR}")
assert_equal "${EXPECTED_ACTIONS}" "$(action_trace)" "QPKG recovery action order"
assert_equal "qpkg" "$(cat "${MOCK_STATE}")" "working QPKG module must be recovered"
pass "failed stock restore puts the QPKG driver back"

new_case absolute-stock-identity-mismatch
set_state qpkg "${MOCK_FILE_SRC}"
MOCK_MODPROBE_RC=1
MOCK_LOADED_SRC_AFTER_STOCK_INSMOD="WRONG-STOCK-SRC"
export MOCK_MODPROBE_RC MOCK_LOADED_SRC_AFTER_STOCK_INSMOD
run_service remove
assert_failure "absolute stock identity mismatch"
EXPECTED_ACTIONS=$(printf 'rmmod r8152\nmodprobe r8152\ninsmod %s\nrmmod r8152\ninsmod %s/r8152.ko' "${MOCK_STOCK_PATH}" "${QPKG_DIR}")
assert_equal "${EXPECTED_ACTIONS}" "$(action_trace)" "unverified stock cleanup order"
assert_equal "qpkg" "$(cat "${MOCK_STATE}")" "unverified stock must be replaced by QPKG"
pass "unverified absolute stock load is removed before QPKG recovery"

new_case qpkg-recovery-identity-mismatch
set_state qpkg "${MOCK_FILE_SRC}"
MOCK_MODPROBE_RC=1
MOCK_STOCK_INSMOD_RC=1
MOCK_LOADED_SRC_AFTER_INSMOD="WRONG-QPKG-SRC"
export MOCK_MODPROBE_RC MOCK_STOCK_INSMOD_RC MOCK_LOADED_SRC_AFTER_INSMOD
run_service remove
assert_failure "QPKG recovery identity mismatch"
EXPECTED_ACTIONS=$(printf 'rmmod r8152\nmodprobe r8152\ninsmod %s\ninsmod %s/r8152.ko\nrmmod r8152' "${MOCK_STOCK_PATH}" "${QPKG_DIR}")
assert_equal "${EXPECTED_ACTIONS}" "$(action_trace)" "unverified QPKG cleanup order"
assert_equal "none" "$(cat "${MOCK_STATE}")" "unverified QPKG recovery must be unloaded"
pass "unverified QPKG recovery never remains loaded"

new_case fallback-failure
set_state stock "${MOCK_STOCK_SRC}"
MOCK_INSMOD_RC=1
MOCK_MODPROBE_RC=1
MOCK_STOCK_INSMOD_RC=1
export MOCK_INSMOD_RC MOCK_MODPROBE_RC MOCK_STOCK_INSMOD_RC
run_service start
assert_failure "fallback failure"
assert_equal "2" "${TEST_RC}" "fallback failure exit code"
assert_equal "none" "$(cat "${MOCK_STATE}")" "failed fallback must be visible"
assert_output_contains "Unable to restore the verified stock r8152 module"
pass "fallback failure is reported and returns non-zero"

echo "1..${PASS_COUNT}"
