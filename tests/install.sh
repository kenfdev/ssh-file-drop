#!/bin/bash
# macOS integration checks. All installs use a private temporary directory.
# Closing the real test dialog needs a GUI session and System Events Accessibility access.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/sfd-install-test.XXXXXX")
APP="$T/home/Applications/SSH File Drop.app"
BUSY_PID=
close_test_dialog() {
  /usr/bin/osascript - "$BUSY_PID" <<'APPLESCRIPT'
on run argv
  set appPID to item 1 of argv as integer
  with timeout of 5 seconds
    tell application "System Events"
      tell (first application process whose unix id is appPID)
        click button "OK" of window 1
      end tell
    end tell
  end timeout
end run
APPLESCRIPT
}
cleanup() {
  if [ -n "$BUSY_PID" ] && /bin/kill -0 "$BUSY_PID" 2>/dev/null; then
    close_test_dialog >/dev/null 2>&1 || true
    echo "test material retained at $T for inspection" >&2
    return
  fi
  /usr/bin/osascript - "$APP" <<'APPLESCRIPT' >/dev/null 2>&1 || true
on run argv
  set appPath to item 1 of argv
  ignoring application responses
    if application appPath is running then tell application appPath to quit
  end ignoring
end run
APPLESCRIPT
  rm -rf "$T"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
PASS=0
check() {
  if "$@"; then
    PASS=$((PASS + 1))
    printf 'PASS  install: %s\n' "$*"
  else
    printf 'FAIL  install: %s\n' "$*" >&2
    exit 1
  fi
}

mkdir -p "$T/home/.config/ssh-file-drop"
printf 'keep-host\n' >"$T/hosts.expected"
cp "$T/hosts.expected" "$T/home/.config/ssh-file-drop/hosts"
(unset SSH_FILE_DROP_INSTALL_DIR; HOME="$T/home" /bin/bash "$ROOT/scripts/install.sh")
check test -d "$APP"
check /usr/bin/cmp "$ROOT/assets/AppIcon.icns" "$APP/Contents/Resources/droplet.icns"
check /usr/bin/cmp "$ROOT/src/ssh-file-drop-send" "$APP/Contents/Resources/ssh-file-drop-send"
check /usr/bin/cmp "$ROOT/src/ssh-file-drop-host-candidates" "$APP/Contents/Resources/ssh-file-drop-host-candidates"
check test ! -e "$APP/Contents/Resources/Assets.car"
check /usr/bin/codesign --verify --deep --strict "$APP"

printf 'obsolete\n' >"$APP/obsolete-resource"
"$APP/Contents/MacOS/droplet" >/dev/null 2>&1 &
BUSY_PID=$!
sleep 2
/usr/bin/ditto "$APP" "$T/before-busy.app"
START=$SECONDS
if SSH_FILE_DROP_INSTALL_DIR="$T/home/Applications" SSH_FILE_DROP_QUIT_TIMEOUT_SECONDS=3 \
  /bin/bash "$ROOT/scripts/install.sh" >"$T/busy.log" 2>&1; then
  echo 'FAIL  install: busy app was replaced' >&2
  exit 1
fi
check test "$((SECONDS - START))" -lt 15
check /usr/bin/grep -q 'Finish or close its app window' "$T/busy.log"
check /usr/bin/diff -qr "$T/before-busy.app" "$APP"
close_test_dialog
for attempt in 1 2 3 4 5; do
  /bin/kill -0 "$BUSY_PID" 2>/dev/null || break
  sleep 1
done
if /bin/kill -0 "$BUSY_PID" 2>/dev/null; then
  echo 'FAIL  install: test dialog did not close' >&2
  exit 1
fi
wait "$BUSY_PID" || true
BUSY_PID=

/usr/bin/osacompile -o "$APP" <<'APPLESCRIPT'
on run
end run
on idle
  return 1
end idle
APPLESCRIPT
/usr/bin/open -n "$APP"
RUNNING=false
for attempt in 1 2 3 4 5 6 7 8 9 10; do
  RUNNING=$(/usr/bin/osascript - "$APP" <<'APPLESCRIPT'
on run argv
  set appPath to item 1 of argv
  return application appPath is running
end run
APPLESCRIPT
  )
  [ "$RUNNING" = true ] && break
  sleep 1
done
check test "$RUNNING" = true
SSH_FILE_DROP_INSTALL_DIR="$T/home/Applications" /bin/bash "$ROOT/scripts/install.sh"
RUNNING=$(/usr/bin/osascript - "$APP" <<'APPLESCRIPT'
on run argv
  set appPath to item 1 of argv
  return application appPath is running
end run
APPLESCRIPT
)
check test "$RUNNING" = false
check test ! -e "$APP/obsolete-resource"
check /usr/bin/codesign --verify --deep --strict "$APP"
check /usr/bin/cmp "$T/hosts.expected" "$T/home/.config/ssh-file-drop/hosts"

SSH_FILE_DROP_INSTALL_DIR="$T/override with spaces" /bin/bash "$ROOT/scripts/install.sh"
check test -x "$T/override with spaces/SSH File Drop.app/Contents/MacOS/droplet"
check /usr/bin/codesign --verify --deep --strict "$T/override with spaces/SSH File Drop.app"

mkdir "$T/refuse"
ln -s "$APP" "$T/refuse/SSH File Drop.app"
if SSH_FILE_DROP_INSTALL_DIR="$T/refuse" /bin/bash "$ROOT/scripts/install.sh"; then
  echo 'FAIL  install: symlink destination was accepted' >&2
  exit 1
fi
check test -L "$T/refuse/SSH File Drop.app"
if SSH_FILE_DROP_INSTALL_DIR="$ROOT/build" /bin/bash "$ROOT/scripts/install.sh"; then
  echo 'FAIL  install: build directory was accepted' >&2
  exit 1
fi
check /usr/bin/codesign --verify --deep --strict "$ROOT/build/SSH File Drop.app"
for invalid in 0 301 invalid; do
  if SSH_FILE_DROP_INSTALL_DIR="$T/invalid-timeout" SSH_FILE_DROP_QUIT_TIMEOUT_SECONDS="$invalid" \
    /bin/bash "$ROOT/scripts/install.sh"; then
    echo "FAIL  install: invalid timeout was accepted: $invalid" >&2
    exit 1
  fi
done
check test ! -e "$T/invalid-timeout"
LEFTOVERS=$(/usr/bin/find "$T" -name '.ssh-file-drop-install.*' -print)
check test -z "$LEFTOVERS"
echo "install passed: $PASS  failed: 0"
