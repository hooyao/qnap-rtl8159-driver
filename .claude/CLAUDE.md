# Claude Development Guide - RTL8159 QNAP Driver

## Project Status: ✅ COMPLETE AND WORKING

**Last Updated**: November 18, 2025
**Status**: Production Ready
**Driver Version**: v2.20.1 with RTL8159 support
**Target**: QNAP x86_64 systems running QuTS hero h5.2.x (kernel 5.10.60-qnap)

---

## Quick Start (For New Claude Sessions)

```bash
# 1. GPL source auto-managed via versions.yml
./prepare_gpl_source.sh  # Auto-downloads if needed

# 2. Build everything
export DRIVER_VERSION=2.20.1
./build.sh all

# 3. Output
ls output/RTL8159_Driver_*.qpkg  # 126KB installer
ls output/driver/r8152.ko        # 391KB driver
```

---

## Critical Success Factors

### 1. Use QNAP's Actual GPL Kernel Source

**THE KEY INSIGHT**: QNAP's kernel is customized. You MUST use their GPL source, not vanilla Linux.

**Where GPL source comes from** (configured in `versions.yml`):
```yaml
gpl_source:
  kernel_version: "5.10.60"
  qts_version: "5.2.3"
  urls:  # Split archives - concatenated in order
    - "https://...QTS_Kernel_5.2.3.20250218.0.tar.gz"
    - "https://...QTS_Kernel_5.2.3.20250218.1.tar.gz"
```

**Auto-handled by**: `prepare_gpl_source.sh`
- Parses URLs from versions.yml
- Downloads if missing
- Combines split archives (`cat part0 part1 > combined`)
- Extracts to `GPL_QTS/`

### 2. Module Cache Issue (CRITICAL FIX)

**Problem**: System loads old module instead of new one from QPKG

**Root Cause**:
- `/lib/modules` is READ-ONLY on QNAP systems
- Trying to copy driver there fails silently
- After reboot, old driver loads from read-only filesystem

**Solution** (implemented in `package_routines`):
```bash
# Keep driver in QPKG directory (on writable data volume)
DRIVER_PATH="${QPKG_ROOT}/${DRIVER_FILE}"

# Unload old module
rmmod r8152

# Load from QPKG directory (bypasses /lib/modules entirely)
insmod ${DRIVER_PATH}

# Verify using srcversion (NOT size!)
LOADED_SRC=$(cat /sys/module/r8152/srcversion)
FILE_SRC=$(strings ${DRIVER_PATH} | grep "^srcversion=" | cut -d= -f2)
if [ "$LOADED_SRC" = "$FILE_SRC" ]; then
    # Correct module loaded
fi
```

**Why this works**:
- Driver loads from persistent data volume
- Uses `insmod` with absolute path
- Verifies using srcversion (unique identifier), not size

**IMPORTANT**: Runtime module size in `/proc/modules` (~294KB) is DIFFERENT from file size (~391KB). This is normal - kernel strips debug symbols. Use `srcversion` to verify!

### 3. Build System Architecture

```
versions.yml          # Single source of truth (GPL URLs, versions)
     ↓
prepare_gpl_source.sh # Downloads & extracts GPL source
     ↓
build.sh all          # Orchestrator
     ↓
├─ build_image()      # Creates Docker image
│  └─ Dockerfile      # Copies GPL_QTS/src/linux-5.10 into image
│
├─ compile_driver()   # Runs inside Docker
│  └─ build_driver.sh # Patches + compiles driver
│
└─ create_qpkg()      # Packages driver
   └─ build_qpkg.sh   # Uses QDK to create QPKG
```

### 4. Driver Patching (RTL8157/8159 Support)

**Location**: `build_driver.sh:patch_driver()`

**Adds device IDs** to USB device table:
```bash
# Find RTL8156 entry, inject RTL8157 and RTL8159 after it
sed -i '/USB_DEVICE(VENDOR_ID_REALTEK, 0x8156)/a\
\t{ USB_DEVICE_AND_INTERFACE_INFO(VENDOR_ID_REALTEK, 0x8157, ...) },\
\t{ USB_DEVICE_AND_INTERFACE_INFO(VENDOR_ID_REALTEK, 0x815a, ...) },' r8152.c
```

**Result**: Driver recognizes USB devices `0bda:8157` (RTL8157) and `0bda:815a` (RTL8159)

