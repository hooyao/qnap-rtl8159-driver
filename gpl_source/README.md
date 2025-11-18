# QNAP GPL Kernel Source

This directory is for QNAP GPL kernel source archives.

## Required Files

Download both parts of the split archive from QNAP's SourceForge:

**For QTS/QuTS hero 5.2.3 (kernel 5.10.60-qnap):**

1. Download Part 0:
   - URL: https://sourceforge.net/projects/qosgpl/files/QNAP%20NAS%20GPL%20Source/QTS%205.2.3/QTS_Kernel_5.2.3.20250218.0.tar.gz/download
   - Save as: `QTS_Kernel_5.2.3.20250218.0.tar.gz`

2. Download Part 1:
   - URL: https://sourceforge.net/projects/qosgpl/files/QNAP%20NAS%20GPL%20Source/QTS%205.2.3/QTS_Kernel_5.2.3.20250218.1.tar.gz/download
   - Save as: `QTS_Kernel_5.2.3.20250218.1.tar.gz`

## File Naming Pattern

The build system will automatically detect and process files matching:
- `QTS_Kernel_*.0.tar.gz` (first part)
- `QTS_Kernel_*.1.tar.gz` (second part)

## Usage

1. Place both `.tar.gz` files in this directory
2. Run `./build.sh all`
3. The build system will:
   - Detect the split archives
   - Combine them automatically
   - Extract to GPL_QTS/
   - Build the driver

## File Structure After Processing

```
../GPL_QTS/
├── src/
│   └── linux-5.10/
└── kernel_cfg/
    └── TS-X65U/
```

## Notes

- Do NOT commit these `.tar.gz` files to git (they're in .gitignore)
- The GPL_QTS/ directory is also excluded from git
- Keep the original `.tar.gz` files for rebuilding if needed
- Both parts are required (the archive is split by QNAP)

## Alternative: Pre-extracted GPL Source

If you already have GPL_QTS/ extracted, you can skip downloading these files.
Just ensure GPL_QTS/src/linux-5.10/ exists with the kernel source.
