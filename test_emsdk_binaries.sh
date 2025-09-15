#!/bin/bash
# test_emsdk_binaries.sh - EMSDK Binary Testing Script

set -e

# Set up build directory
BUILD_DIR="./.build"
mkdir -p "$BUILD_DIR"

echo "=== EMSDK Binary Testing ==="
echo "Platform: $(uname -s)"
echo "Date: $(date)"
echo "Build directory: $BUILD_DIR"

# Function to get file size cross-platform
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
        ls -l "$file" 2>/dev/null | awk '{print $5}'
    fi
}

# Phase 1: Build or Use Existing EMSDK
if [ "$1" = "build" ] || [ ! -d "$BUILD_DIR/emsdk" ]; then
    echo "Building EMSDK from source..."
    ./install_emscripten.sh

    echo "Checking for created archives in $BUILD_DIR..."
    ls -la "$BUILD_DIR"/emsdk-*.tar.xz* 2>/dev/null || echo "No archives found"

    echo "Extracting EMSDK for testing..."
    # Find the created archive in build directory
    if ls "$BUILD_DIR"/emsdk-*.tar.xz >/dev/null 2>&1; then
        archive=$(ls "$BUILD_DIR"/emsdk-*.tar.xz | head -1)
        echo "Found single archive: $archive"
        cd "$BUILD_DIR"
        tar -xJf "$(basename "$archive")"
        cd ..
    elif ls "$BUILD_DIR"/emsdk-*.tar.xz.part* >/dev/null 2>&1; then
        echo "Found split archives, reconstructing..."
        reconstruct_script=$(ls "$BUILD_DIR"/emsdk-*-reconstruct.sh | head -1)
        chmod +x "$reconstruct_script"
        "$reconstruct_script"
    else
        echo "No archives found, checking if emsdk directory already exists..."
        if [ ! -d "$BUILD_DIR/emsdk" ]; then
            echo "ERROR: No EMSDK installation found"
            exit 1
        fi
    fi
else
    echo "Using existing EMSDK installation..."
fi

# Phase 2: Setup Environment
echo "Setting up EMSDK environment..."
if [ ! -d "$BUILD_DIR/emsdk" ]; then
    echo "ERROR: emsdk directory not found in $BUILD_DIR"
    exit 1
fi

cd "$BUILD_DIR/emsdk"
source ./emsdk_env.sh
cd ../..

# Verify tools are available
echo "Verifying EMSDK tools..."
emcc --version || { echo "ERROR: emcc not found or not working"; exit 1; }
em++ --version || { echo "ERROR: em++ not found or not working"; exit 1; }

# Phase 3: Compilation Test
echo "Testing C++ compilation..."

# Ensure hello_world.cpp exists in build directory
if [ ! -f "$BUILD_DIR/hello_world.cpp" ]; then
    echo "Creating hello_world.cpp test file in $BUILD_DIR..."
    cat > "$BUILD_DIR/hello_world.cpp" << 'EOF'
#include <iostream>

int main() {
    std::cout << "Hello, World from Emscripten!" << std::endl;
    return 0;
}
EOF
fi

# Change to build directory for compilation
cd "$BUILD_DIR"

# Test different compilation targets
echo "Compiling to HTML..."
em++ hello_world.cpp -o hello_world.html

echo "Compiling to JavaScript (Node.js compatible)..."
em++ hello_world.cpp -o hello_world.js -s ENVIRONMENT=node

echo "Compiling to WebAssembly..."
em++ hello_world.cpp -o hello_world.wasm

# Return to project root
cd ..

# Phase 4: Artifact Validation
echo "Validating generated artifacts..."

# Check for required files in build directory
test -f "$BUILD_DIR/hello_world.html" || { echo "ERROR: hello_world.html not created"; exit 1; }
test -f "$BUILD_DIR/hello_world.js" || { echo "ERROR: hello_world.js not created"; exit 1; }
test -f "$BUILD_DIR/hello_world.wasm" || { echo "ERROR: hello_world.wasm not created"; exit 1; }

echo "✓ All expected artifacts created"

# Report file sizes
echo "Artifact sizes:"
for file in hello_world.html hello_world.js hello_world.wasm; do
    if [ -f "$BUILD_DIR/$file" ]; then
        size=$(get_file_size "$BUILD_DIR/$file")
        if [ -n "$size" ]; then
            echo "  $file: $size bytes"
        else
            echo "  $file: size unknown"
        fi
    fi
done

# Phase 5: Runtime Test (Node.js)
echo "Testing Node.js execution..."
if command -v node >/dev/null 2>&1; then
    echo "Running hello_world.js with Node.js..."
    cd "$BUILD_DIR"
    timeout 10s node hello_world.js > output.txt 2>&1 || {
        echo "Node.js execution timed out or failed"
        echo "Output:"
        cat output.txt 2>/dev/null || echo "No output captured"
        exit 1
    }
    cd ..

    if grep -q "Hello, World from Emscripten!" "$BUILD_DIR/output.txt"; then
        echo "✓ Node.js execution successful"
        echo "Output: $(cat "$BUILD_DIR/output.txt")"
    else
        echo "ERROR: Expected output not found in Node.js execution"
        echo "Actual output:"
        cat "$BUILD_DIR/output.txt"
        exit 1
    fi
else
    echo "WARNING: Node.js not available, skipping runtime test"
fi

# Additional validation
echo "Performing additional validation..."

# Check if WASM file is valid
if command -v file >/dev/null 2>&1; then
    wasm_type=$(file "$BUILD_DIR/hello_world.wasm" 2>/dev/null || echo "unknown")
    echo "WASM file type: $wasm_type"
fi

# Check HTML contains expected elements
if grep -q "hello_world.js" "$BUILD_DIR/hello_world.html" && grep -q "Module" "$BUILD_DIR/hello_world.html"; then
    echo "✓ HTML file contains expected Emscripten structure"
else
    echo "WARNING: HTML file may not have proper Emscripten structure"
fi

echo ""
echo "=== Test Results Summary ==="
echo "✓ EMSDK installation successful"
echo "✓ Environment setup successful"
echo "✓ C++ compilation successful"
echo "✓ All artifacts generated"
echo "✓ File validation passed"
if command -v node >/dev/null 2>&1; then
    echo "✓ Runtime execution successful"
else
    echo "⚠ Runtime execution skipped (Node.js not available)"
fi

echo ""
echo "Generated files:"
ls -la "$BUILD_DIR"/hello_world.* "$BUILD_DIR"/output.txt 2>/dev/null | head -10

echo ""
echo "=== All tests completed successfully! ==="