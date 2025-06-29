#!/bin/bash

set -e

EMSDK_DIR="$HOME/emsdk"

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

# Install with optimization flags set
./emsdk install latest
./emsdk activate latest
source ./emsdk_env.sh

emcc -v

# Clean up unnecessary files to reduce artifact size
echo "Cleaning up unnecessary files to reduce artifact size..."

# Remove all downloaded archives - these are the biggest space consumers
echo "Removing downloaded archives..."
rm -rf downloads/ 2>/dev/null || true

# Remove cache and temporary files
find . -name "*.tmp" -delete 2>/dev/null || true
find . -name "*.cache" -delete 2>/dev/null || true
find . -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
find . -name "*.pyc" -delete 2>/dev/null || true

# Remove documentation and examples that aren't needed for compilation
rm -rf docs/ 2>/dev/null || true
rm -rf tests/ 2>/dev/null || true
rm -rf test/ 2>/dev/null || true
rm -rf examples/ 2>/dev/null || true
rm -rf site/ 2>/dev/null || true

# Remove git history and metadata to save space
rm -rf .git/ 2>/dev/null || true
rm -rf .github/ 2>/dev/null || true

# Clean up any large log files
find . -name "*.log" -size +1M -delete 2>/dev/null || true

# Remove intermediate build files
find . -name "*.o" -delete 2>/dev/null || true
find . -name "*.a" -name "*debug*" -delete 2>/dev/null || true

# More aggressive cleanup for maximum size reduction
echo "Applying aggressive size reduction..."

# Remove all debug information and symbols
find . -name "*.debug" -delete 2>/dev/null || true
find . -name "*.pdb" -delete 2>/dev/null || true
find . -name "*.dSYM" -type d -exec rm -rf {} + 2>/dev/null || true

# Remove source maps and debugging files
find . -name "*.map" -delete 2>/dev/null || true
find . -name "*.dwp" -delete 2>/dev/null || true
find . -name "*.dwarf" -delete 2>/dev/null || true

# Remove unnecessary static libraries (keep only essential ones)
find . -name "*.a" -path "*/lib/*" -not -name "libc.a" -not -name "libm.a" -not -name "libpthread.a" -not -name "librt.a" -not -name "libdl.a" -delete 2>/dev/null || true

# Remove unnecessary headers and includes (keep only essential runtime headers)
find . -path "*/include/*" -name "*.h" -not -path "*/emscripten/*" -not -path "*/c++/*" -not -name "emscripten.h" -not -name "bind.h" -delete 2>/dev/null || true

# Remove language-specific files we don't need
rm -rf */locale/ 2>/dev/null || true
rm -rf */locales/ 2>/dev/null || true
rm -rf */i18n/ 2>/dev/null || true
rm -rf */po/ 2>/dev/null || true
rm -rf */share/locale/ 2>/dev/null || true

# Remove man pages and documentation
rm -rf */man/ 2>/dev/null || true
rm -rf */share/man/ 2>/dev/null || true
rm -rf */share/doc/ 2>/dev/null || true
rm -rf */share/info/ 2>/dev/null || true

# Remove unnecessary compiler tools (keep only essential ones)
find . -name "clang++-*" -not -name "clang++" -delete 2>/dev/null || true
find . -name "clang-*" -not -name "clang" -delete 2>/dev/null || true

# Remove source files that aren't needed for compilation
find . -name "*.cpp" -path "*/src/*" -delete 2>/dev/null || true
find . -name "*.c" -path "*/src/*" -delete 2>/dev/null || true
find . -name "*.cc" -path "*/src/*" -delete 2>/dev/null || true

# Remove large unnecessary files
find . -type f -size +50M -name "*.tar*" -delete 2>/dev/null || true
find . -type f -size +50M -name "*.zip" -delete 2>/dev/null || true

# Remove backup files
find . -name "*.bak" -delete 2>/dev/null || true
find . -name "*~" -delete 2>/dev/null || true

# Remove unnecessary binary variants (keep only the most optimized ones)
find . -name "*-debug" -type f -delete 2>/dev/null || true
find . -name "*_debug" -type f -delete 2>/dev/null || true

