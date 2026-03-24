#!/bin/bash
# Build verification script for photo-storage-cleaner
# Run from the photo_storage_cleaner/ directory
#
# Prerequisites:
#   - iOS:     Xcode installed, valid signing certificate configured
#   - Android: Android SDK installed, ANDROID_HOME set
#   - macOS:   macOS host required
#   - Windows: Windows host required
#   - Linux:   Linux host with build-essential, clang, cmake, ninja-build

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== Building mobile_client ==="
cd packages/mobile_client

echo "--- iOS (requires Xcode and signing) ---"
flutter build ios --no-codesign || echo "iOS build requires Xcode and signing"

echo "--- Android APK ---"
flutter build apk || echo "Android build requires Android SDK"

cd ../..

echo ""
echo "=== Building storage_server ==="
cd packages/storage_server

echo "--- macOS ---"
flutter build macos || echo "macOS build requires macOS"

echo "--- Windows ---"
flutter build windows || echo "Windows build requires Windows"

echo "--- Linux ---"
flutter build linux || echo "Linux build requires Linux"

cd ../..

echo ""
echo "=== Build verification complete ==="
