#!/bin/sh
set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ROUTINES_FILE="${PROJECT_ROOT}/qpkg/RTL8159_Driver/package_routines"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/rtl8159-routines-test.XXXXXX")
QPKG_DIR="${TEST_ROOT}/qpkg"
TRACE_FILE="${TEST_ROOT}/service.trace"
PASS_COUNT=0

cleanup() {
    rm -rf "${TEST_ROOT}"
}
trap cleanup EXIT HUP INT TERM

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

pass() {
    PASS_COUNT=$((PASS_COUNT + 1))
    echo "ok ${PASS_COUNT} - $1"
}

assert_equal() {
    [ "$1" = "$2" ] || fail "$3: expected [$1], got [$2]"
}

mkdir -p "${QPKG_DIR}"
: > "${QPKG_DIR}/r8152.ko"
: > "${TRACE_FILE}"

cat > "${QPKG_DIR}/RTL8159_Driver.sh" <<'SERVICE'
#!/bin/sh
[ "${RTL8159_QPKG_ROOT:-}" = "${ROUTINES_EXPECTED_ROOT:-}" ] || exit 8
printf '%s\n' "$1" >> "${ROUTINES_TEST_TRACE}"
case "$1" in
    validate) exit "${ROUTINES_VALIDATE_RC:-0}" ;;
    cleanup) exit "${ROUTINES_CLEANUP_RC:-0}" ;;
    start) exit "${ROUTINES_START_RC:-0}" ;;
    remove) exit "${ROUTINES_REMOVE_RC:-0}" ;;
    *) exit 0 ;;
esac
SERVICE
chmod +x "${QPKG_DIR}/RTL8159_Driver.sh"

SYS_QPKG_DIR="${QPKG_DIR}"
SYS_CPU_ARCH="x86_64"
SYS_QPKG_SERVICE_ENABLED="TRUE"
ROUTINES_TEST_TRACE="${TRACE_FILE}"
ROUTINES_EXPECTED_ROOT="${QPKG_DIR}"
export ROUTINES_TEST_TRACE ROUTINES_EXPECTED_ROOT

log() {
    printf 'log:%s\n' "$*" >> "${TEST_ROOT}/qdk.log"
}

warn_log() {
    printf 'warn:%s\n' "$*" >> "${TEST_ROOT}/qdk.log"
}

err_log() {
    printf 'error:%s\n' "$*" >> "${TEST_ROOT}/qdk.log"
    exit 99
}

# Sourcing must use QDK's SYS_QPKG_DIR and must not require a qpkg.conf entry.
. "${ROUTINES_FILE}"
assert_equal "${QPKG_DIR}/install.log" "${INSTALL_LOG}" "install log path"
pass "fresh-install source uses SYS_QPKG_DIR"

: > "${TRACE_FILE}"
pkg_install
assert_equal "validate" "$(cat "${TRACE_FILE}")" "pkg_install service action"
pass "pkg_install performs static driver validation"

set +e
(
    SYS_QPKG_DIR="${QPKG_DIR}"
    SYS_CPU_ARCH="x86_64"
    SYS_QPKG_SERVICE_ENABLED="TRUE"
    ROUTINES_VALIDATE_RC=1
    export ROUTINES_TEST_TRACE ROUTINES_VALIDATE_RC
    . "${ROUTINES_FILE}"
    pkg_install
) >/dev/null 2>&1
FAIL_RC=$?
set -e
assert_equal "99" "${FAIL_RC}" "err_log must abort validation failure"
pass "validation failure aborts through QDK err_log"

: > "${TRACE_FILE}"
SYS_QPKG_SERVICE_ENABLED="FALSE"
pkg_post_install
assert_equal "cleanup" "$(cat "${TRACE_FILE}")" "disabled package actions"
pass "disabled upgrade does not start the QPKG driver"

set +e
(
    SYS_QPKG_DIR="${QPKG_DIR}"
    SYS_CPU_ARCH="x86_64"
    SYS_QPKG_SERVICE_ENABLED="FALSE"
    ROUTINES_CLEANUP_RC=1
    export ROUTINES_TEST_TRACE ROUTINES_EXPECTED_ROOT ROUTINES_CLEANUP_RC
    . "${ROUTINES_FILE}"
    pkg_post_install
) >/dev/null 2>&1
CLEANUP_RC=$?
set -e
assert_equal "99" "${CLEANUP_RC}" "legacy cleanup failure must abort installation"
pass "legacy auto-load cleanup failure aborts installation"

: > "${TRACE_FILE}"
SYS_QPKG_SERVICE_ENABLED="TRUE"
ROUTINES_START_RC=1
export ROUTINES_START_RC
pkg_post_install
assert_equal "FALSE" "${SYS_QPKG_SERVICE_ENABLED}" "failed start must disable package"
assert_equal "$(printf 'cleanup\nstart')" "$(cat "${TRACE_FILE}")" "enabled package actions"
unset ROUTINES_START_RC
pass "dynamic load failure leaves the package disabled"

set +e
(
    SYS_QPKG_DIR="${QPKG_DIR}"
    SYS_CPU_ARCH="x86_64"
    SYS_QPKG_SERVICE_ENABLED="TRUE"
    ROUTINES_START_RC=2
    export ROUTINES_TEST_TRACE ROUTINES_EXPECTED_ROOT ROUTINES_START_RC
    . "${ROUTINES_FILE}"
    pkg_post_install
) >/dev/null 2>&1
FALLBACK_RC=$?
set -e
assert_equal "99" "${FALLBACK_RC}" "failed fallback must abort installation"
unset ROUTINES_START_RC
pass "unrecoverable fallback aborts through QDK err_log"

UNINSTALL_SCRIPT="${TEST_ROOT}/uninstall-success.sh"
{
    echo '#!/bin/sh'
    printf '%s\n' "${PKG_PRE_REMOVE}"
    printf 'echo deleted > "%s"\n' "${TEST_ROOT}/deleted-success"
} > "${UNINSTALL_SCRIPT}"
chmod +x "${UNINSTALL_SCRIPT}"
: > "${TRACE_FILE}"
ROUTINES_REMOVE_RC=0 ROUTINES_TEST_TRACE="${TRACE_FILE}" sh "${UNINSTALL_SCRIPT}"
[ -f "${TEST_ROOT}/deleted-success" ] || fail "successful guard did not continue"
assert_equal "remove" "$(cat "${TRACE_FILE}")" "uninstall guard action"
pass "generated uninstall guard is self-contained"

UNINSTALL_FAIL_SCRIPT="${TEST_ROOT}/uninstall-failure.sh"
{
    echo '#!/bin/sh'
    printf '%s\n' "${PKG_PRE_REMOVE}"
    printf 'echo deleted > "%s"\n' "${TEST_ROOT}/deleted-failure"
} > "${UNINSTALL_FAIL_SCRIPT}"
chmod +x "${UNINSTALL_FAIL_SCRIPT}"
set +e
ROUTINES_REMOVE_RC=1 ROUTINES_TEST_TRACE="${TRACE_FILE}" sh "${UNINSTALL_FAIL_SCRIPT}" >/dev/null 2>&1
REMOVE_RC=$?
set -e
[ "${REMOVE_RC}" -ne 0 ] || fail "unsafe removal guard returned success"
[ ! -f "${TEST_ROOT}/deleted-failure" ] || fail "QPKG deletion continued after restore failure"
pass "restore failure blocks QPKG directory deletion"

echo "1..${PASS_COUNT}"
