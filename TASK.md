# EMSDK Binary Testing Plan

## Overview
This document outlines the plan for testing EMSDK binaries built by this repository. The goal is to verify that the compiled Emscripten SDK binaries can successfully compile a C++ program and produce the expected WebAssembly artifacts.

## Repository Analysis

### Build Script: `install_emscripten.sh`
- **Purpose**: Downloads, compiles, and packages Emscripten SDK with aggressive size optimizations
- **Output**: Creates `emsdk-{OS_NAME}.tar.xz` archive (or split parts if >95MB)
- **Platforms**: Ubuntu, macOS (x86_64 + ARM64), Windows
- **Optimizations**: Uses `-Oz`, LTO, and strip flags for minimal binary size

### GitHub Actions Workflow
- **File**: `.github/workflows/publish-emscripten.yml`
- **Triggers**: Push to main, weekly schedule, manual dispatch
- **Matrix Build**: Builds for 4 platforms simultaneously
- **Artifacts**: Uploads compressed archives to GitHub Pages at `https://fastled.github.io/emsdk-binaries/`

## Testing Strategy

### Phase 1: Local Build Testing
1. **Execute Build Script**
   ```bash
   chmod +x install_emscripten.sh
   ./install_emscripten.sh
   ```

2. **Verify Archive Creation**
   - Check for `emsdk-{platform}.tar.xz` or split parts
   - Verify reconstruction script if split
   - Validate archive integrity with `xz -t`

### Phase 2: Binary Extraction Testing
1. **Extract Archive**
   ```bash
   # For single archive
   tar -xJf emsdk-{platform}.tar.xz

   # For split archives
   ./emsdk-{platform}-reconstruct.sh
   tar -xJf emsdk-{platform}.tar.xz
   ```

2. **Environment Setup**
   ```bash
   cd emsdk
   source ./emsdk_env.sh
   ```

3. **Verify Tools Available**
   ```bash
   emcc --version
   em++ --version
   emrun --version
   ```

### Phase 3: Compilation Testing
1. **Test Program**: `hello_world.cpp`
   ```cpp
   #include <iostream>

   int main() {
       std::cout << "Hello, World from Emscripten!" << std::endl;
       return 0;
   }
   ```

2. **Compilation Commands**
   ```bash
   # Basic compilation
   em++ hello_world.cpp -o hello_world.html

   # WebAssembly only
   em++ hello_world.cpp -o hello_world.wasm

   # JavaScript module
   em++ hello_world.cpp -o hello_world.js
   ```

3. **Expected Artifacts**
   - `hello_world.html` - HTML wrapper with embedded JS
   - `hello_world.js` - JavaScript runtime
   - `hello_world.wasm` - WebAssembly binary
   - `hello_world.wasm.map` - Source map (optional)

### Phase 4: Runtime Testing
1. **HTML Output Testing**
   ```bash
   # Start local server
   emrun hello_world.html
   ```
   - Verify "Hello, World from Emscripten!" appears in browser console
   - Check for successful WASM loading

2. **Node.js Testing**
   ```bash
   node hello_world.js
   ```
   - Verify console output matches expected

3. **WASM Validation**
   ```bash
   # Validate WASM structure
   wasm-validate hello_world.wasm  # if available
   file hello_world.wasm  # check file type
   ```

## Test Implementation Plan

