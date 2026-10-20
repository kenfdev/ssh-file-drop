#!/bin/bash
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
INSTALL_DIR=${SSH_FILE_DROP_INSTALL_DIR:-"$HOME/Applications"}
QUIT_TIMEOUT=${SSH_FILE_DROP_QUIT_TIMEOUT_SECONDS:-30}
case "$QUIT_TIMEOUT" in
  *[!0-9]*|'') echo 'quit timeout must be an integer from 1 to 300 seconds' >&2; exit 1 ;;
esac
if ! [ "$QUIT_TIMEOUT" -ge 1 ] || ! [ "$QUIT_TIMEOUT" -le 300 ]; then
  echo 'quit timeout must be an integer from 1 to 300 seconds' >&2
  exit 1
fi
mkdir -p "$INSTALL_DIR"
INSTALL_DIR=$(cd "$INSTALL_DIR" && pwd -P)
APP="$INSTALL_DIR/SSH File Drop.app"
if [ -L "$APP" ] || { [ -e "$APP" ] && [ ! -d "$APP" ]; }; then
  echo "refusing to replace a symlink or non-directory: $APP" >&2
  exit 1
fi
if [ "$APP" = "$ROOT/build/SSH File Drop.app" ]; then
  echo "install directory must differ from the build directory" >&2
  exit 1
fi

/bin/bash "$ROOT/scripts/build.sh"
STAGE=$(mktemp -d "$INSTALL_DIR/.ssh-file-drop-install.XXXXXX")
cleanup() {
  if [ -d "$STAGE/previous.app" ] && [ ! -e "$APP" ]; then
    if ! mv "$STAGE/previous.app" "$APP"; then
      echo "could not restore the previous app; saved at $STAGE/previous.app" >&2
      return
    fi
  fi
  rm -rf "$STAGE"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
/usr/bin/ditto "$ROOT/build/SSH File Drop.app" "$STAGE/SSH File Drop.app"
/usr/bin/codesign --verify --deep --strict "$STAGE/SSH File Drop.app"

# Address the installed path so a test destination cannot quit another copy.
if ! /usr/bin/osascript - "$APP" "$QUIT_TIMEOUT" <<'APPLESCRIPT'
on run argv
  set appPath to item 1 of argv
  set quitTimeout to item 2 of argv as integer
  if application appPath is running then
    ignoring application responses
      tell application appPath to quit
    end ignoring
    repeat quitTimeout times
      if application appPath is not running then return
      delay 1
    end repeat
    if application appPath is running then error "SSH File Drop is still running."
  end if
end run
APPLESCRIPT
then
  echo 'SSH File Drop was not replaced. Finish or close its app window, then run this installer again.' >&2
  exit 1
fi

if [ -d "$APP" ]; then
  mv "$APP" "$STAGE/previous.app"
fi
mv "$STAGE/SSH File Drop.app" "$APP"
echo "installed: $APP"
