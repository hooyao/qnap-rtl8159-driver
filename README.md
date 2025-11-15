# RTL8159 10Gbps Driver Builder for QNAP NAS

Automated build system for compiling and packaging the Realtek RTL8159 10Gbps USB Ethernet driver (r8152.ko) as a QPKG for QNAP NAS systems.

## Features

- **Automated Build**: Docker-based build environment with all dependencies
- **Official QDK**: Uses QNAP's official QDK (QPKG Development Kit) for packaging
- **Kernel Module**: Compiles r8152.ko driver for kernel 5.10.60
- **Multi-Device Support**: RTL8152/8153/8156/8157/8159 USB Ethernet adapters (up to 10Gbps)
- **QuTS hero Compatible**: Works on both QTS and QuTS hero systems
- **Auto-Load**: Driver loads automatically at boot after installation

## Supported Devices

| Chipset  | Max Speed | Notes                           |
|----------|-----------|----------------------------------|
| RTL8152  | 100 Mbps  | Basic USB Ethernet              |
| RTL8153  | 1 Gbps    | Gigabit USB Ethernet            |
| RTL8156  | 2.5 Gbps  | 2.5G USB Ethernet               |
| RTL8157  | 5 Gbps    | High-speed USB Ethernet         |
| RTL8159  | 10 Gbps   | Latest generation (up to 10Gbps)|

## System Requirements

### Build Machine
- Docker installed
- 2GB+ free disk space
- Internet connection

### Target QNAP NAS
- Architecture: x86_64
- OS: QTS 4.2+ or QuTS hero h5.2+
- Kernel: 5.10.60
- USB port (for connecting adapter)

## Quick Start

### 1. Build the QPKG

```bash
# Clone or download this repository
cd quts_rtl

# Build everything (Docker image + driver + QPKG)
./build.sh all
```

The build process will:
1. Create a Docker container with Ubuntu 20.04
2. Install QNAP QDK and kernel build tools
3. Download Linux kernel 5.10.60 source
4. Compile the r8152 driver module
5. Package everything into a QPKG file

**Output**: `output/RTL8159_Driver_2.20.1_x86_64.qpkg` (version is configurable)

### 2. Install on QNAP

#### Method A: App Center (GUI)

1. Copy the `.qpkg` file to your computer
2. Open **App Center** on your QNAP
3. Click the gear icon → **Install Manually**
4. Select the `.qpkg` file and install
5. Connect your USB Ethernet adapter

#### Method B: SSH (CLI)

```bash
# Copy to NAS
scp output/RTL8159_Driver_2.20.1_x86_64.qpkg admin@your-nas:/share/Public/

# SSH and install
ssh admin@your-nas
cd /share/Public
sh RTL8159_Driver_2.20.1_x86_64.qpkg
```

### 3. Verify Installation

```bash
# Check if driver is loaded
lsmod | grep r8152

# View driver information
modinfo r8152

# List network interfaces
ip link show

# Check installation log
cat /share/CACHEDEV1_DATA/.qpkg/RTL8159_Driver/install.log
```

## Build System Architecture

### Directory Structure

```
quts_rtl/
├── Dockerfile              # Docker build environment (Ubuntu 20.04 + QDK)
├── build.sh               # Main orchestration script
├── build_driver.sh        # Driver compilation script
├── build_qpkg.sh          # QPKG packaging script
├── qpkg/                  # QPKG source template (version controlled)
│   └── RTL8159_Driver/
│       ├── icons/         # Package icons
│       ├── shared/        # Shared files (scripts, web UI)
│       ├── config/        # Configuration directory
│       ├── qpkg.cfg       # Package metadata
│       └── package_routines # Install/remove scripts
├── .gitignore            # Git ignore rules
├── README.md             # This file
└── CLAUDE.md             # Development conversation log
```

### Build Components

#### 1. Dockerfile
Creates a Docker container with:
- Ubuntu 20.04 base image
- Kernel build tools (gcc, make, flex, bison, etc.)
- QNAP QDK 2.3.14 (official QPKG builder)
- All dependencies for kernel module compilation

#### 2. build_driver.sh
Handles driver compilation:
- Downloads Linux kernel 5.10.60 source
- Configures kernel for x86_64
- Prepares kernel headers
- Downloads Realtek r8152 driver source (configurable version, default: 2.20.1)
- Patches driver for compatibility
- Compiles r8152.ko module

#### 3. build_qpkg.sh
Packages driver using QDK template:
- Uses pre-created template in qpkg/RTL8159_Driver/
- Copies compiled driver to template
- Builds QPKG with official qbuild tool
- Icons and scripts are part of version-controlled template

#### 4. build.sh
Main orchestration:
- Manages Docker image building
- Coordinates driver compilation
- Triggers QPKG creation
- Provides cleanup and debug options

## Build Commands

