#!/bin/bash
# Build dist/MountGate.app from the SwiftPM package (no Xcode required).
#
# Usage:
#   ./scripts/build-app.sh              # release build, native arch
#   UNIVERSAL=1 ./scripts/build-app.sh  # arm64 + x86_64
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

if [[ ! -x Vendor/rclone ]]; then
    echo "ERROR: Vendor/rclone missing — run ./scripts/fetch-rclone.sh first" >&2
    exit 1
fi

BUILD_ARGS=(-c release)
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    BUILD_ARGS+=(--arch arm64 --arch x86_64)
    BIN_DIR="$REPO_ROOT/.build/apple/Products/Release"
else
    BIN_DIR="$REPO_ROOT/.build/release"
fi

echo "==> swift build ${BUILD_ARGS[*]}"
swift build "${BUILD_ARGS[@]}"

APP="$REPO_ROOT/dist/MountGate.app"
echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/MountGate" "$APP/Contents/MacOS/MountGate"
cp "$REPO_ROOT/Vendor/rclone" "$APP/Contents/Resources/rclone"
cp "$REPO_ROOT/Support/Info.plist" "$APP/Contents/Info.plist"

# Ad-hoc signing keeps macOS happy for local runs; Developer ID signing
# for distribution happens in CI (M7).
codesign --force --options runtime --sign - "$APP/Contents/Resources/rclone" 2>/dev/null \
    || codesign --force --sign - "$APP/Contents/Resources/rclone"
codesign --force --sign - "$APP"

echo "==> Built $APP"
