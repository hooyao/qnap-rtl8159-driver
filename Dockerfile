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

# Create directory structure
RUN mkdir -p /build/{kernel,driver,qpkg,output}

# Copy build scripts
COPY build_driver.sh /build/
COPY create_qpkg_qdk.sh /build/

# Make scripts executable
RUN chmod +x /build/*.sh

# Set environment variables
ENV ARCH=x86_64
ENV KERNEL_VERSION=5.10.60
ENV DRIVER_VERSION=2.20.1
ENV PATH="/opt/QDK:${PATH}"

# Default command
CMD ["/bin/bash"]
