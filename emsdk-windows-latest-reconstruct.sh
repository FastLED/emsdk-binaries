#!/bin/bash

# EMSDK Archive Reconstruction Script
# This script reconstructs the original tar.xz file from split parts

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Get the base name from the script name
BASE_NAME="${0%-reconstruct.sh}"
ARCHIVE_NAME="${BASE_NAME}.tar.xz"

echo "Reconstructing ${ARCHIVE_NAME} from split parts..."

# Check if all parts are present
PARTS=()
for part in "${BASE_NAME}".tar.xz.part*; do
    if [ -f "$part" ]; then
        PARTS+=("$part")
    fi
done

if [ ${#PARTS[@]} -eq 0 ]; then
    echo "ERROR: No split parts found matching pattern ${BASE_NAME}.tar.xz.part*"
    exit 1
fi

echo "Found ${#PARTS[@]} parts to reconstruct"

# Sort parts to ensure correct order
IFS=$'\n' PARTS=($(sort <<<"${PARTS[*]}"))

# Reconstruct the archive
cat "${PARTS[@]}" > "$ARCHIVE_NAME"

if [ -f "$ARCHIVE_NAME" ]; then
    echo "Successfully reconstructed: $ARCHIVE_NAME"
    
    # Verify the archive
    if command -v xz >/dev/null 2>&1 && xz -t "$ARCHIVE_NAME" 2>/dev/null; then
        echo "Archive integrity verified"
    else
        echo "WARNING: Could not verify archive integrity (xz command not available or archive corrupted)"
    fi
    
    echo ""
    echo "To extract the EMSDK:"
    echo "  tar -xJf $ARCHIVE_NAME"
    echo "  cd emsdk"
    echo "  source ./emsdk_env.sh"
    echo ""
    echo "Optional: Remove split parts after successful reconstruction:"
    printf "  rm"
    for part in "${PARTS[@]}"; do
        printf " '%s'" "$part"
    done
    echo ""
else
    echo "ERROR: Failed to reconstruct archive"
    exit 1
fi
