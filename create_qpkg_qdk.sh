#!/bin/bash
set -e

# Configuration
QPKG_NAME="RTL8159_Driver"
DRIVER_VERSION="${DRIVER_VERSION:-2.20.1}"
BUILD_DIR="/build"
OUTPUT_DIR="${BUILD_DIR}/output"
QPKG_BUILD_DIR="${OUTPUT_DIR}/qpkg_qdk"
DRIVER_FILE="r8152.ko"

echo "==================================="
echo "Creating QPKG with QDK"
echo "==================================="

# Function to check QDK installation
check_qdk() {
    echo "[1/7] Checking QDK installation..."

    # Find qbuild
    QBUILD_PATH=$(which qbuild || find /opt/QDK -name qbuild -type f 2>/dev/null | head -1)

    if [ -z "$QBUILD_PATH" ]; then
        echo "ERROR: qbuild not found!"
        echo "QDK may not be installed correctly"
        exit 1
    fi

    echo "Found qbuild at: $QBUILD_PATH"
    export PATH="$(dirname $QBUILD_PATH):$PATH"
}

# Function to create QDK environment
create_qdk_environment() {
    echo "[2/7] Creating QDK environment..."

    cd "${OUTPUT_DIR}"
    rm -rf "${QPKG_BUILD_DIR}"
    mkdir -p "${QPKG_BUILD_DIR}"
    cd "${QPKG_BUILD_DIR}"

    # Create environment using qbuild
    qbuild --create-env "${QPKG_NAME}"

    if [ ! -d "${QPKG_NAME}" ]; then
        echo "ERROR: Failed to create QDK environment"
        exit 1
    fi

    echo "QDK environment created"
}

# Function to configure QPKG
configure_qpkg() {
    echo "[3/7] Configuring QPKG..."

    cd "${QPKG_BUILD_DIR}/${QPKG_NAME}"

    # Create qpkg.cfg with dynamic version
    cat > qpkg.cfg << EOF
QPKG_NAME="RTL8159_Driver"
QPKG_DISPLAY_NAME="Realtek RTL8159/8152/8156/8157 USB Network Driver"
QPKG_VER="${DRIVER_VERSION}"
QPKG_AUTHOR="Custom Build"
QPKG_LICENSE="GPL"
QPKG_SUMMARY="Realtek RTL8159 USB Ethernet driver for 2.5G/5G adapters"
QPKG_RC_NUM="101"

# Supported architectures - QuTS hero h5.x.x and QTS 4.x/5.x
QTS_MINI_VERSION="4.2.0"
QTS_MAX_VERSION="9.9.9"

# Web interface settings
QPKG_WEBUI="/"
QPKG_WEB_PORT=""
QPKG_SERVICE_PORT=""

# Volume settings
QPKG_VOLUME_SELECT="0"
QPKG_TIMEOUT="0"
QPKG_REQUIRE=""
QPKG_CONFLICT=""
QPKG_INCOMPATIBLE=""
EOF

    echo "QPKG configured with version ${DRIVER_VERSION}"
}

# Function to copy driver files
copy_driver_files() {
    echo "[4/7] Copying driver files..."

    cd "${QPKG_BUILD_DIR}/${QPKG_NAME}"

    # Copy driver to x86_64 directory
    if [ -f "${OUTPUT_DIR}/driver/${DRIVER_FILE}" ]; then
        mkdir -p x86_64
        cp "${OUTPUT_DIR}/driver/${DRIVER_FILE}" x86_64/
        echo "Driver copied to x86_64/"
    else
        echo "ERROR: Driver file not found at ${OUTPUT_DIR}/driver/${DRIVER_FILE}"
        exit 1
    fi

    # Copy module info to shared
    if [ -f "${OUTPUT_DIR}/driver/module_info.txt" ]; then
        mkdir -p shared
        cp "${OUTPUT_DIR}/driver/module_info.txt" shared/
    fi
}

# Function to create package routines
create_package_routines() {
    echo "[5/7] Creating package routines..."

    cd "${QPKG_BUILD_DIR}/${QPKG_NAME}"

    cat > package_routines << 'EOF'
#!/bin/sh

QPKG_NAME="RTL8159_Driver"
QPKG_ROOT=$(/sbin/getcfg ${QPKG_NAME} Install_Path -f /etc/config/qpkg.conf)
DRIVER_FILE="r8152.ko"
KERNEL_VERSION=$(uname -r)
MODULE_DIR="/lib/modules/${KERNEL_VERSION}"
LOG_FILE="${QPKG_ROOT}/install.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_FILE}"
}

pkg_pre_install(){
    log "=== Pre-installation started ==="

    # Create module directory
    mkdir -p "${MODULE_DIR}"

    # Backup existing driver
    if [ -f "${MODULE_DIR}/${DRIVER_FILE}" ]; then
        cp "${MODULE_DIR}/${DRIVER_FILE}" "${MODULE_DIR}/${DRIVER_FILE}.backup.$(date +%s)"
        log "Backed up existing driver"
    fi

    # Unload existing driver
    if lsmod | grep -q "^r8152 "; then
        rmmod r8152 2>/dev/null || modprobe -r r8152 2>/dev/null || true
        log "Unloaded existing r8152 driver"
    fi
}

pkg_install(){
    log "=== Installation started ==="

    # Determine architecture
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)
            DRIVER_SRC="${QPKG_ROOT}/x86_64/${DRIVER_FILE}"
            ;;
        *)
            log "ERROR: Unsupported architecture: $ARCH"
            return 1
            ;;
    esac

    # Copy driver
    if [ -f "${DRIVER_SRC}" ]; then
        cp "${DRIVER_SRC}" "${MODULE_DIR}/"
        chmod 644 "${MODULE_DIR}/${DRIVER_FILE}"
        log "Installed driver to ${MODULE_DIR}/"
    else
        log "ERROR: Driver not found: ${DRIVER_SRC}"
        return 1
    fi

    # Update module dependencies
    depmod -a 2>/dev/null || true
    log "Updated module dependencies"
}

