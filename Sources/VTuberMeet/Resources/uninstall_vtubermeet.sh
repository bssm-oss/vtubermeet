#!/bin/bash
# ============================================================
# VTuberMeet - Complete Uninstall Script
# Removes application files, defaults, and temporary Live2D SDK caches
# ============================================================

set -e

echo "=== VTuberMeet 완전 삭제 ==="

# Remove application
if [ -d "/Applications/VTuberMeet.app" ]; then
    rm -rf "/Applications/VTuberMeet.app"
    echo "[1/3] App bundle removed"
else
    echo "[1/3] No app bundle found"
fi

# Remove user defaults
defaults delete local.vtubermeet.app 2>/dev/null || true
echo "[2/3] User defaults removed"

# Remove cached SDK files
rm -rf /tmp/CubismSdkForWeb-*.zip 2>/dev/null || true
rm -rf /tmp/cubism_sdk 2>/dev/null || true
rm -rf /tmp/cubism5_sdk 2>/dev/null || true
rm -rf /tmp/cubism-full-sdk 2>/dev/null || true
echo "[3/3] SDK cache removed"

echo ""
echo "=== VTuberMeet has been completely uninstalled ==="
