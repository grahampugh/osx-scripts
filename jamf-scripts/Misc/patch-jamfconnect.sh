#!/bin/bash

# Script to patch JamfConnect.pkg to not launch if Setup Assistant, JSDE, or Setup Manager is running
# Usage: ./patch-jamfconnect.sh /path/to/JamfConnect.dmg

set -e

# Check if DMG path is provided
if [[ -z "$1" ]]; then
    echo "Error: Please provide the path to JamfConnect.dmg"
    echo "Usage: $0 /path/to/JamfConnect.dmg"
    exit 1
fi

DMG_PATH="$1"

# Verify DMG exists
if [ ! -f "$DMG_PATH" ]; then
    echo "Error: DMG file not found at $DMG_PATH"
    exit 1
fi

echo "Mounting DMG..."
MOUNT_POINT=$(hdiutil attach "$DMG_PATH" -nobrowse -noverify -noautoopen | grep "/Volumes/" | awk '{print $3}')

if [[ -z "$MOUNT_POINT" ]]; then
    echo "Error: Failed to mount DMG"
    exit 1
fi

echo "DMG mounted at: $MOUNT_POINT"

# Create temporary scratch space
SCRATCH_DIR=$(mktemp -d)
echo "Created scratch space at: $SCRATCH_DIR"

# Cleanup function
# shellcheck disable=SC2329
cleanup() {
    echo "Cleaning up..."
    if [[ -d "$SCRATCH_DIR" ]]; then
        rm -rf "$SCRATCH_DIR"
    fi
    if [[ -n "$MOUNT_POINT" && -d "$MOUNT_POINT" ]]; then
        hdiutil detach "$MOUNT_POINT" -quiet
    fi
}

trap cleanup EXIT

# Change to scratch directory
cd "$SCRATCH_DIR"

# Find JamfConnect.pkg
PKG_PATH=$(find "$MOUNT_POINT" -name "JamfConnectLogin.pkg" -type f | head -n 1)

if [[ ! -f "$PKG_PATH" ]]; then
    echo "Error: JamfConnectLogin.pkg not found in mounted volume"
    exit 1
fi

echo "Found package at: $PKG_PATH"

# Expand the package
echo "Expanding package..."
pkgutil --expand "$PKG_PATH" JamfConnectPkg

# Locate and modify the postinstall script
POSTINSTALL_PATH="JamfConnectPkg/JamfConnectLogin.pkg/Scripts/postinstall"

if [[ ! -f "$POSTINSTALL_PATH" ]]; then
    echo "Error: postinstall script not found at expected path"
    exit 1
fi

echo "Patching postinstall script..."

# Replace the line using awk for reliable multiline replacement, preserving indentation
awk '
{
    if ($0 ~ /\[\[ \$\( \/usr\/bin\/pgrep "Setup Assistant" \) \]\] && exit 0/) {
        match($0, /^[[:space:]]*/);
        indent = substr($0, RSTART, RLENGTH);
        print indent "if /usr/bin/pgrep -xq \"Setup Assistant\" || /usr/bin/pgrep -xq \"Setup Manager\" || /usr/bin/pgrep -xq \"JSDE\"; then"
        print indent "    exit 0"
        print indent "fi"
    } else {
        print $0
    }
}
' "$POSTINSTALL_PATH" > "$POSTINSTALL_PATH.tmp" && mv "$POSTINSTALL_PATH.tmp" "$POSTINSTALL_PATH"

# show current ownership and permissions for postinstall script
echo "Postinstall script ownership and permissions before change:"
ls -l "$POSTINSTALL_PATH"

# Ensure correct ownership and permissions for postinstall script
# chown root:wheel "$POSTINSTALL_PATH"
chmod 755 "$POSTINSTALL_PATH"

echo "Recompressing package..."
pkgutil --flatten JamfConnectPkg JamfConnectPatched.pkg

# Move patched package to a permanent location (Desktop or original location)
OUTPUT_DIR=$(dirname "$DMG_PATH")
OUTPUT_PATH="$OUTPUT_DIR/JamfConnectPatched.pkg"

mv JamfConnectPatched.pkg "$OUTPUT_PATH"

echo ""
echo "Successfully patched JamfConnect package"
echo "Patched package saved to: $OUTPUT_PATH"
echo ""
