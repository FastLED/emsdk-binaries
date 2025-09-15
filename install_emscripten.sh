#!/bin/bash

set -e

# Create .build directory for all artifacts
BUILD_DIR="./.build"
mkdir -p "$BUILD_DIR"

EMSDK_DIR="$BUILD_DIR/emsdk"

# Set aggressive optimization flags for SDK compilation
export CFLAGS="-Oz -flto -ffunction-sections -fdata-sections -fno-exceptions -fno-rtti -fno-unwind-tables -fno-asynchronous-unwind-tables -fomit-frame-pointer -ffast-math -fno-stack-protector"
export CXXFLAGS="-Oz -flto -ffunction-sections -fdata-sections -fno-exceptions -fno-rtti -fno-unwind-tables -fno-asynchronous-unwind-tables -fomit-frame-pointer -ffast-math -fno-stack-protector"
export LDFLAGS="-Oz -flto -Wl,--gc-sections -Wl,--strip-all -Wl,--strip-debug -s"

# Additional optimization environment variables
export EMCC_OPTIMIZE_SIZE=1
export EMCC_CLOSURE=1
export CMAKE_BUILD_TYPE=MinSizeRel

echo "Setting optimization flags for SDK compilation:"
echo "CFLAGS: $CFLAGS"
echo "CXXFLAGS: $CXXFLAGS"
echo "LDFLAGS: $LDFLAGS"

if [ ! -d "$EMSDK_DIR" ]; then
    git clone https://github.com/emscripten-core/emsdk.git "$EMSDK_DIR" --depth=1
fi

cd "$EMSDK_DIR"
# Only pull if we have a full clone
if [ -d ".git" ]; then
    git pull
fi

./emsdk install latest
./emsdk activate latest
source ./emsdk_env.sh

emcc -v

echo "EMSDK installation completed. Creating archive..."

cd "$BUILD_DIR/.."

# Map uname output to GitHub Actions OS names for consistency, with Mac architecture detection
case "$(uname | tr '[:upper:]' '[:lower:]')" in
  linux) 
    OS_NAME="ubuntu-latest" 
    ;;
  darwin) 
    # Detect Mac architecture
    ARCH=$(uname -m)
    case "$ARCH" in
      arm64)
        OS_NAME="macos-arm64"
        ;;
      x86_64)
        OS_NAME="macos-x86_64"
        ;;
      *)
        # Fallback to generic macos-latest for unknown architectures
        OS_NAME="macos-latest"
        ;;
    esac
    ;;
  mingw*|cygwin*|msys*) 
    OS_NAME="windows-latest" 
    ;;
  *) 
    OS_NAME="$(uname | tr '[:upper:]' '[:lower:]')" 
    ;;
esac

ARTIFACT_NAME="emsdk-${OS_NAME}"

# Function to get file size in a cross-platform way
get_file_size() {
    local file="$1"
    if command -v stat >/dev/null 2>&1; then
        case "$(uname)" in
            Darwin|*BSD)
                stat -f%z "$file" 2>/dev/null
                ;;
            *)
                stat -c%s "$file" 2>/dev/null
                ;;
        esac
    else
        # Fallback: use ls and extract size
        ls -l "$file" 2>/dev/null | awk '{print $5}'
    fi
}

echo "Creating compressed artifact in .build directory: ${BUILD_DIR}/${ARTIFACT_NAME}.tar.xz"

# Create a highly compressed tarball with XZ compression (better than gzip)
echo "Using XZ compression with maximum compression level..."
cd "$BUILD_DIR"
XZ_OPT=-9 tar -cJf "${ARTIFACT_NAME}.tar.xz" emsdk
cd ..