### Test Script Structure
```bash
#!/bin/bash
# test_emsdk_binaries.sh

set -e

echo "=== EMSDK Binary Testing ==="

# Phase 1: Build or Download
if [ "$1" = "build" ]; then
    echo "Building EMSDK from source..."
    ./install_emscripten.sh
else
    echo "Using pre-built binaries..."
    # Download and extract logic here
fi

# Phase 2: Setup Environment
echo "Setting up EMSDK environment..."
cd emsdk
source ./emsdk_env.sh
cd ..

# Phase 3: Compilation Test
echo "Testing compilation..."
em++ hello_world.cpp -o hello_world.html
em++ hello_world.cpp -o hello_world.js
em++ hello_world.cpp -o hello_world.wasm

# Phase 4: Artifact Validation
echo "Validating artifacts..."
test -f hello_world.html || { echo "ERROR: hello_world.html not created"; exit 1; }
test -f hello_world.js || { echo "ERROR: hello_world.js not created"; exit 1; }
test -f hello_world.wasm || { echo "ERROR: hello_world.wasm not created"; exit 1; }

# Test file sizes
wasm_size=$(stat -c%s hello_world.wasm 2>/dev/null || stat -f%z hello_world.wasm)
echo "WASM file size: $wasm_size bytes"

# Phase 5: Runtime Test (Node.js)
echo "Testing Node.js execution..."
timeout 10s node hello_world.js > output.txt
grep -q "Hello, World from Emscripten!" output.txt || {
    echo "ERROR: Expected output not found"
    echo "Actual output:"
    cat output.txt
    exit 1
}

echo "=== All tests passed! ==="
```

### GitHub Actions Integration
Add to `.github/workflows/test-binaries.yml`:
```yaml
name: Test EMSDK Binaries

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  test-build:
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest, windows-latest]
    runs-on: ${{ matrix.os }}

    steps:
    - uses: actions/checkout@v4

    - name: Build and Test EMSDK
      shell: bash
      run: |
        chmod +x test_emsdk_binaries.sh
        ./test_emsdk_binaries.sh build

    - name: Upload Test Artifacts
      uses: actions/upload-artifact@v4
      with:
        name: test-artifacts-${{ matrix.os }}
        path: |
          hello_world.*
          output.txt
```

## Success Criteria

### Build Phase
- [ ] Script executes without errors
- [ ] Archive created with expected naming convention
- [ ] Archive size is reasonable (<500MB uncompressed)
- [ ] Split archives can be reconstructed properly

### Setup Phase
- [ ] Archive extracts successfully
- [ ] Environment script runs without errors
- [ ] All EMSDK tools are in PATH and functional

### Compilation Phase
- [ ] C++ compilation succeeds for all output formats
- [ ] All expected artifacts are created
- [ ] WASM file is valid WebAssembly format
- [ ] File sizes are reasonable

### Runtime Phase
- [ ] Node.js execution produces expected output
- [ ] HTML version loads in browser (manual test)
- [ ] No runtime errors in console

## Error Handling

### Common Issues
1. **Missing Dependencies**: Ensure system has required build tools
2. **Archive Corruption**: Verify checksums and re-download if needed
3. **Permission Issues**: Check file permissions on extracted binaries
4. **Path Problems**: Ensure EMSDK paths are properly set in environment

### Debugging Steps
1. Check `emcc --version` output for version info
2. Verify `which emcc` points to correct installation
3. Test with simpler C program if C++ fails
4. Check Node.js version compatibility
5. Examine browser developer console for WASM loading issues

## Maintenance

### Regular Testing
- Run tests weekly as part of CI/CD
- Test against latest Emscripten releases
- Verify cross-platform compatibility
- Monitor archive sizes and optimization effectiveness

### Updates Required
- Update test when new Emscripten features are added
- Adjust size limits if compression improves
- Add new test cases for specific use cases
- Update Node.js compatibility as needed

## Files Created/Modified

1. `hello_world.cpp` - Test program for compilation
2. `test_emsdk_binaries.sh` - Main test script (to be created)
3. `.github/workflows/test-binaries.yml` - CI testing workflow (to be created)
4. `TASK.md` - This documentation file

## Next Steps

1. Implement the test script (`test_emsdk_binaries.sh`)
2. Add GitHub Actions workflow for automated testing
3. Test locally on current platform
4. Verify with pre-built binaries from GitHub Pages
5. Document any platform-specific requirements
6. Create automated reporting of test results