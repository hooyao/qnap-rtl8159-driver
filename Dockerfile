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

# Copy QNAP's complete kernel source (pre-built with correct configuration)
COPY GPL_QTS/src/linux-5.10 /build/kernel/linux-source
COPY GPL_QTS/kernel_cfg/TS-X65U/linux-5.10-x86_64.config /build/kernel/.config

# Prepare QNAP kernel source for module building
RUN mkdir -p /build/driver /build/qpkg /build/output && \
    echo "Using QNAP's pre-built kernel 5.10.60-qnap source..." && \
    cd /build/kernel/linux-source && \
    echo "Kernel source already built and ready for driver compilation"

# Copy build scripts
COPY build_driver.sh /build/
COPY build_qpkg.sh /build/

# Make scripts executable
RUN chmod +x /build/*.sh

# Default command
CMD ["/bin/bash"]
