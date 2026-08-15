#!/bin/bash
# Download the official rclone macOS binary into Vendor/rclone.
# By default builds a universal (arm64 + x86_64) binary via lipo.
#
# Usage:
#   ./scripts/fetch-rclone.sh                 # latest stable, universal
#   RCLONE_VERSION=v1.71.0 ./scripts/fetch-rclone.sh
#   ARCH_ONLY=1 ./scripts/fetch-rclone.sh     # native arch only (faster, dev)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$REPO_ROOT/Vendor"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

VERSION="${RCLONE_VERSION:-$(curl -fsSL https://downloads.rclone.org/version.txt | tr -d '[:space:]' | sed 's/^rclone//')}"
echo "==> rclone version: $VERSION"

fetch_arch() {
    local arch="$1" # arm64 | amd64
    local zip="rclone-${VERSION}-osx-${arch}.zip"
    local url="https://downloads.rclone.org/${VERSION}/${zip}"
    echo "==> Downloading $url"
    curl -fsSL -o "$WORK/$zip" "$url"

    echo "==> Verifying SHA256"
    local sums expected actual
    sums="$(curl -fsSL "https://downloads.rclone.org/${VERSION}/SHA256SUMS")"
    expected="$(echo "$sums" | grep " ${zip}\$" | awk '{print $1}')"
    actual="$(shasum -a 256 "$WORK/$zip" | awk '{print $1}')"
    if [[ -z "$expected" || "$expected" != "$actual" ]]; then
        echo "ERROR: SHA256 mismatch for $zip (expected: ${expected:-<missing>}, got: $actual)" >&2
        exit 1
    fi

    unzip -q -o "$WORK/$zip" -d "$WORK"
    mv "$WORK/rclone-${VERSION}-osx-${arch}/rclone" "$WORK/rclone-${arch}"
}

mkdir -p "$VENDOR"

if [[ "${ARCH_ONLY:-0}" == "1" ]]; then
    native="$(uname -m)"
    [[ "$native" == "x86_64" ]] && native="amd64"
    fetch_arch "$native"
    cp "$WORK/rclone-$native" "$VENDOR/rclone"
else
    fetch_arch "arm64"
    fetch_arch "amd64"
    echo "==> Creating universal binary"
    lipo -create "$WORK/rclone-arm64" "$WORK/rclone-amd64" -output "$VENDOR/rclone"
fi

chmod +x "$VENDOR/rclone"
# Strip the quarantine attribute so the binary can run when bundled.
xattr -d com.apple.quarantine "$VENDOR/rclone" 2>/dev/null || true

echo "==> Installed: $VENDOR/rclone"
"$VENDOR/rclone" version | head -1
