#!/bin/bash
set -e

# Configuration
QNAP_GPL_URL="https://sourceforge.net/projects/qosgpl/files"
KERNEL_VERSION="${KERNEL_VERSION:-5.10.60}"
# Use v2.17.1.20230903 to match QNAP's working driver version (v2.17.1 from 2023/06/13)
DRIVER_VERSION="${DRIVER_VERSION:-2.17.1.20230903}"
REALTEK_DRIVER_URL="https://github.com/wget/realtek-r8152-linux/archive/refs/tags/v${DRIVER_VERSION}.tar.gz"
# RTL8159 is part of the r8152 driver family (r8152.ko supports RTL8152/8153/8156/8157/8159)
DRIVER_NAME="r8152"

echo "==================================="
echo "RTL8159 Driver Build for QNAP x86"
echo "==================================="
echo "Kernel Version: ${KERNEL_VERSION}"
echo "Driver Version: ${DRIVER_VERSION}"
echo "Note: RTL8159 uses r8152.ko driver"
echo "==================================="

# Function to verify kernel source
verify_kernel_source() {
    echo "[1/6] Verifying kernel source..."

    if [ -d "/build/kernel/linux-source" ]; then
        echo "✓ Kernel source found (pre-downloaded in Docker image)"
        echo "  Location: /build/kernel/linux-source"
        echo "  Version: ${KERNEL_VERSION}"
    else
        echo "ERROR: Kernel source not found!"
        echo "The Docker image should have pre-downloaded kernel source."
        echo "Please rebuild the Docker image: ./build.sh image"
        exit 1
    fi
}

# Function to prepare kernel (if custom config provided)
prepare_kernel() {
    echo "[2/6] Preparing kernel..."

    cd /build/kernel/linux-source

    # QNAP's kernel source is already built with correct version (5.10.60-qnap)
    echo "Using QNAP's pre-built kernel source (5.10.60-qnap)..."
    echo "✓ Kernel source already prepared for module building"
}

# Function to download driver source
download_driver_source() {
    echo "[3/6] Downloading RTL8152/8156 driver source..."

    mkdir -p /build/driver
    cd /build/driver

    if [ ! -d "realtek-r8152-linux-${DRIVER_VERSION}" ]; then
        # Try official Realtek driver
        if ! wget -O r8152-${DRIVER_VERSION}.tar.gz "${REALTEK_DRIVER_URL}"; then
            echo "Trying alternative source..."
            # Alternative: clone from git
            git clone https://github.com/wget/realtek-r8152-linux.git
            cd realtek-r8152-linux
            git checkout "v${DRIVER_VERSION}" 2>/dev/null || echo "Using latest version"
            cd ..
            mv realtek-r8152-linux "realtek-r8152-linux-${DRIVER_VERSION}"
        else
            tar -xzf r8152-${DRIVER_VERSION}.tar.gz
        fi
    fi

    cd "realtek-r8152-linux-${DRIVER_VERSION}" || cd realtek-r8152-linux-*
}

# Function to patch driver for older kernels
patch_driver() {
    echo "[4/6] Patching driver for kernel ${KERNEL_VERSION}..."

    # Replace strscpy with strlcpy for older kernels (< 4.3)
    if [ -f "r8152.c" ]; then
        echo "Patching strscpy -> strlcpy..."
        sed -i 's/strscpy/strlcpy/g' r8152.c

        # Add RTL8159 (0x815a) and RTL8157 (0x8157) device ID support
        # These devices are newer but compatible with the r8152 driver
        echo "Adding RTL8157/RTL8159 device ID support..."

        # Find the usb_device_id table and add entries before the terminator
        # Look for the pattern: { USB_DEVICE(VENDOR_ID_REALTEK, 0x8156) }
        # Add RTL8157 and RTL8159 entries after RTL8156

        sed -i '/USB_DEVICE(VENDOR_ID_REALTEK, 0x8156)/a\
\t{ USB_DEVICE_AND_INTERFACE_INFO(VENDOR_ID_REALTEK, 0x8157, USB_CLASS_COMM, USB_CDC_SUBCLASS_ETHERNET, USB_CDC_PROTO_NONE) },\
\t{ USB_DEVICE_AND_INTERFACE_INFO(VENDOR_ID_REALTEK, 0x8157, USB_CLASS_COMM, USB_CDC_SUBCLASS_NCM, USB_CDC_PROTO_NONE) },\
\t{ USB_DEVICE_AND_INTERFACE_INFO(VENDOR_ID_REALTEK, 0x8157, USB_CLASS_VENDOR_SPEC, USB_SUBCLASS_VENDOR_SPEC, 0xff) },\
\t{ USB_DEVICE_AND_INTERFACE_INFO(VENDOR_ID_REALTEK, 0x815a, USB_CLASS_COMM, USB_CDC_SUBCLASS_ETHERNET, USB_CDC_PROTO_NONE) },\
\t{ USB_DEVICE_AND_INTERFACE_INFO(VENDOR_ID_REALTEK, 0x815a, USB_CLASS_COMM, USB_CDC_SUBCLASS_NCM, USB_CDC_PROTO_NONE) },\
\t{ USB_DEVICE_AND_INTERFACE_INFO(VENDOR_ID_REALTEK, 0x815a, USB_CLASS_VENDOR_SPEC, USB_SUBCLASS_VENDOR_SPEC, 0xff) },' r8152.c

        echo "✓ RTL8157/RTL8159 device IDs added"
    fi

    # Enable S5 Wake-on-LAN support (uncomment in Makefile)
    if [ -f "Makefile" ]; then
        echo "Enabling S5 Wake-on-LAN (S5_WOL) support..."
        sed -i 's/^#\([ \t]*ccflags-y += -DRTL8152_S5_WOL\)/\1/' Makefile
        echo "✓ S5_WOL enabled"
    fi

    # Apply any additional patches if needed
    echo "Driver patching complete."
}

# Function to compile driver
compile_driver() {
    echo "[5/6] Compiling driver..."

    KERNEL_SRC="/build/kernel/linux-source"

    # Compile against QNAP's actual kernel source (CONFIG_MODVERSIONS is disabled)
    echo "Compiling against QNAP kernel source..."

    make ARCH=x86_64 \
         -C "${KERNEL_SRC}" \
         M=$(pwd) \
         modules \
         EXTRA_CFLAGS='-O2'

    if [ ! -f "r8152.ko" ]; then
        echo "ERROR: Driver compilation failed - r8152.ko not found!"
        exit 1
    fi

    echo "Driver compiled successfully!"
    ls -lh r8152.ko
}

# Function to prepare output
prepare_output() {
    echo "[6/6] Preparing output..."

    mkdir -p /build/output/driver
    cp r8152.ko /build/output/driver/

    # Get driver info
    modinfo r8152.ko > /build/output/driver/module_info.txt || true

    echo "Driver build complete!"
    echo "Output location: /build/output/driver/r8152.ko"
}

# Main build process
main() {
    verify_kernel_source
    prepare_kernel
    download_driver_source
    patch_driver
    compile_driver
    prepare_output

    echo ""
    echo "==================================="
    echo "Build completed successfully!"
    echo "==================================="
    echo "Driver: /build/output/driver/r8152.ko"
    echo ""
    echo "Next step: Run create_qpkg_qdk.sh to package the driver"
}

# Run main function
main
