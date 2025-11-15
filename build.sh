#!/bin/bash
set -e

# Main build orchestration script for RTL8159 driver QPKG

echo "=========================================="
echo "RTL8159 Driver QPKG Build System"
echo "=========================================="
echo "Target: QNAP x86_64 (Kernel 5.10.60)"
echo "=========================================="

# Configuration
DOCKER_IMAGE="rtl8159-builder"
DOCKER_TAG="latest"
CONTAINER_NAME="rtl8159-build"

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    echo "ERROR: Docker is not installed or not in PATH"
    exit 1
fi

# Parse command line arguments
COMMAND="${1:-all}"
KERNEL_SOURCE_PATH="${2:-}"

show_usage() {
    cat << EOF
Usage: $0 [command] [kernel_source_path]

Commands:
  all              - Build Docker image, compile driver, and create QPKG (default)
  image            - Build Docker image only
  driver           - Compile driver only (requires existing image)
  qpkg             - Create QPKG package only (requires compiled driver)
  clean            - Remove Docker image and build artifacts
  shell            - Start interactive shell in build container
  help             - Show this help message

Optional:
  kernel_source_path - Path to QNAP GPL kernel source tarball
                       If not provided, will download generic kernel

Examples:
  $0 all                           # Full build with generic kernel
  $0 all /path/to/kernel.tar.gz    # Full build with QNAP kernel
  $0 driver                         # Compile driver only
  $0 shell                          # Interactive debugging

EOF
}

# Function to build Docker image
build_image() {
    echo ""
    echo "[Step 1/3] Building Docker image..."
    echo "=========================================="

    docker build -t "${DOCKER_IMAGE}:${DOCKER_TAG}" .

    echo "Docker image built successfully: ${DOCKER_IMAGE}:${DOCKER_TAG}"
}

# Function to compile driver
compile_driver() {
    echo ""
    echo "[Step 2/3] Compiling RTL8159 driver..."
    echo "=========================================="

    # Prepare volume mounts
    VOLUME_MOUNTS="-v $(pwd)/output:/build/output"

    # If kernel source is provided, mount it
    if [ -n "${KERNEL_SOURCE_PATH}" ] && [ -f "${KERNEL_SOURCE_PATH}" ]; then
        echo "Using provided kernel source: ${KERNEL_SOURCE_PATH}"
        VOLUME_MOUNTS="${VOLUME_MOUNTS} -v ${KERNEL_SOURCE_PATH}:/build/kernel/kernel-source.tar.gz"
    else
        echo "No kernel source provided - will download generic kernel"
    fi

    # Remove old container if exists
    docker rm -f "${CONTAINER_NAME}" 2>/dev/null || true

    # Run build
    docker run --name "${CONTAINER_NAME}" \
        ${VOLUME_MOUNTS} \
        "${DOCKER_IMAGE}:${DOCKER_TAG}" \
        /bin/bash -c "/build/build_driver.sh"

    # Check if driver was built
    if [ -f "output/driver/r8152.ko" ]; then
        echo ""
        echo "Driver compiled successfully!"
        echo "Location: $(pwd)/output/driver/r8152.ko"
        ls -lh output/driver/r8152.ko
    else
        echo "ERROR: Driver compilation failed!"
        exit 1
    fi

    # Cleanup container
    docker rm "${CONTAINER_NAME}" 2>/dev/null || true
}

# Function to create QPKG
create_qpkg() {
    echo ""
    echo "[Step 3/3] Creating QPKG package..."
    echo "=========================================="

    # Check if driver exists
    if [ ! -f "output/driver/r8152.ko" ]; then
        echo "ERROR: Driver not found! Please compile the driver first."
        echo "Run: $0 driver"
        exit 1
    fi

    # Remove old container if exists
    docker rm -f "${CONTAINER_NAME}-qpkg" 2>/dev/null || true

    # Run QPKG creation with QDK
    docker run --name "${CONTAINER_NAME}-qpkg" \
        -v $(pwd)/output:/build/output \
        "${DOCKER_IMAGE}:${DOCKER_TAG}" \
        /bin/bash -c "/build/create_qpkg_qdk.sh"

    # QDK creates QDK_*.qpkg, we need to copy and rename it
    QDK_QPKG=$(find output/qpkg_qdk/RTL8159_Driver/build -name "*x86_64.qpkg" -type f | head -n 1)
    QPKG_FILE="output/RTL8159_Driver_2.17.1_x86_64.qpkg"

    if [ -f "${QDK_QPKG}" ]; then
        cp "${QDK_QPKG}" "${QPKG_FILE}"
        echo ""
        echo "QPKG package created successfully!"
        echo "Location: ${QPKG_FILE}"
        ls -lh "${QPKG_FILE}"
        echo ""
        echo "=========================================="
        echo "Installation Instructions:"
        echo "=========================================="
        echo "1. Copy ${QPKG_FILE} to your QNAP NAS"
        echo "2. Install via App Center > Install Manually"
        echo "   OR"
        echo "3. Install via SSH: sh $(basename ${QPKG_FILE})"
        echo "=========================================="
    else
        echo "ERROR: QPKG creation failed!"
        echo "QDK did not create the expected package file."
        exit 1
    fi

    # Cleanup container
    docker rm "${CONTAINER_NAME}-qpkg" 2>/dev/null || true
}

# Function to clean build artifacts
clean() {
    echo "Cleaning build artifacts..."

    # Remove output directory
    rm -rf output

    # Remove Docker image
    docker rmi "${DOCKER_IMAGE}:${DOCKER_TAG}" 2>/dev/null || true

    # Remove any leftover containers
    docker rm -f "${CONTAINER_NAME}" "${CONTAINER_NAME}-qpkg" 2>/dev/null || true

    echo "Cleanup complete!"
}

# Function to start interactive shell
interactive_shell() {
    echo "Starting interactive build shell..."
    echo "Available scripts:"
    echo "  /build/build_driver.sh  - Compile driver"
    echo "  /build/create_qpkg.sh   - Create QPKG package"
    echo ""

    docker run -it --rm \
        -v $(pwd)/output:/build/output \
        "${DOCKER_IMAGE}:${DOCKER_TAG}" \
        /bin/bash
}

# Main execution
case "${COMMAND}" in
    all)
        build_image
        compile_driver
        create_qpkg
        echo ""
        echo "=========================================="
        echo "Build process completed successfully!"
        echo "=========================================="
        ;;
    image)
        build_image
        ;;
    driver)
        compile_driver
        ;;
    qpkg)
        create_qpkg
        ;;
    clean)
        clean
        ;;
    shell)
        interactive_shell
        ;;
    help|--help|-h)
        show_usage
        ;;
    *)
        echo "ERROR: Unknown command: ${COMMAND}"
        echo ""
        show_usage
        exit 1
        ;;
esac
