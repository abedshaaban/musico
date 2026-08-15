#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE_IMAGE="${1:-$PROJECT_DIR/design/app-icon-concepts/spatial-pulse.png}"
ICON_DIR="$PROJECT_DIR/Musico/Resources/Assets.xcassets/AppIcon.appiconset"

if [[ ! -f "$SOURCE_IMAGE" ]]; then
  echo "App icon source image not found: $SOURCE_IMAGE" >&2
  exit 1
fi

read -r WIDTH HEIGHT ALPHA < <(
  sips -g pixelWidth -g pixelHeight -g hasAlpha "$SOURCE_IMAGE" 2>/dev/null \
    | awk '/pixelWidth/{w=$2} /pixelHeight/{h=$2} /hasAlpha/{a=$2} END{print w, h, a}'
)

if [[ "$WIDTH" != "$HEIGHT" || "$WIDTH" -lt 1024 ]]; then
  echo "Source must be a square image at least 1024x1024; found ${WIDTH}x${HEIGHT}." >&2
  exit 1
fi

if [[ "$ALPHA" == "yes" ]]; then
  echo "Source must not contain transparency." >&2
  exit 1
fi

mkdir -p "$ICON_DIR"

resize_icon() {
  local pixels="$1"
  local filename="$2"
  sips --resampleHeightWidth "$pixels" "$pixels" "$SOURCE_IMAGE" \
    --out "$ICON_DIR/$filename" >/dev/null
}

resize_icon 40 "AppIcon-20@2x.png"
resize_icon 60 "AppIcon-20@3x.png"
resize_icon 58 "AppIcon-29@2x.png"
resize_icon 87 "AppIcon-29@3x.png"
resize_icon 80 "AppIcon-40@2x.png"
resize_icon 120 "AppIcon-40@3x.png"
resize_icon 120 "AppIcon-60@2x.png"
resize_icon 180 "AppIcon-60@3x.png"
resize_icon 1024 "AppIcon-1024.png"

echo "Generated AppIcon assets from: $SOURCE_IMAGE"
echo "Output: $ICON_DIR"
