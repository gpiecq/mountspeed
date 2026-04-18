#!/bin/bash
set -e

ADDON_NAME="MountSpeed"
TOC_FILE="${ADDON_NAME}.toc"

if [ ! -f "$TOC_FILE" ]; then
    echo "ERROR: $TOC_FILE not found. Run this script from the addon root."
    exit 1
fi

VERSION=$(grep "^## Version:" "$TOC_FILE" | sed 's/## Version: //' | tr -d '\r')
ZIPNAME="${ADDON_NAME}.zip"

echo "Packaging ${ADDON_NAME} v${VERSION}..."

rm -f "$ZIPNAME"
rm -rf build

mkdir -p "build/$ADDON_NAME"

# Source files (kept in sync with the .toc load order)
cp "$TOC_FILE" \
   Core.lua \
   Slots.lua \
   Swap.lua \
   UI.lua \
   "build/$ADDON_NAME/"

# Optional docs (only copy if present so the script works on a fresh checkout)
[ -f CHANGELOG.md ] && cp CHANGELOG.md "build/$ADDON_NAME/"
[ -f README.md ]    && cp README.md    "build/$ADDON_NAME/"
[ -f LICENSE ]      && cp LICENSE      "build/$ADDON_NAME/"

# Prefer the standard `zip` tool (Linux / macOS / Git Bash with zip installed).
# Fall back to PowerShell's Compress-Archive on Windows hosts that lack it.
if command -v zip >/dev/null 2>&1; then
    (cd build && zip -rq "../$ZIPNAME" "$ADDON_NAME")
elif command -v powershell.exe >/dev/null 2>&1; then
    echo "zip not found, falling back to PowerShell Compress-Archive..."
    powershell.exe -NoProfile -Command \
        "Compress-Archive -Path 'build\\${ADDON_NAME}' -DestinationPath '${ZIPNAME}' -Force" \
        >/dev/null
else
    echo "ERROR: neither 'zip' nor 'powershell.exe' is available to create the archive."
    exit 1
fi

rm -rf build

echo "Created $ZIPNAME"
echo ""
echo "Install:"
echo "  Extract into <WoW>/Interface/AddOns/"
