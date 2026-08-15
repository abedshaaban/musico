#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIGURATION="${1:-Release}"
XCODE_DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

case "$CONFIGURATION" in
  Debug|Release) ;;
  *)
    echo "Usage: $0 [Debug|Release]" >&2
    exit 64
    ;;
esac

if [[ ! -x "$XCODE_DEVELOPER_DIR/usr/bin/xcodebuild" ]]; then
  echo "Full Xcode was not found at: $XCODE_DEVELOPER_DIR" >&2
  echo "Install Xcode or set DEVELOPER_DIR to its Contents/Developer directory." >&2
  exit 1
fi

export DEVELOPER_DIR="$XCODE_DEVELOPER_DIR"

xcodebuild \
  -project "$PROJECT_DIR/Musico.xcodeproj" \
  -scheme Musico \
  -configuration "$CONFIGURATION" \
  -destination "generic/platform=iOS" \
  -derivedDataPath "$PROJECT_DIR/build" \
  CODE_SIGNING_ALLOWED=NO \
  build

APP_PATH="$PROJECT_DIR/build/Build/Products/${CONFIGURATION}-iphoneos/Musico.app"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Build completed, but the expected app was not found at: $APP_PATH" >&2
  exit 1
fi

echo
echo "Build succeeded: $APP_PATH"
echo "This app is unsigned and must be signed before normal iPhone installation."
