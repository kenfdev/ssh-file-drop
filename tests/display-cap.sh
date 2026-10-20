#!/bin/bash
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/sfd-display.XXXXXX")
trap 'rm -rf "$T"' EXIT
/usr/bin/osacompile -o "$T/drop.scpt" "$HERE/../src/droplet.applescript"

check_count() {
  local count=$1 expected=$2 lines='' i actual
  for ((i=1; i<=count; i++)); do lines+="path$i"; [ "$i" -eq "$count" ] || lines+=$'\n'; done
  actual=$(/usr/bin/osascript - "$T/drop.scpt" "$lines" <<'APPLESCRIPT'
on run argv
  set appScript to load script POSIX file (item 1 of argv)
  tell appScript to return limitedLines(item 2 of argv)
end run
APPLESCRIPT
)
  [ "$actual" = "$expected" ] || { printf 'FAIL display cap %s: got <%s> expected <%s>\n' "$count" "$actual" "$expected" >&2; exit 1; }
  printf 'PASS display cap %s\n' "$count"
}
check_count 0 ''
check_count 1 'path1'
check_count 10 "$(printf 'path%s\n' $(seq 1 9))$(printf '\npath10')"
check_count 11 "$(printf 'path%s\n' $(seq 1 9))$(printf '\npath10\n... 1 more')"
check_count 25 "$(printf 'path%s\n' $(seq 1 9))$(printf '\npath10\n... 15 more')"
