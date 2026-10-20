#!/bin/bash
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/ssh-file-drop-icon.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
ICONSET="$WORK/AppIcon.iconset"
mkdir "$ICONSET"

for size in 16 32 128 256 512; do
  /usr/bin/sips -z "$size" "$size" "$ROOT/assets/icon-1024.png" \
    --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  pixels=$((size * 2))
  /usr/bin/sips -z "$pixels" "$pixels" "$ROOT/assets/icon-1024.png" \
    --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
/usr/bin/iconutil -c icns "$ICONSET" -o "$ROOT/assets/AppIcon.icns"
echo "icon: $ROOT/assets/AppIcon.icns"
