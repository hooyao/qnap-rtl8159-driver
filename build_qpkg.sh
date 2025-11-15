#!/bin/bash
set -e

# Configuration
QPKG_NAME="RTL8159_Driver"
QPKG_SOURCE="/qpkg_source/${QPKG_NAME}"
BUILD_DIR="/build"
OUTPUT_DIR="${BUILD_DIR}/output"
DRIVER_OUTPUT="${OUTPUT_DIR}/driver"

echo "===================================="
echo "Building QPKG from source template"
echo "===================================="
echo "QPKG Source: ${QPKG_SOURCE}"
echo "Output: ${OUTPUT_DIR}"
echo ""

# Check if QDK is installed
check_qdk() {
    echo "[1/5] Checking QDK installation..."
    QBUILD_PATH=$(which qbuild || find /opt/QDK -name qbuild -type f 2>/dev/null | head -1)

    if [ -z "$QBUILD_PATH" ]; then
        echo "ERROR: qbuild not found!"
        exit 1
    fi

    echo "Found qbuild at: $QBUILD_PATH"
    export PATH="$(dirname $QBUILD_PATH):$PATH"
}

# Copy driver to QPKG source
copy_driver() {
    echo "[2/5] Copying driver to QPKG source..."

    # Validate QPKG source directory exists
    if [ ! -d "${QPKG_SOURCE}" ]; then
        echo "ERROR: QPKG source directory not found: ${QPKG_SOURCE}"
        echo "Please ensure the qpkg directory is properly mounted"
        echo "Expected directory structure:"
        echo "  ${QPKG_SOURCE}/"
        echo "  ├── qpkg.cfg"
        echo "  ├── package_routines"
        echo "  ├── shared/"
        echo "  └── icons/"
        exit 1
    fi

    # Validate required files exist
    if [ ! -f "${QPKG_SOURCE}/qpkg.cfg" ]; then
        echo "ERROR: qpkg.cfg not found in ${QPKG_SOURCE}"
        exit 1
    fi

    if [ ! -f "${QPKG_SOURCE}/package_routines" ]; then
        echo "ERROR: package_routines not found in ${QPKG_SOURCE}"
        exit 1
    fi

    if [ ! -f "${DRIVER_OUTPUT}/r8152.ko" ]; then
        echo "ERROR: Driver not found at ${DRIVER_OUTPUT}/r8152.ko"
        echo "Please build the driver first using ./build.sh driver"
        exit 1
    fi

    # Copy driver to x86_64 architecture directory
    mkdir -p "${QPKG_SOURCE}/x86_64"
    cp "${DRIVER_OUTPUT}/r8152.ko" "${QPKG_SOURCE}/x86_64/"
    echo "Driver copied to ${QPKG_SOURCE}/x86_64/"
}

# Set permissions and update version
set_permissions() {
    echo "[3/5] Setting permissions and updating version..."

    # Update version in qpkg.cfg if QPKG_VERSION is set
    if [ -n "${QPKG_VERSION}" ]; then
        echo "Updating qpkg.cfg with QPKG version: ${QPKG_VERSION}"
        sed -i "s/^QPKG_VER=.*/QPKG_VER=\"${QPKG_VERSION}\"/" "${QPKG_SOURCE}/qpkg.cfg"
    else
        echo "Using default version from qpkg.cfg"
    fi

    # Log driver version being packaged
    if [ -n "${DRIVER_VERSION}" ]; then
        echo "Packaging Realtek driver version: ${DRIVER_VERSION}"
    fi

    # Make scripts executable if they exist
    if [ -f "${QPKG_SOURCE}/shared/RTL8159_Driver.sh" ]; then
        chmod +x "${QPKG_SOURCE}/shared/RTL8159_Driver.sh"
    else
        echo "ERROR: ${QPKG_SOURCE}/shared/RTL8159_Driver.sh not found"
        echo "QPKG_SOURCE directory contents:"
        ls -laR "${QPKG_SOURCE}/" || true
        exit 1
    fi

    # Fix line endings (dos2unix)
    if command -v dos2unix > /dev/null 2>&1; then
        find "${QPKG_SOURCE}" -type f \( -name "*.sh" -o -name "package_routines" \) -exec dos2unix {} \; 2>/dev/null || true
    fi

    echo "Permissions set and version updated"
}

# Build QPKG with qbuild
build_qpkg() {
    echo "[4/5] Building QPKG with qbuild..."

    cd "${QPKG_SOURCE}"

    # Clean previous build
    rm -rf build

    # Build with qbuild
    qbuild

    # Find generated QPKG file
    QPKG_FILE=$(find build -name "*.qpkg" -type f | head -1)

    if [ -n "$QPKG_FILE" ] && [ -f "$QPKG_FILE" ]; then
        # Rename to proper name with version
        DRIVER_VERSION=$(grep "QPKG_VER=" "${QPKG_SOURCE}/qpkg.cfg" | cut -d'"' -f2)
        FINAL_NAME="${QPKG_NAME}_${DRIVER_VERSION}_x86_64.qpkg"
        FINAL_QPKG="${OUTPUT_DIR}/${FINAL_NAME}"

        # Copy to output directory with proper name
        mkdir -p "${OUTPUT_DIR}"
        cp "$QPKG_FILE" "${FINAL_QPKG}"

        echo "QPKG built successfully!"
        echo "Output: ${FINAL_QPKG}"
        ls -lh "$FINAL_QPKG"

        return 0
    else
        echo "ERROR: QPKG file not found in build directory"
        echo "Build directory contents:"
        ls -lR build/ || true
        return 1
    fi
}

# Show summary
show_summary() {
    echo ""
    echo "===================================="
    echo "QPKG Build Complete!"
    echo "===================================="
    echo "Package: ${OUTPUT_DIR}/${QPKG_NAME}_*.qpkg"
    echo ""
    echo "Install on your QNAP:"
    echo "  1. Via App Center > Install Manually"
    echo "  2. Upload the .qpkg file"
    echo ""
    echo "To verify after installation:"
    echo "  - Check App Center for Remove button"
    echo "  - SSH: lsmod | grep r8152"
    echo "===================================="
}

# Main execution
main() {
    check_qdk
    copy_driver
    set_permissions
    build_qpkg
    show_summary
}

main