# Check the size of the created artifact
size=$(get_file_size "${BUILD_DIR}/${ARTIFACT_NAME}.tar.xz")
if [ -n "$size" ] && [ "$size" -gt 0 ]; then
    size_mb=$((size / 1024 / 1024))
    echo "Created artifact: ${ARTIFACT_NAME}.tar.xz (${size_mb}MB)"
    
    if [ $size_mb -gt 95 ]; then
        echo "WARNING: Artifact is ${size_mb}MB, which exceeds GitHub's 95MB limit!"
        echo "Splitting archive into 95MB chunks..."
        
        # Split the tar.xz file into 95MB chunks
        split -b 95M "${BUILD_DIR}/${ARTIFACT_NAME}.tar.xz" "${BUILD_DIR}/${ARTIFACT_NAME}.tar.xz.part"
        
        # Remove the original large file
        rm "${BUILD_DIR}/${ARTIFACT_NAME}.tar.xz"
        
        # Check the created parts
        success=true
        total_size=0
        part_count=0
        
        for part in "${BUILD_DIR}/${ARTIFACT_NAME}".tar.xz.part*; do
            if [ -f "$part" ]; then
                part_count=$((part_count + 1))
                size=$(get_file_size "$part")
                if [ -n "$size" ] && [ "$size" -gt 0 ]; then
                    size_mb=$((size / 1024 / 1024))
                    total_size=$((total_size + size_mb))
                    echo "Created split part: $part (${size_mb}MB)"
                    
                    if [ $size_mb -gt 95 ]; then
                        echo "ERROR: Split part $part is still ${size_mb}MB, exceeding the limit!"
                        success=false
                    fi
                else
                    echo "WARNING: Could not determine size of $part"
                fi
            fi
        done
        
        if [ "$success" = true ]; then
            echo "Successfully split archive into ${part_count} parts under the size limit."
            echo "Total compressed size: ${total_size}MB across ${part_count} parts"
            
            # Create a reconstruction script
            echo "Creating reconstruction script..."
            cat > "${BUILD_DIR}/${ARTIFACT_NAME}-reconstruct.sh" << 'EOF'
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
EOF
            
            # Make the reconstruction script executable
            chmod +x "${BUILD_DIR}/${ARTIFACT_NAME}-reconstruct.sh"
            
            # Create a manifest file listing all parts
            echo "Creating manifest file..."
            cat > "${BUILD_DIR}/${ARTIFACT_NAME}-manifest.txt" << EOF
# EMSDK Split Archive Manifest
# This file lists all the parts of the split EMSDK archive

EMSDK_VERSION=$(cat emsdk/.emscripten_version 2>/dev/null || echo "unknown")
SPLIT_DATE=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
TOTAL_PARTS=${part_count}
TOTAL_SIZE_MB=${total_size}
COMPRESSION=tar.xz
SPLIT_SIZE=95MB

Split Parts:
EOF
            for part in "${BUILD_DIR}/${ARTIFACT_NAME}".tar.xz.part*; do
                if [ -f "$part" ]; then
                    size=$(get_file_size "$part")
                    size_mb=$((size / 1024 / 1024))
                    basename_part=$(basename "$part")
                    echo "  $basename_part (${size_mb}MB)" >> "${BUILD_DIR}/${ARTIFACT_NAME}-manifest.txt"
                fi
            done
            
            cat >> "${BUILD_DIR}/${ARTIFACT_NAME}-manifest.txt" << EOF

Reconstruction Instructions:
1. Download all ${ARTIFACT_NAME}.tar.xz.part* files to the same directory
2. Download ${ARTIFACT_NAME}-reconstruct.sh to the same directory
3. Run: chmod +x ${ARTIFACT_NAME}-reconstruct.sh
4. Run: ./${ARTIFACT_NAME}-reconstruct.sh
5. Extract: tar -xJf ${ARTIFACT_NAME}.tar.xz
6. Setup: cd emsdk && source ./emsdk_env.sh

Alternative manual reconstruction:
1. Download all parts to the same directory  
2. Run: cat ${ARTIFACT_NAME}.tar.xz.part* > ${ARTIFACT_NAME}.tar.xz
3. Extract: tar -xJf ${ARTIFACT_NAME}.tar.xz
4. Setup: cd emsdk && source ./emsdk_env.sh
EOF
            
        else
            echo "ERROR: Some split parts are still too large!"
            exit 1
        fi
    else
        echo "Artifact size is acceptable (${size_mb}MB <= 95MB)"
    fi
else
    echo "ERROR: Could not determine artifact size"
    exit 1
fi

# Also create the artifact in the original repository directory if we're not already there
if [ "$PWD" != "$GITHUB_WORKSPACE" ] && [ -n "$GITHUB_WORKSPACE" ]; then
    cp "${BUILD_DIR}/${ARTIFACT_NAME}"*.tar.xz* "$GITHUB_WORKSPACE/" 2>/dev/null || true
    cp "${BUILD_DIR}/${ARTIFACT_NAME}"*-reconstruct.sh "$GITHUB_WORKSPACE/" 2>/dev/null || true
    cp "${BUILD_DIR}/${ARTIFACT_NAME}"*.txt "$GITHUB_WORKSPACE/" 2>/dev/null || true
fi