---

## Failure Lessons Learned

### ❌ What Doesn't Work

1. **Vanilla Linux Kernel**
   - Problem: Symbol version mismatch
   - Why: QNAP's kernel has custom exports
   - Symptom: `Unknown symbol` errors, `invalid module format`

2. **Patching Module.symvers Alone**
   - Problem: Not sufficient
   - Why: Kernel has other customizations beyond symbols
   - Symptom: Module loads but crashes or doesn't detect device

3. **Relying on modprobe After Install**
   - Problem: Loads cached old module
   - Why: Module cache not cleared
   - Symptom: Module shows 229KB size, device not detected

4. **Hardcoded GPL URLs in Scripts**
   - Problem: Hard to maintain
   - Why: Each QTS version needs different URLs
   - Symptom: Scripts need editing for updates

### ✅ What Works

1. **QNAP's Complete GPL Source**
   - Solution: Use pre-built kernel from GPL archive
   - Why: Exact match with running kernel
   - Files: Complete kernel tree with Module.symvers

2. **Force Load with insmod**
   - Solution: Clear cache, use `insmod /path/to/r8152.ko`
   - Why: Bypasses module alias cache
   - Result: Correct module loads immediately

3. **YAML Configuration**
   - Solution: `versions.yml` contains all URLs
   - Why: Single source of truth, easy updates
   - Benefit: No shell script editing needed

4. **Fail-Fast Checks**
   - Solution: Verify GPL source before Docker build
   - Why: Catches missing files early
   - Benefit: Clear error messages, no wasted builds

---

## Configuration Management

### versions.yml Structure

```yaml
driver_version: "2.20.1"  # Realtek driver to download

gpl_source:
  kernel_version: "5.10.60"      # Target kernel
  qts_version: "5.2.3"           # QTS release
  build_date: "20250218"         # GPL package date

  urls:  # Can be 1-N split archives
    - "https://url/to/part0.tar.gz"
    - "https://url/to/part1.tar.gz"
    # ... add more parts if needed

target_model: "TS-X65U"  # Kernel config directory
```

**Benefits**:
- All versions in one place
- Easy to update for new QTS versions
- Supports split archives (auto-combined)
- Self-documenting

### To Update for New QTS Version

1. Edit `versions.yml`:
   - Update `gpl_source.kernel_version`
   - Update `gpl_source.qts_version`
   - Update `gpl_source.urls` list

2. Run: `./prepare_gpl_source.sh`

3. Build: `./build.sh all`

---

## Troubleshooting Guide

### Issue: How to Verify Correct Module is Loaded

**IMPORTANT**: `/proc/modules` shows runtime memory size, NOT file size!
- File size: ~391KB (399848 bytes)
- Runtime size: ~288KB (294912 bytes) - this is NORMAL

**Correct way to verify**:
```bash
# 1. Get srcversion from loaded module
LOADED_SRC=$(cat /sys/module/r8152/srcversion)
echo "Loaded module srcversion: $LOADED_SRC"

# 2. Get srcversion from QPKG driver file
QPKG_PATH=$(getcfg "RTL8159_Driver" Install_Path -f /etc/config/qpkg.conf)
FILE_SRC=$(strings "$QPKG_PATH/r8152.ko" | grep "^srcversion=" | cut -d= -f2)
echo "QPKG driver srcversion: $FILE_SRC"

# 3. Compare - they should match!
if [ "$LOADED_SRC" = "$FILE_SRC" ]; then
    echo "✓ Correct module loaded!"
else
    echo "✗ Wrong module loaded!"
fi

# To get srcversion from build output:
strings output/driver/r8152.ko | grep "^srcversion="
```

**Wrong way**: Comparing `/proc/modules` size to file size (they will always differ)

**Fix if wrong module loaded**:
```bash
sudo rmmod r8152
sudo insmod /share/ZFSXXX_DATA/.qpkg/RTL8159_Driver/r8152.ko
```

### Issue: "Unknown symbol" Errors

**Symptom**: `dmesg` shows `Unknown symbol in module`

**Cause**: Compiled against wrong kernel

**Check**:
```bash
strings /lib/modules/*/r8152.ko | grep vermagic
# Should be: 5.10.60-qnap SMP mod_unload (no "modversions")
```

