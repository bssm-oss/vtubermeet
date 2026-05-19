#!/bin/bash
# VTuberMeet - Live2D Cubism SDK Setup Script
# This script helps you download and install the Cubism SDK for Web
# which is required for Live2D model rendering.

set -e

echo "=== VTuberMeet - Live2D Cubism SDK Setup ==="
echo ""
echo "The Cubism SDK for Web is required for Live2D model rendering."
echo "It's proprietary software from Live2D Inc. and requires accepting"
echo "their license agreement to download."
echo ""
echo "Step 1: Open the SDK download page:"
echo "  https://www.live2d.com/en/sdk/download/web/"
echo ""
echo "Step 2: Read and agree to the license terms"
echo ""
echo "Step 3: Download the latest Cubism SDK for Web ZIP"
echo ""
echo "Step 4: Run this script again after downloading:"
echo "  $0 /path/to/CubismSdkForWeb-*.zip"
echo ""

SDK_ZIP="$1"

if [ -z "$SDK_ZIP" ]; then
    echo "No ZIP file provided. Follow steps 1-3 above, then re-run with the ZIP path."
    exit 0
fi

if [ ! -f "$SDK_ZIP" ]; then
    echo "Error: File not found: $SDK_ZIP"
    exit 1
fi

echo "Extracting Cubism Core from $SDK_ZIP..."
TMP_DIR=$(mktemp -d)
unzip -o "$SDK_ZIP" "*/Core/*" -d "$TMP_DIR" 2>/dev/null

CORE_DIR=$(find "$TMP_DIR" -name "live2dcubismcore.min.js" -exec dirname {} \; 2>/dev/null | head -1)

if [ -z "$CORE_DIR" ]; then
    echo "Error: Could not find Cubism Core files in the ZIP."
    echo "Make sure you downloaded the Cubism SDK for Web."
    rm -rf "$TMP_DIR"
    exit 1
fi

# Determine app Resources directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VENDOR_DIR="$SCRIPT_DIR/Live2DViewer/vendor"

echo "Installing Cubism Core to: $VENDOR_DIR"
cp "$CORE_DIR/live2dcubismcore.min.js" "$VENDOR_DIR/live2dcubismcore.min.js"

# The WASM file might have a different name - find any .wasm file
WASM_FILE=$(find "$CORE_DIR" -name "*.wasm" 2>/dev/null | head -1)
if [ -n "$WASM_FILE" ]; then
    cp "$WASM_FILE" "$VENDOR_DIR/"
    echo "Installed WASM: $(basename $WASM_FILE)"
fi

rm -rf "$TMP_DIR"
echo ""
echo "=== Setup Complete! ==="
echo "Live2D Cubism SDK installed. Restart VTuberMeet to use Live2D models."