```bash
# Full build (recommended)
./build.sh all

# Build only Docker image
./build.sh image

# Compile driver only (requires existing image)
./build.sh driver

# Create QPKG only (requires compiled driver)
./build.sh qpkg

# Clean all build artifacts
./build.sh clean

# Interactive shell for debugging
./build.sh shell

# Show help
./build.sh help
```

## Advanced Usage

### Custom Driver Version

You can build different driver versions by setting the `DRIVER_VERSION` environment variable:

```bash
# Build with a specific driver version
DRIVER_VERSION=2.17.1 ./build.sh all
DRIVER_VERSION=2.18.0 ./build.sh all
DRIVER_VERSION=2.19.0 ./build.sh all

# Default version (if not specified)
./build.sh all  # Uses 2.20.1
```

**Output**: The QPKG filename will reflect the version, e.g., `RTL8159_Driver_2.19.0_x86_64.qpkg`

Available driver versions can be found at:
- https://github.com/wget/realtek-r8152-linux/tags

### Package Icons

Icons are included in the QPKG source template at `qpkg/RTL8159_Driver/icons/`.

**Included Icons:**
- `RTL8159_Driver.gif` (64x64) - Enabled state icon
- `RTL8159_Driver_gray.gif` (64x64) - Disabled state icon
- `RTL8159_Driver_80.gif` (80x80) - Dialog popup icon

**Customizing Icons:**
To use custom icons, replace the files in `qpkg/RTL8159_Driver/icons/` before building:

```bash
# Replace icon files in the template
cp my-custom-icon.gif qpkg/RTL8159_Driver/icons/RTL8159_Driver.gif
cp my-custom-icon-gray.gif qpkg/RTL8159_Driver/icons/RTL8159_Driver_gray.gif
cp my-custom-icon-80.gif qpkg/RTL8159_Driver/icons/RTL8159_Driver_80.gif

# Build with your custom icons
./build.sh qpkg
```

**Icon Requirements:**
- **Format**: GIF (preferred) or PNG (supported since QDK 2.2.15)
- **Standard icons**: 64x64 pixels (RTL8159_Driver.gif, RTL8159_Driver_gray.gif)
- **Dialog icon**: 80x80 pixels (RTL8159_Driver_80.gif)
- Icons are version controlled and part of the QPKG template

### Custom Kernel Source

If you have the official QNAP GPL kernel source:

```bash
./build.sh all /path/to/qnap-kernel-source.tar.gz
```

Download QNAP GPL sources from: https://sourceforge.net/projects/qosgpl/files/

### Rebuilding

```bash
# Clean and rebuild
./build.sh clean
./build.sh all

# Or just rebuild QPKG after code changes
./build.sh qpkg
```

### Debugging

```bash
# Enter interactive build environment
./build.sh shell

# Inside the container:
/build/build_driver.sh     # Compile driver manually
/build/build_qpkg.sh       # Package manually
```

## Installation Details

### What the Installer Does

**Pre-Install:**
- Creates `/lib/modules/5.10.60/` directory
- Backs up existing r8152.ko driver (if present)
- Unloads old driver from memory

**Install:**
- Copies new r8152.ko to `/lib/modules/5.10.60/`
- Sets permissions (644)
- Updates kernel module dependencies (depmod)

**Post-Install:**
- Loads new driver into kernel
- Verifies driver loaded successfully
- Creates installation log
- Sets up auto-load at boot

### Installed Files

On your QNAP after installation:
- **Driver**: `/lib/modules/5.10.60/r8152.ko`
- **QPKG directory**: `/share/CACHEDEV1_DATA/.qpkg/RTL8159_Driver/`
- **Installation log**: `/share/CACHEDEV1_DATA/.qpkg/RTL8159_Driver/install.log`
- **Service script**: `/share/CACHEDEV1_DATA/.qpkg/RTL8159_Driver/shared/RTL8159_Driver.sh`
- **Configuration**: `/etc/config/qpkg.conf` (entry added)

### Auto-Load at Boot

The driver automatically loads at boot through the QPKG startup mechanism registered in `/etc/config/qpkg.conf`.

## Uninstallation

### Via App Center
1. Open **App Center**
2. Find "Realtek RTL8159 USB Network Driver"
3. Click **Remove**

### Via Command Line
```bash
/sbin/qpkg_cli -R RTL8159_Driver
```

**What happens:**
- Driver is unloaded from memory
- Driver file is removed
- Original backup is restored (if any)
- Module dependencies updated
- QPKG entry removed from config

## Troubleshooting

### Driver Not Loading

```bash
# Check kernel messages
dmesg | grep r8152 | tail -20

# Try manual load
insmod /lib/modules/5.10.60/r8152.ko

# Or
modprobe r8152

# Check for errors
journalctl -xe
```

### Device Not Detected

```bash
# Check if USB device is recognized
lsusb | grep Realtek

# View USB tree
lsusb -t

# Verify driver is loaded
lsmod | grep r8152
```

### Performance Issues

**Symptoms**: Not getting expected speeds