# Strip debug symbols from all binaries and shared libraries
if command -v strip >/dev/null 2>&1; then
    echo "Stripping debug symbols from binaries..."
    # Fix for macOS: use different approach for finding executable files
    case "$(uname)" in
        Darwin)
            # macOS-specific approach
            find . -type f -perm +111 -exec file {} \; | grep -E "(executable|shared object)" | cut -d: -f1 | while read -r file; do
                strip -S "$file" 2>/dev/null || true
            done
            # Strip static libraries
            find . -name "*.a" -exec strip -S {} \; 2>/dev/null || true
            ;;
        Linux)
            # Linux approach
            find . -type f -executable -exec file {} \; | grep -E "(executable|shared object)" | cut -d: -f1 | xargs -r strip --strip-all 2>/dev/null || true
            # Also strip static libraries
            find . -name "*.a" -exec strip --strip-debug {} \; 2>/dev/null || true
            ;;
        *)
            # Generic approach
            find . -type f -name "*.so*" -exec strip {} \; 2>/dev/null || true
            find . -name "*.a" -exec strip {} \; 2>/dev/null || true
            ;;
    esac
fi

# Use UPX to compress binaries if available (fast compression to avoid CI timeouts)
if command -v upx >/dev/null 2>&1 && [ "${GITHUB_ACTIONS:-false}" != "true" ]; then
    echo "Compressing binaries with UPX (local build only)..."
    find . -type f -size +1M -size -50M -exec file {} \; | grep -E "(executable|shared object)" | cut -d: -f1 | while read -r file; do
        timeout 60 upx --best "$file" 2>/dev/null || true
    done
else
    echo "Skipping UPX compression (disabled in CI or UPX not available)"
fi

# Remove duplicate shared libraries (keep only the most recent versions) - Fix head command
find . -name "*.so.*" -type f | sort | uniq -d | head -n 1 | while read -r file; do
    rm "$file" 2>/dev/null || true
done

# Remove Python optimization files
find . -name "*.pyo" -delete 2>/dev/null || true
find . -name "*.opt-1.pyc" -delete 2>/dev/null || true
find . -name "*.opt-2.pyc" -delete 2>/dev/null || true

# Remove unnecessary Node.js modules (if any)
find . -path "*/node_modules/*" -name "*.md" -delete 2>/dev/null || true
find . -path "*/node_modules/*" -name "LICENSE*" -delete 2>/dev/null || true
find . -path "*/node_modules/*" -name "CHANGELOG*" -delete 2>/dev/null || true

# Remove CMake cache and build files
find . -name "CMakeCache.txt" -delete 2>/dev/null || true
find . -name "CMakeFiles" -type d -exec rm -rf {} + 2>/dev/null || true
find . -name "*.cmake" -path "*/CMakeFiles/*" -delete 2>/dev/null || true

# Remove pkg-config files we don't need
find . -name "*.pc" -path "*/pkgconfig/*" -delete 2>/dev/null || true

# Additional specific cleanup based on typical EMSDK structure
echo "Applying EMSDK-specific optimizations..."

# Remove CI/development files
rm -rf .circleci/ 2>/dev/null || true
rm -f .flake8 2>/dev/null || true

# Remove documentation files to save space
rm -f README.md SECURITY.md 2>/dev/null || true

# Remove legacy tag files and build-time metadata
rm -f legacy-emscripten-tags.txt legacy-binaryen-tags.txt 2>/dev/null || true
rm -f llvm-tags-64bit.txt 2>/dev/null || true
rm -f emscripten-releases-tags.json 2>/dev/null || true

# Remove development/build scripts directory if not essential
rm -rf scripts/ 2>/dev/null || true

# Remove bazel if present and not needed
rm -rf bazel/ 2>/dev/null || true

# Keep only essential shell environment files (remove platform-specific ones)
# Keep: emsdk_env.sh (main), emsdk_env.bat (Windows basic)
# Remove: csh, fish, ps1 variants
rm -f emsdk_env.csh emsdk_env.fish emsdk_env.ps1 2>/dev/null || true
rm -f emsdk.ps1 emcmdprompt.bat 2>/dev/null || true

# Clean up Node.js installation if present
if [ -d "node" ]; then
    echo "Optimizing Node.js installation..."
    # Remove Node.js documentation and examples
    find node/ -name "*.md" -delete 2>/dev/null || true
    find node/ -name "doc" -type d -exec rm -rf {} + 2>/dev/null || true
    find node/ -name "example*" -type d -exec rm -rf {} + 2>/dev/null || true
    find node/ -name "CHANGELOG*" -delete 2>/dev/null || true
    find node/ -name "LICENSE*" -delete 2>/dev/null || true
    # Remove npm cache and logs
    find node/ -name ".npm" -type d -exec rm -rf {} + 2>/dev/null || true
    find node/ -name "npm-debug.log*" -delete 2>/dev/null || true
fi

# Clean up Python installation if present
if [ -d "python" ]; then
    echo "Optimizing Python installation..."
    # Remove Python test files and documentation  
    find python/ -name "test" -type d -exec rm -rf {} + 2>/dev/null || true
    find python/ -name "tests" -type d -exec rm -rf {} + 2>/dev/null || true
    find python/ -name "Doc" -type d -exec rm -rf {} + 2>/dev/null || true
    find python/ -name "*.md" -delete 2>/dev/null || true
    # Remove pip cache
    find python/ -name "pip" -type d -path "*/cache/*" -exec rm -rf {} + 2>/dev/null || true
