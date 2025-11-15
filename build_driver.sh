#!/bin/bash
set -e

# Configuration
QNAP_GPL_URL="https://sourceforge.net/projects/qosgpl/files"
KERNEL_VERSION="${KERNEL_VERSION:-5.10.60}"
DRIVER_VERSION="${DRIVER_VERSION:-2.20.1}"
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

# Function to download and extract QNAP GPL source
download_kernel_source() {
    echo "[1/6] Downloading QNAP GPL kernel source..."

    mkdir -p /build/kernel
    cd /build/kernel

    # Note: User needs to provide the correct QNAP GPL source URL for their specific model
    # This is a placeholder - actual URL depends on QNAP model and QTS version
    if [ ! -f "kernel-source.tar.gz" ]; then
        echo "WARNING: Kernel source not found!"
        echo "Please download the QNAP GPL source for your specific model from:"
        echo "https://sourceforge.net/projects/qosgpl/files/"
        echo ""
        echo "Place the kernel source archive as /build/kernel/kernel-source.tar.gz"
        echo ""
        echo "Or mount it using: docker run -v /path/to/kernel-source.tar.gz:/build/kernel/kernel-source.tar.gz"

        # For testing, we'll download a generic x86 kernel
        echo "Attempting to download generic Linux kernel ${KERNEL_VERSION}..."
        wget -O kernel-source.tar.xz "https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-${KERNEL_VERSION}.tar.xz" || {
            echo "Failed to download kernel source"
            exit 1
        }
        tar -xf kernel-source.tar.xz
        mv linux-${KERNEL_VERSION} linux-source
    else
        echo "Found existing kernel source, extracting..."
        tar -xzf kernel-source.tar.gz
    fi
}

# Function to configure kernel
configure_kernel() {
    echo "[2/6] Configuring kernel..."

    cd /build/kernel/linux-source

    # If there's a custom config, use it; otherwise use defconfig
    if [ -f "/build/kernel/qnap_kernel.config" ]; then
        echo "Using custom QNAP kernel config..."
        cp /build/kernel/qnap_kernel.config .config
    else
        echo "Using x86_64 defconfig..."
        make ARCH=x86_64 defconfig
    fi

    # Prepare kernel for module compilation
    echo "Preparing kernel for module build..."
    make ARCH=x86_64 scripts prepare modules_prepare
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
    fi

    # Apply any additional patches if needed
    echo "Driver patching complete."
}

# Function to compile driver
compile_driver() {
    echo "[5/6] Compiling driver..."

    KERNEL_SRC="/build/kernel/linux-source"

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
    download_kernel_source
    configure_kernel
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
    echo "Next step: Run create_qpkg.sh to package the driver"
}

# Run main function
main