**Solutions:**
- Use **rear** USB ports (often faster than front)
- Use high-quality USB cables (USB 3.0+ rated)
- Verify adapter chipset with `lsusb | grep Realtek`
- Check NAS USB port capabilities in specifications
- RTL8159 may achieve 8-10Gbps depending on hardware

### Build Failures

**Out of disk space:**
```bash
df -h
docker system prune -a  # Clean Docker cache
```

**Network timeout:**
- Retry the build (kernel download may timeout)
- Or provide your own kernel source

**Permission issues:**
```bash
chmod +x *.sh
```

## QuTS Hero Notes

This build system works on both:
- **QTS** (ext4-based): 4.2.0 - 9.9.9
- **QuTS hero** (ZFS-based): h5.2.0 - h5.9.9

The QPKG is configured with `QTS_MAX_VERSION="9.9.9"` to support QuTS hero's h5.x.x versioning.

## Customization

### Change Driver Version

Edit `Dockerfile` and `build_driver.sh`:
```bash
ENV DRIVER_VERSION=2.18.0
```

### Change Kernel Version

Edit `Dockerfile` and `build_driver.sh`:
```bash
ENV KERNEL_VERSION=5.10.70
```

Then rebuild:
```bash
./build.sh clean
./build.sh all
```

### Modify QPKG Configuration

Edit `qpkg/RTL8159_Driver/qpkg.cfg` to change:
- Package name and display name
- Version constraints (QTS_MINI_VERSION, QTS_MAX_VERSION)
- Package metadata (author, license, summary)
- Web UI settings

## Technical Details

### Driver Version
- **Version**: 2.17.1
- **Source**: https://github.com/wget/realtek-r8152-linux
- **Module**: r8152.ko
- **Size**: ~619KB compiled

### Kernel Version
- **Version**: 5.10.60
- **Architecture**: x86_64
- **Config**: x86_64_defconfig

### QDK Version
- **Version**: 2.3.14
- **Source**: https://github.com/qnap-dev/QDK
- **Purpose**: Official QNAP package builder

### Build Time
- Docker image: ~2-3 minutes (first time)
- Driver compilation: ~3-5 minutes
- QPKG creation: ~10-20 seconds
- **Total**: ~5-10 minutes (subsequent builds faster due to caching)

## References

- [QNAP GPL Source](https://sourceforge.net/projects/qosgpl/files/)
- [Realtek r8152 Driver](https://github.com/wget/realtek-r8152-linux)
- [QNAP QDK](https://github.com/qnap-dev/QDK)
- [QDK Quick Start Guide](https://cheng-yuan-hong.gitbook.io/qdk-quick-start-guide/)
- [Linux Kernel Archives](https://kernel.org/)

## GitHub Actions - Automated Releases

This repository includes a GitHub Actions workflow that automatically builds and releases the QPKG when you push a tag starting with `release-`.

### Creating a Release

```bash
# Tag the commit with a version
git tag release-2.20.1b
git push origin release-2.20.1b
```

The GitHub Actions workflow will:
1. Build the Docker image
2. Compile the driver
3. Package the QPKG
4. Create a GitHub release
5. Upload the QPKG file as a release asset

### Release Workflow Features

- **Automatic builds**: Triggered by tags matching `release-*`
- **Version extraction**: Extracts version from tag name (e.g., `release-2.20.1b` → `2.20.1b`)
- **GitHub releases**: Creates a release with changelog and installation instructions
- **Asset upload**: Uploads the built QPKG file to the release
- **Build artifacts**: Stores build artifacts for 30 days

### Workflow File

The workflow is defined in [.github/workflows/release.yml](.github/workflows/release.yml).

### Example Usage

```bash
# Make changes to your code
git add .
git commit -m "Update driver to version 2.20.1b"

# Create a release tag
git tag release-2.20.1b

# Push the tag to trigger the workflow
git push origin release-2.20.1b

# GitHub Actions will:
# - Build the QPKG automatically
# - Create a GitHub release at: https://github.com/yourusername/quts_rtl/releases
# - Upload RTL8159_Driver_2.20.1b_x86_64.qpkg to the release
```

Users can then download the QPKG directly from the GitHub releases page without needing to build it themselves.

## License

This build system is provided for building GPL-licensed kernel modules. The r8152 driver is licensed under GPL v2.

## Contributing

Contributions welcome! Areas for improvement:
- Support for additional architectures (ARM)
- Support for different kernel versions
- Additional driver patches
- Improved error handling
- CI/CD integration

## Disclaimer

This is an unofficial build. Test thoroughly before using in production. Always backup your data before installing kernel modules.

## Support

For issues:
1. Check installation log: `cat /share/CACHEDEV1_DATA/.qpkg/RTL8159_Driver/install.log`
2. Check kernel messages: `dmesg | grep r8152`
3. Verify kernel version: `uname -r` (should be 5.10.60)
4. Verify architecture: `uname -m` (should be x86_64)

---

**Author**: Built with Claude
**Contact**: hooyao@gmail.com
**Updated**: November 2025
