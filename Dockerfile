# Dockerfile for building RTL8159 driver for QNAP x86 systems
FROM ubuntu:20.04

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    libelf-dev \
    bc \
    wget \
    curl \
    bzip2 \
    xz-utils \
    flex \
    bison \
    libssl-dev \
    libncurses5-dev \
    git \
    unzip \
    kmod \
    cpio \
    rsync \
    python3 \
    python3-pip \
    file \
    jq \
    dos2unix \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# Install QDK (QNAP Development Kit)
RUN git clone https://github.com/qnap-dev/QDK.git /opt/QDK && \
    cd /opt/QDK && \
    chmod +x InstallToUbuntu.sh && \
    yes | ./InstallToUbuntu.sh install

# Set working directory
WORKDIR /build

# Set environment variables
ENV ARCH=x86_64
ENV KERNEL_VERSION=5.10.60
ENV DRIVER_VERSION=2.20.1
ENV PATH="/opt/QDK:${PATH}"

# Download and prepare kernel source (done once during image build)
RUN mkdir -p /build/kernel /build/driver /build/qpkg /build/output && \
    echo "Downloading kernel ${KERNEL_VERSION} source..." && \
    cd /build/kernel && \
    wget "https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-${KERNEL_VERSION}.tar.xz" && \
    echo "Extracting kernel source..." && \
    tar -xf linux-${KERNEL_VERSION}.tar.xz && \
    mv linux-${KERNEL_VERSION} linux-source && \
    rm linux-${KERNEL_VERSION}.tar.xz && \
    echo "Preparing kernel for module building..." && \
    cd linux-source && \
    make ARCH=x86_64 x86_64_defconfig > /dev/null && \
    make ARCH=x86_64 scripts prepare modules_prepare > /dev/null && \
    echo "Kernel source ready for driver compilation"

# Copy build scripts
COPY build_driver.sh /build/
COPY build_qpkg.sh /build/

# Make scripts executable
RUN chmod +x /build/*.sh

# Default command
CMD ["/bin/bash"]
