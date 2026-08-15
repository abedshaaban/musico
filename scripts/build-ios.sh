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
ARTIFACTS_DIR="$PROJECT_DIR/artifacts"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Build completed, but the expected app was not found at: $APP_PATH" >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Info.plist")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Info.plist")"
IPA_PATH="$ARTIFACTS_DIR/Musico-${VERSION}-${BUILD_NUMBER}-${CONFIGURATION}.ipa"
PACKAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/musico-ipa.XXXXXX")"

cleanup() {
  rm -rf "$PACKAGE_DIR"
}
trap cleanup EXIT

mkdir -p "$ARTIFACTS_DIR" "$PACKAGE_DIR/Payload"
COPYFILE_DISABLE=1 cp -R "$APP_PATH" "$PACKAGE_DIR/Payload/Musico.app"
(
  cd "$PACKAGE_DIR"
  COPYFILE_DISABLE=1 /usr/bin/zip -qry "$IPA_PATH" Payload
)

/usr/bin/unzip -tq "$IPA_PATH"
CHECKSUM="$(/usr/bin/shasum -a 256 "$IPA_PATH" | /usr/bin/awk '{print $1}')"

echo
echo "Build succeeded: $APP_PATH"
echo "IPA artifact: $IPA_PATH"
echo "SHA-256: $CHECKSUM"
echo "The IPA is unsigned and must be signed or installed with a compatible installer."
