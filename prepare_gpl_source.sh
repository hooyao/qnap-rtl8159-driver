#!/bin/bash
#
# prepare_gpl_source.sh - Extract QNAP GPL kernel source
#
# This script reads GPL source URLs from versions.yml,
# downloads and combines archives (in order), then extracts to GPL_QTS/
#
# Configuration:
#   - Primary: versions.yml (gpl_source.urls list)
#   - Fallback: Local files in gpl_source/
#

set -e

GPL_SOURCE_DIR="gpl_source"
GPL_TARGET_DIR="GPL_QTS"
VERSIONS_FILE="versions.yml"

# Function to parse YAML and extract GPL URLs
parse_gpl_urls() {
    if [ ! -f "$VERSIONS_FILE" ]; then
        echo "Warning: $VERSIONS_FILE not found" >&2
        return 1
    fi

    # Extract URLs from YAML (simple parsing - looks for lines under urls: section)
    local in_urls_section=0
    local urls=()

    while IFS= read -r line; do
        # Check if we're entering the urls section
        if [[ "$line" =~ ^[[:space:]]*urls:[[:space:]]*$ ]]; then
            in_urls_section=1
            continue
        fi

        # If in urls section and line starts with -, extract URL
        if [ "$in_urls_section" -eq 1 ]; then
            if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*\"(.+)\"[[:space:]]*$ ]]; then
                urls+=("${BASH_REMATCH[1]}")
            elif [[ "$line" =~ ^[[:space:]]*-[[:space:]]*\'(.+)\'[[:space:]]*$ ]]; then
                urls+=("${BASH_REMATCH[1]}")
            elif [[ "$line" =~ ^[[:space:]]*[a-zA-Z_] ]]; then
                # End of urls section (new key found)
                break
            fi
        fi
    done < "$VERSIONS_FILE"

    # Export URLs
    if [ ${#urls[@]} -gt 0 ]; then
        for url in "${urls[@]}"; do
            echo "$url"
        done
        return 0
    else
        return 1
    fi
}

# Function to get kernel version from versions.yml (major.minor format)
get_kernel_version() {
    if [ -f "$VERSIONS_FILE" ]; then
        local full_ver=$(grep 'kernel_version:' "$VERSIONS_FILE" | sed 's/.*kernel_version:[[:space:]]*"\(.*\)".*/\1/' | head -1)
        # Extract major.minor (e.g., 5.10.60 -> 5.10)
        echo "$full_ver" | cut -d'.' -f1-2
    else
        echo "5.10"
    fi
}

echo "========================================"
echo "QNAP GPL Kernel Source Preparation"
echo "========================================"
echo ""

# Check if GPL_QTS already exists
if [ -d "${GPL_TARGET_DIR}/src/linux-5.10" ]; then
    KERNEL_VER=$(get_kernel_version)
    echo "✓ GPL source already extracted: ${GPL_TARGET_DIR}/src/linux-${KERNEL_VER}/"
    echo "  Skipping extraction. To re-extract, remove ${GPL_TARGET_DIR}/ first."
    exit 0
fi

# Create gpl_source directory if it doesn't exist
mkdir -p "${GPL_SOURCE_DIR}"

# Try to find existing archives first
echo "[1/5] Checking for GPL kernel archives..."
EXISTING_FILES=($(find "${GPL_SOURCE_DIR}" -name "*.tar.gz" -type f | sort))

# If no local files, try to parse URLs from versions.yml
if [ ${#EXISTING_FILES[@]} -eq 0 ]; then
    echo "  No local archives found."
    echo "  Reading GPL URLs from ${VERSIONS_FILE}..."
    echo ""

    # Parse URLs from YAML
    mapfile -t GPL_URLS < <(parse_gpl_urls)

    if [ ${#GPL_URLS[@]} -eq 0 ]; then
        echo "✗ Error: No GPL URLs found in ${VERSIONS_FILE}"
        echo ""
        echo "  Expected format in ${VERSIONS_FILE}:"
        echo "    gpl_source:"
        echo "      urls:"
        echo "        - \"https://url/to/part0.tar.gz\""
        echo "        - \"https://url/to/part1.tar.gz\""
        echo ""
        exit 1
    fi

    echo "  Found ${#GPL_URLS[@]} URL(s) in ${VERSIONS_FILE}"
    echo ""

    # Download each URL
    DOWNLOADED_FILES=()
    for i in "${!GPL_URLS[@]}"; do
        url="${GPL_URLS[$i]}"
        # Extract filename from URL (remove query parameters)
        filename=$(basename "$url" | cut -d'?' -f1)
        filepath="${GPL_SOURCE_DIR}/${filename}"

        echo "  [$((i+1))/${#GPL_URLS[@]}] Downloading: $(basename "$filename")"
        echo "      URL: $url"

        if ! wget --no-check-certificate -q --show-progress -O "$filepath" "$url"; then
            echo "  ✗ Error: Failed to download"
            rm -f "$filepath"
            exit 1
        fi

        DOWNLOADED_FILES+=("$filepath")
        echo "      ✓ Downloaded: $(du -h "$filepath" | cut -f1)"
    done

    echo ""
    echo "  ✓ All downloads complete!"
    ARCHIVE_FILES=("${DOWNLOADED_FILES[@]}")
else
    echo "  ✓ Found ${#EXISTING_FILES[@]} local archive(s)"
    ARCHIVE_FILES=("${EXISTING_FILES[@]}")
fi

echo ""
echo "[2/5] Preparing to combine archives..."
for i in "${!ARCHIVE_FILES[@]}"; do
    echo "  Part $((i+1)): $(basename "${ARCHIVE_FILES[$i]}") ($(du -h "${ARCHIVE_FILES[$i]}" | cut -f1))"
done

# Determine combined filename
if [ ${#ARCHIVE_FILES[@]} -eq 1 ]; then
    # Single archive - no combination needed
    COMBINED="${ARCHIVE_FILES[0]}"
    echo "  Using single archive (no combination needed)"
else
    # Multiple archives - combine them
    BASENAME=$(basename "${ARCHIVE_FILES[0]}" | sed 's/\.0\.tar\.gz$//' | sed 's/\.tar\.gz$//')
    COMBINED="${BASENAME}_combined.tar.gz"

    echo ""
    echo "[3/5] Combining ${#ARCHIVE_FILES[@]} archives..."
    echo "  Output: ${COMBINED}"

    cat "${ARCHIVE_FILES[@]}" > "${COMBINED}"

    if [ ! -f "${COMBINED}" ]; then
        echo "✗ Error: Failed to combine archives"
        exit 1
    fi

    COMBINED_SIZE=$(du -h "${COMBINED}" | cut -f1)
    echo "  ✓ Combined archive size: ${COMBINED_SIZE}"
fi

echo ""
echo "[4/5] Extracting GPL source..."
echo "  This may take a few minutes..."

tar -xzf "${COMBINED}" 2>&1 | head -20 || true

if [ ! -d "${GPL_TARGET_DIR}" ]; then
    echo "✗ Error: Extraction failed, ${GPL_TARGET_DIR}/ not created"
    exit 1
fi

echo "  ✓ Extracted to: ${GPL_TARGET_DIR}/"

echo ""
echo "[5/5] Verifying kernel source..."

# Get kernel version from config
KERNEL_VER=$(get_kernel_version)

# Verify required files exist
REQUIRED_FILES=(
    "${GPL_TARGET_DIR}/src/linux-${KERNEL_VER}/Makefile"
    "${GPL_TARGET_DIR}/src/linux-${KERNEL_VER}/Module.symvers"
    "${GPL_TARGET_DIR}/kernel_cfg"
)

ALL_OK=true
for file in "${REQUIRED_FILES[@]}"; do
    if [ -e "$file" ]; then
        echo "  ✓ Found: $file"
    else
        echo "  ✗ Missing: $file"
        ALL_OK=false
    fi
done

# Check for model-specific configs
echo ""
echo "  Available model configurations:"
if [ -d "${GPL_TARGET_DIR}/kernel_cfg" ]; then
    ls -1 "${GPL_TARGET_DIR}/kernel_cfg/" | head -10 | while read model; do
        echo "    - $model"
    done
    MODEL_COUNT=$(ls -1 "${GPL_TARGET_DIR}/kernel_cfg/" | wc -l)
    if [ "$MODEL_COUNT" -gt 10 ]; then
        echo "    ... and $((MODEL_COUNT - 10)) more"
    fi
else
    echo "    (none found)"
    ALL_OK=false
fi

# Cleanup combined archive if we created it
if [ ${#ARCHIVE_FILES[@]} -gt 1 ] && [ -f "${COMBINED}" ]; then
    echo ""
    echo "Cleanup: Removing combined archive..."
    rm -f "${COMBINED}"
    echo "  ✓ Removed: ${COMBINED}"
fi

echo ""
echo "========================================"
if [ "$ALL_OK" = true ]; then
    echo "✓ GPL source preparation complete!"
    echo "========================================"
    echo ""
    echo "Kernel version: ${KERNEL_VER}"
    echo "Source location: ${GPL_TARGET_DIR}/src/linux-${KERNEL_VER}/"
    echo ""
    echo "You can now run: ./build.sh all"
    exit 0
else
    echo "✗ GPL source preparation incomplete"
    echo "========================================"
    echo ""
    echo "Some required files are missing."
    echo "Please check the extraction and try again."
    exit 1
fi