**Fix**: Rebuild with QNAP GPL source (check `GPL_QTS/` exists)

### Issue: USB Device Not Detected

**Symptom**: `lsusb` shows device but no `ethX` interface

**Check sequence**:
```bash
# 1. Check module loaded
lsmod | grep r8152

# 2. Verify CORRECT module is loaded (compare srcversions)
LOADED_SRC=$(cat /sys/module/r8152/srcversion)
QPKG_PATH=$(getcfg "RTL8159_Driver" Install_Path -f /etc/config/qpkg.conf)
FILE_SRC=$(strings "$QPKG_PATH/r8152.ko" | grep "^srcversion=" | cut -d= -f2)
echo "Loaded: $LOADED_SRC"
echo "QPKG:   $FILE_SRC"
[ "$LOADED_SRC" = "$FILE_SRC" ] && echo "✓ Match!" || echo "✗ Mismatch!"

# 3. Check module version
cat /sys/module/r8152/version
# Should be: v2.20.1 (2025/05/13)

# 4. Check USB device
lsusb | grep 0bda:815a

# 5. Check dmesg
dmesg | tail -30 | grep r8152
```

**Fix order**:
1. If wrong srcversion → Reload from QPKG directory (see above)
2. If USB not recognized → Check dmesg for errors
3. If no interface created → Check cable/port

**IMPORTANT**: Don't check module size! Runtime size (~294KB) differs from file size (~391KB).

### Issue: Build Fails "GPL source not found"

**Symptom**: Docker build fails at COPY instruction

**Check**:
```bash
ls GPL_QTS/src/linux-5.10/Makefile
# Should exist
```

**Fix**:
```bash
./prepare_gpl_source.sh
# Auto-downloads from versions.yml if files missing
```

---

## Development Workflow

### For Driver Version Updates

```bash
# 1. Edit versions.yml
driver_version: "2.21.0"  # Update this

# 2. Build
./build.sh all

# 3. Test
scp output/*.qpkg admin@qnap:/share/Public/
# Install and verify
```

### For New QTS Versions

```bash
# 1. Find GPL source URLs from QNAP SourceForge
# Visit: https://sourceforge.net/projects/qosgpl/files/

# 2. Edit versions.yml
gpl_source:
  kernel_version: "5.10.70"  # New kernel
  qts_version: "5.2.4"       # New QTS
  urls:
    - "https://new/url/part0.tar.gz"
    - "https://new/url/part1.tar.gz"

# 3. Clean and rebuild
rm -rf GPL_QTS
./prepare_gpl_source.sh
./build.sh all
```

### For New Device IDs

Edit `build_driver.sh:patch_driver()`:
```bash
# Add after RTL8159 (0x815a)
sed -i '/USB_DEVICE(VENDOR_ID_REALTEK, 0x815a)/a\
\t{ USB_DEVICE_AND_INTERFACE_INFO(VENDOR_ID_REALTEK, 0x815b, ...) },' r8152.c
```

### For Other QNAP Models

```bash
# 1. Check available models
ls GPL_QTS/kernel_cfg/
# Example: TS-X73, TS-X82, TS-531P, etc.

# 2. Edit versions.yml
target_model: "TS-X73"  # Change this

# 3. Edit Dockerfile
COPY GPL_QTS/kernel_cfg/TS-X73/linux-5.10-x86_64.config /build/kernel/

# 4. Rebuild
./build.sh image
./build.sh all
```

---

## Build System Improvements (November 2025)

### 1. YAML-Based Configuration
- ✅ All versions in `versions.yml`
- ✅ GPL URLs as list (supports N parts)
- ✅ Easy to update for new QTS versions

### 2. Automatic GPL Management
- ✅ `prepare_gpl_source.sh` parses YAML
- ✅ Auto-downloads from URLs if files missing
- ✅ Combines split archives intelligently
- ✅ Extracts to `GPL_QTS/`

### 3. Fail-Fast Validation
- ✅ Checks GPL source before Docker build
- ✅ Clear error messages with fix instructions
- ✅ No wasted Docker builds

### 4. Installation Cache Fix
- ✅ Auto-clears module cache
- ✅ Force-loads with `insmod`
- ✅ Verifies module size after load
- ✅ Warns if wrong module detected

### 5. Clear Build Messages
- ❌ OLD: "No kernel source provided - will download generic kernel"
- ✅ NEW: "Using QNAP GPL kernel source from Docker image"