fi

# Remove development/build scripts that aren't needed for runtime
if [ -d "scripts" ]; then
    echo "Cleaning up scripts directory..."
    # Keep only essential scripts, remove development ones
    find scripts/ -name "*test*" -delete 2>/dev/null || true
    find scripts/ -name "*dev*" -delete 2>/dev/null || true
    find scripts/ -name "*debug*" -delete 2>/dev/null || true
fi

# Remove any remaining large archive files that might have been missed
find . -name "*.tar.gz" -size +10M -delete 2>/dev/null || true
find . -name "*.tar.bz2" -size +10M -delete 2>/dev/null || true
find . -name "*.zip" -size +10M -delete 2>/dev/null || true

echo "EMSDK-specific cleanup completed. Checking directory size..."

cd ..

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

# Common tar exclusions
COMMON_EXCLUDES=(
    --exclude='*.git*'
    --exclude='*cache*'
    --exclude='*tmp*'
    --exclude='*temp*'
    --exclude='*.log'
    --exclude='*test*'
    --exclude='*doc*'
    --exclude='*example*'
    --exclude='*download*'
    --exclude='*.tar*'
    --exclude='*.zip'
    --exclude='*.bak'
    --exclude='*~'
    --exclude='*/locale/*'
    --exclude='*/locales/*'
    --exclude='*/man/*'
    --exclude='*/share/man/*'
    --exclude='*/share/doc/*'
    --exclude='*/share/info/*'
    --exclude='*debug*'
    --exclude='*.debug'
    --exclude='*.pdb'
    --exclude='*.map'
    --exclude='*.dwp'
    --exclude='*.dwarf'
    --exclude='CMakeFiles'
    --exclude='*.cmake'
    --exclude='*.pc'
    --exclude='.circleci'
    --exclude='.flake8'
    --exclude='README.md'
    --exclude='SECURITY.md'

)

echo "Creating compressed artifact: ${ARTIFACT_NAME}.tar.xz"

# Create a highly compressed tarball with XZ compression (better than gzip)
echo "Using XZ compression with maximum compression level..."
XZ_OPT=-9 tar "${COMMON_EXCLUDES[@]}" -cJf "${ARTIFACT_NAME}.tar.xz" emsdk

# Check the size of the created artifact
size=$(get_file_size "${ARTIFACT_NAME}.tar.xz")
if [ -n "$size" ] && [ "$size" -gt 0 ]; then
    size_mb=$((size / 1024 / 1024))
    echo "Created artifact: ${ARTIFACT_NAME}.tar.xz (${size_mb}MB)"
    
    if [ $size_mb -gt 95 ]; then
        echo "WARNING: Artifact is ${size_mb}MB, which exceeds GitHub's 95MB limit!"
        echo "Splitting archive into 95MB chunks..."
        
        # Split the tar.xz file into 95MB chunks
        split -b 95M "${ARTIFACT_NAME}.tar.xz" "${ARTIFACT_NAME}.tar.xz.part"
        
        # Remove the original large file
        rm "${ARTIFACT_NAME}.tar.xz"
        
        # Check the created parts
        success=true
        total_size=0
        part_count=0
        
        for part in "${ARTIFACT_NAME}".tar.xz.part*; do
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
            cat > "${ARTIFACT_NAME}-reconstruct.sh" << 'EOF'
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
            chmod +x "${ARTIFACT_NAME}-reconstruct.sh"
            
            # Create a manifest file listing all parts
            echo "Creating manifest file..."
            cat > "${ARTIFACT_NAME}-manifest.txt" << EOF
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
            for part in "${ARTIFACT_NAME}".tar.xz.part*; do
                if [ -f "$part" ]; then
                    size=$(get_file_size "$part")
                    size_mb=$((size / 1024 / 1024))
                    echo "  $part (${size_mb}MB)" >> "${ARTIFACT_NAME}-manifest.txt"
                fi
            done
            
            cat >> "${ARTIFACT_NAME}-manifest.txt" << EOF

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
    cp "${ARTIFACT_NAME}"*.tar.xz* "$GITHUB_WORKSPACE/" 2>/dev/null || true
    cp "${ARTIFACT_NAME}"*-reconstruct.sh "$GITHUB_WORKSPACE/" 2>/dev/null || true
    cp "${ARTIFACT_NAME}"*.txt "$GITHUB_WORKSPACE/" 2>/dev/null || true
fi