pkg_post_install(){
    log "=== Post-installation started ==="

    # Load driver
    if [ -f "${MODULE_DIR}/${DRIVER_FILE}" ]; then
        insmod "${MODULE_DIR}/${DRIVER_FILE}" 2>/dev/null || modprobe r8152 2>/dev/null || true

        if lsmod | grep -q "^r8152 "; then
            log "Driver loaded successfully"

            # Show driver info
            modinfo r8152 2>/dev/null | head -10 | while read line; do
                log "  $line"
            done
        else
            log "WARNING: Driver may not have loaded properly"
        fi
    fi

    log "=== Installation completed successfully ==="
    echo ""
    echo "=========================================="
    echo "RTL8159 Driver installed!"
    echo "=========================================="
    echo "Log: ${LOG_FILE}"
    echo "Please reconnect your USB Ethernet adapter"
    echo "=========================================="
}

PKG_PRE_REMOVE(){
    log "=== Pre-removal started ==="

    # Unload driver
    if lsmod | grep -q "^r8152 "; then
        rmmod r8152 2>/dev/null || modprobe -r r8152 2>/dev/null || true
        log "Unloaded r8152 driver"
    fi
}

PKG_MAIN_REMOVE(){
    log "=== Main removal started ==="

    # Remove driver
    if [ -f "${MODULE_DIR}/${DRIVER_FILE}" ]; then
        rm -f "${MODULE_DIR}/${DRIVER_FILE}"
        log "Removed driver from ${MODULE_DIR}/"
    fi

    # Restore backup if exists
    BACKUP=$(ls -t "${MODULE_DIR}/${DRIVER_FILE}.backup."* 2>/dev/null | head -1)
    if [ -n "$BACKUP" ]; then
        mv "$BACKUP" "${MODULE_DIR}/${DRIVER_FILE}"
        log "Restored backup driver"
    fi

    # Update module dependencies
    depmod -a 2>/dev/null || true
    log "Updated module dependencies"
}

PKG_POST_REMOVE(){
    log "=== Post-removal started ==="

    # Reload original driver if available
    if [ -f "${MODULE_DIR}/${DRIVER_FILE}" ]; then
        modprobe r8152 2>/dev/null || true
        log "Reloaded original driver"
    fi

    log "=== Removal completed ==="
}

case "$1" in
  start)
    # Not needed for driver, but required by QPKG
    ;;
  stop)
    # Not needed for driver, but required by QPKG
    ;;
  restart)
    ;;
  remove)
    PKG_PRE_REMOVE
    PKG_MAIN_REMOVE
    PKG_POST_REMOVE
    ;;
esac
EOF

    chmod +x package_routines
    dos2unix package_routines 2>/dev/null || true

    echo "Package routines created"
}

# Function to create service script
create_service_script() {
    echo "[6/7] Creating service script..."

    cd "${QPKG_BUILD_DIR}/${QPKG_NAME}/shared"

    cat > "${QPKG_NAME}.sh" << 'EOF'
#!/bin/sh
CONF=/etc/config/qpkg.conf
QPKG_NAME="RTL8159_Driver"
QPKG_ROOT=$(/sbin/getcfg ${QPKG_NAME} Install_Path -f ${CONF})

case "$1" in
  start)
    ENABLED=$(/sbin/getcfg ${QPKG_NAME} Enable -u -d FALSE -f ${CONF})
    if [ "$ENABLED" != "TRUE" ]; then
        echo "${QPKG_NAME} is disabled."
        exit 1
    fi
    # Driver loads via package_routines, nothing to do here
    echo "${QPKG_NAME} started"
    ;;

  stop)
    # Driver stays loaded, nothing to do here
    echo "${QPKG_NAME} stopped"
    ;;

  restart)
    $0 stop
    $0 start
    ;;

  *)
    echo "Usage: $0 {start|stop|restart}"
    exit 1
esac

exit 0
EOF

    chmod +x "${QPKG_NAME}.sh"
    dos2unix "${QPKG_NAME}.sh" 2>/dev/null || true

    echo "Service script created"
}

# Function to build QPKG
build_qpkg() {
    echo "[7/7] Building QPKG with qbuild..."

    cd "${QPKG_BUILD_DIR}/${QPKG_NAME}"

    # Run qbuild
    qbuild

    # Find the generated QPKG
    QPKG_FILE=$(find build -name "*.qpkg" -type f | head -1)

    if [ -n "$QPKG_FILE" ] && [ -f "$QPKG_FILE" ]; then
        # Copy to output directory
        cp "$QPKG_FILE" "${OUTPUT_DIR}/"
        FINAL_QPKG="${OUTPUT_DIR}/$(basename $QPKG_FILE)"

        echo "QPKG built successfully!"
        ls -lh "$FINAL_QPKG"

        return 0
    else
        echo "ERROR: QPKG file not found in build directory"
        echo "Build directory contents:"
        ls -lR build/ || true
        return 1
    fi
}

# Main function
main() {
    check_qdk
    create_qdk_environment
    configure_qpkg
    copy_driver_files
    create_package_routines
    create_service_script
    build_qpkg

    echo ""
    echo "==================================="
    echo "QPKG Build Complete!"
    echo "==================================="
    echo "Package: ${OUTPUT_DIR}/${QPKG_NAME}_*.qpkg"
    echo ""
    echo "Install on your QNAP:"
    echo "  1. Via App Center > Install Manually"
    echo "  2. Or SSH: sh *.qpkg"
}

# Run main function
main
