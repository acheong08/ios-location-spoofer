#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

IOS_SDK=$(xcrun --sdk iphoneos --show-sdk-path)
IOS_ARCH="arm64"
MIN_IOS_VERSION="15.0"
BUILD_DIR="$SCRIPT_DIR/build"

echo "=== Building Go Location Spoofer for iOS ==="
echo "SDK: $IOS_SDK"
echo "Architecture: $IOS_ARCH"
echo "Min iOS Version: $MIN_IOS_VERSION"

# Create build directory
mkdir -p "$BUILD_DIR"

# Set up Go environment for iOS cross-compilation
export CGO_ENABLED=1
export CGO_CFLAGS="-arch arm64 -isysroot $IOS_SDK -miphoneos-version-min=$MIN_IOS_VERSION"
export CGO_LDFLAGS="-arch arm64 -isysroot $IOS_SDK -miphoneos-version-min=$MIN_IOS_VERSION"
export GOOS="ios"
export GOARCH="arm64"
export GO111MODULE="on"

# Build the Go library as a C archive for iOS
# Strip symbols to reduce binary size (important for iOS 50MB memory limit)
echo "Building libgolocationspoofer.a..."
go build -ldflags="-s -w" -buildmode=c-archive \
    -o "$BUILD_DIR/libgolocationspoofer.a" \
    -tags=ios \
    .

# Copy header to project root with proper name
cp "$BUILD_DIR/libgolocationspoofer.h" "$SCRIPT_DIR/golocationspoofer.h"
echo "Generated golocationspoofer.h"

# Create symbolic link
ln -sf "$BUILD_DIR/libgolocationspoofer.a" "$SCRIPT_DIR/libgolocationspoofer.a" 2>/dev/null || true

echo ""
echo "=== Build Complete ==="
echo "Static library: $BUILD_DIR/libgolocationspoofer.a"
echo "Header file: $SCRIPT_DIR/golocationspoofer.h"
echo ""
echo "To use in Xcode:"
echo "1. Add libgolocationspoofer.a to 'Linked Frameworks and Libraries'"
echo "2. Add golocationspoofer.h to your project"
echo "3. Add to 'Other Linker Flags': -l golocationspoofer"
echo "4. Add to 'Header Search Paths': $SCRIPT_DIR"