#!/bin/bash
# Builds build/SSH File Drop.app from src/. Safe to run again; it replaces the previous build.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP="$ROOT/build/SSH File Drop.app"

mkdir -p "$ROOT/build"
rm -rf "$APP"
/usr/bin/osacompile -o "$APP" "$ROOT/src/droplet.applescript"

install -m 755 "$ROOT/src/ssh-file-drop-send" "$APP/Contents/Resources/ssh-file-drop-send"
install -m 755 "$ROOT/src/ssh-file-drop-host-candidates" "$APP/Contents/Resources/ssh-file-drop-host-candidates"
install -m 644 "$ROOT/assets/AppIcon.icns" "$APP/Contents/Resources/droplet.icns"
# osacompile's asset catalog takes precedence over the custom droplet.icns.
rm -f "$APP/Contents/Resources/Assets.car"
/usr/bin/codesign --force --deep -s - "$APP"

echo "built: $APP"
