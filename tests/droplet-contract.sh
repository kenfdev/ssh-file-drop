#!/bin/bash
# Headless regression checks for the AppleScript droplet's multi-file flow.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
SOURCE=$HERE/../src/droplet.applescript

fail() { echo "FAIL  $1" >&2; exit 1; }
pass() { echo "PASS  $1"; }
line() { grep -nF "$1" "$SOURCE" | awk -F: 'NR == 1 { print $1; found = 1 } END { if (!found) exit 1 }'; }

validate=$(line 'repeat with droppedItem in theItems') || fail 'prevalidation loop exists'
check=$(line 'my runHelperTolerant({"--check-file", filePath})') || fail 'each item is checked'
choose=$(line 'set hostName to my chooseHost(fileNames)') || fail 'one host is chosen'
[ "$validate" -lt "$check" ] && [ "$check" -lt "$choose" ] || fail 'all items must be checked before host choice'
pass 'checks every dropped item before host choice'

transfer=$(line 'repeat with fileIndex from 1 to totalFiles') || fail 'ordered transfer loop exists'
call=$(line 'my transfer(hostName, item fileIndex of filePaths') || fail 'helper transfer call uses the indexed item'
[ "$transfer" -lt "$call" ] || fail 'transfer call is outside the ordered loop'
pass 'sends files in dropped order through the per-file transfer handler'

line "set AppleScript's text item delimiters to linefeed" >/dev/null || fail 'clipboard paths use LF separators'
line 'set body to "File: " & fileName' >/dev/null || fail 'failure identifies the file'
line '" path(s) copied to the clipboard."' >/dev/null || fail 'failure reports copied path count'
line 'on copyPartial(sentPaths)' >/dev/null || fail 'partial results have a clipboard path'
pass 'preserves line-based clipboard output and partial-failure reporting'