---

## Testing Checklist

### Pre-Build
- [ ] `versions.yml` has correct GPL URLs
- [ ] GPL source exists: `ls GPL_QTS/src/linux-5.10/`
- [ ] Docker running: `docker --version`

### Post-Build
- [ ] QPKG created: `ls output/*.qpkg` (~126KB)
- [ ] Driver compiled: `ls output/driver/r8152.ko` (~391KB)
- [ ] Driver version: `strings output/driver/r8152.ko | grep "v2.20"`
- [ ] Driver srcversion: `strings output/driver/r8152.ko | grep "^srcversion="`
- [ ] Device IDs present: `strings output/driver/r8152.ko | grep 815a`

### Post-Install (on QNAP)
- [ ] Module loaded: `lsmod | grep r8152`
- [ ] Correct module: Compare `cat /sys/module/r8152/srcversion` with `strings /path/to/r8152.ko | grep "^srcversion="`
- [ ] USB detected: `lsusb | grep 0bda:815a`
- [ ] Interface created: `ip link show` (new ethX)
- [ ] No errors: `dmesg | grep r8152`
- [ ] Survives reboot: Auto-loads after reboot
- [ ] Note: Runtime size (~294KB) is NORMAL, don't check size!

---

## Key Files Reference

### Configuration
- `versions.yml` - All version settings and GPL URLs
- `Dockerfile` - Build environment (copies GPL source)
- `.gitignore` - Excludes GPL files from git

### Build Scripts
- `build.sh` - Main orchestrator
- `prepare_gpl_source.sh` - GPL download & extract
- `build_driver.sh` - Driver compilation
- `build_qpkg.sh` - QPKG packaging

### Installation
- `qpkg/RTL8159_Driver/package_routines` - Install/remove logic
- `qpkg/RTL8159_Driver/qpkg.cfg` - Package metadata

### Documentation
- `README.md` - User guide
- `.claude/CLAUDE.md` - This file (developer guide)
- `gpl_source/README.md` - GPL source instructions

---

## Critical Insights for Future Claude Sessions

### What Made This Work

1. **GPL Source is Everything**
   - QNAP's kernel is too customized for vanilla sources
   - Need complete pre-built kernel tree
   - Module.symvers alone is insufficient

2. **Module Cache is a Hidden Problem**
   - System caches module metadata
   - New file installed but old module loads
   - Must clear cache and use `insmod` with absolute path

3. **YAML Configuration is Superior**
   - Single source of truth
   - Easy to update
   - No shell script editing

4. **Fail-Fast Saves Time**
   - Check GPL before Docker build
   - Clear errors guide user to fix
   - No wasted build attempts

### If Starting This Project Again

1. **Day 1**: Get complete QNAP GPL source
2. **Day 2**: Verify it's pre-built (has .o files, Module.symvers)
3. **Day 3**: Copy entire kernel tree to Docker image
4. **Day 4**: Compile driver, don't touch vermagic/symbols
5. **Day 5**: Fix module cache loading issue

Don't waste time trying to:
- Use vanilla kernel with patching
- Manipulate Module.symvers manually
- Download GPL during Docker build (too slow)

### Success Metrics

- ✅ Driver compiles: 391KB r8152.ko file
- ✅ Module loads: `lsmod | grep r8152`
- ✅ Correct module: srcversion matches QPKG driver file
- ✅ Version correct: v2.20.1 (2025/05/13)
- ✅ Device detects: USB device → ethX interface
- ✅ Network works: Can ping/transfer data
- ✅ Survives reboot: Auto-loads on boot
- ⚠️ Runtime size: ~294KB in /proc/modules (NORMAL, don't check this!)

---

## Status Summary

**Project**: ✅ Complete and Production Ready
**Confidence**: High (tested on actual hardware)
**Reproducibility**: Excellent (Docker-based)
**Maintainability**: Good (YAML config, clear docs)
**User Experience**: Smooth (automatic install, cache fix)

**Last verified**: November 18, 2025
**Hardware**: QNAP TS-X65U / QuTS hero h5.2.7.3251
**Device**: RTL8159 (0bda:815a) 10GbE USB adapter

---

*This guide contains all critical knowledge for building and troubleshooting the RTL8159 driver for QNAP NAS systems.*
