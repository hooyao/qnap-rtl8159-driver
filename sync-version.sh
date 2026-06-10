#!/bin/bash
#
# sync-version.sh - Propagate the Realtek driver version everywhere from a single
# source of truth (versions.yml).
#
# Why this exists:
#   The build itself already reads versions.yml directly
#   (build.sh -> build_driver.sh / build_qpkg.sh), so the COMPILED driver, the
#   PACKAGED QPKG version and the Web UI version always match versions.yml at build
#   time. This script keeps the *committed* human-facing copies (package manifest
#   default, web UI, README, developer guide) from drifting, so a version bump is a
#   single command instead of editing ~9 files by hand.
#
# Usage:
#   ./sync-version.sh            # re-sync all references to the current versions.yml
#   ./sync-version.sh 2.21.5     # bump versions.yml to 2.21.5 AND propagate everywhere
#   NEW=2.21.5 ./sync-version.sh # same as above
#
# NOTE: The driver's internal release DATE (shown by `modinfo`, e.g. "2025/10/28")
#       lives inside the Realtek source and is only known after download/build. It is
#       deliberately NOT tracked here - read it from the built module if you need it.
set -e

cd "$(dirname "$0")"

if [ ! -f versions.yml ]; then
    echo "ERROR: versions.yml not found (run from the repository root)"
    exit 1
fi

# Current version in versions.yml (the source of truth)
OLD=$(grep '^driver_version:' versions.yml | sed 's/driver_version:[[:space:]]*"\(.*\)"/\1/' | tr -d '"' | tr -d "'")
if [ -z "${OLD}" ]; then
    echo "ERROR: could not read 'driver_version' from versions.yml"
    exit 1
fi

# Target version: positional arg, then $NEW, otherwise keep current (pure re-sync)
NEW="${1:-${NEW:-$OLD}}"

if [ "${OLD}" = "${NEW}" ]; then
    echo "Re-syncing all references to driver version: ${NEW}"
else
    echo "Bumping driver version: ${OLD} -> ${NEW}"
fi

# Escape dots so OLD can be used safely in a sed regex (e.g. 2.20.1 -> 2\.20\.1)
OLD_RE="${OLD//./\\.}"

# 1) Single source of truth
sed -i "s/^driver_version:.*/driver_version: \"${NEW}\"/" versions.yml

# 2) Structured committed files (anchored; also re-written at build time)
sed -i "s/^QPKG_VER=.*/QPKG_VER=\"${NEW}\"/" qpkg/RTL8159_Driver/qpkg.cfg
sed -i "s|\(<strong>Version:</strong>\)[^<]*<|\1 ${NEW}<|" qpkg/RTL8159_Driver/shared/web/index.html

# 3) Free-text references: replace the previous exact version string. Using the full
#    OLD string (e.g. "2.20.1") is safe - it will not collide with the kernel (5.10.60)
#    or QTS (5.2.3) versions. Skipped on a pure re-sync (OLD == NEW).
if [ "${OLD}" != "${NEW}" ]; then
    for f in README.md .claude/CLAUDE.md versions.yml; do
        [ -f "$f" ] && sed -i "s/${OLD_RE}/${NEW}/g" "$f"
    done
fi

echo ""
echo "Done. Files updated from versions.yml:"
echo "  - versions.yml            (driver_version)"
echo "  - qpkg/.../qpkg.cfg       (QPKG_VER)"
echo "  - qpkg/.../web/index.html (Version label)"
echo "  - README.md, .claude/CLAUDE.md (docs)"
echo ""
echo "Review with: git diff"
