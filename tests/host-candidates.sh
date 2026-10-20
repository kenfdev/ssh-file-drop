#!/bin/bash
# Offline tests for SSH-config host candidate extraction.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
EXTRACTOR=$ROOT/src/ssh-file-drop-host-candidates
VALIDATOR=$ROOT/src/ssh-file-drop-send
T=$(mktemp -d "${TMPDIR:-/tmp}/sfd-host-test.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
mkdir -p "$T/ssh/parts" "$T/config"
PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); printf 'PASS  host candidates: %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL  host candidates: %s (%s)\n' "$1" "${2:-}"; }

cat >"$T/ssh/config" <<'EOF'
Host root existing *.wild !excluded ?question bad:name bad/name
Include parts/[az].conf
Include parts/cycle.conf
Host duplicate
Match User nobody
Host match-must-be-ignored
Include parts/ignored.conf
EOF
cat >"$T/ssh/parts/a.conf" <<'EOF'
Host alpha
EOF
cat >"$T/ssh/parts/cycle.conf" <<'EOF'
Include config
Host cycle
EOF
cat >"$T/ssh/parts/z.conf" <<'EOF'
Host duplicate nested
EOF
cat >"$T/ssh/parts/ignored.conf" <<'EOF'
Host included-under-match
EOF
printf 'existing\n' >"$T/config/hosts"

OUT=$(SSH_FILE_DROP_SSH_DIR="$T/ssh" \
  SSH_FILE_DROP_CANDIDATES_CONFIG="$T/ssh/config" \
  SSH_FILE_DROP_CONFIG_DIR="$T/config" \
  SSH_FILE_DROP_HOST_VALIDATOR="$VALIDATOR" \
  bash "$EXTRACTOR")
EXPECTED=$(printf 'root\nalpha\nduplicate\nnested\ncycle')
if [ "$OUT" = "$EXPECTED" ]; then ok 'Include globs, relative paths, and ordered deduplication'; else bad 'Include globs and ordering' "got: $OUT"; fi
if ! printf '%s\n' "$OUT" | grep -qxF existing; then ok 'explicit hosts are not offered twice'; else bad 'explicit host exclusion'; fi
FILTERED=0
for name in excluded match-must-be-ignored included-under-match 'bad:name' 'bad/name' '*.wild' '?question'; do
  if printf '%s\n' "$OUT" | grep -qxF -- "$name"; then FILTERED=1; fi
done
if [ "$FILTERED" = 0 ]; then ok 'wildcards, negation, Match blocks, and invalid names are skipped'; else bad 'filtering'; fi

MISSING=$(SSH_FILE_DROP_SSH_DIR="$T/ssh" \
  SSH_FILE_DROP_CANDIDATES_CONFIG="$T/ssh/missing-config" \
  SSH_FILE_DROP_CONFIG_DIR="$T/config" \
  SSH_FILE_DROP_HOST_VALIDATOR="$VALIDATOR" \
  bash "$EXTRACTOR")
if [ -z "$MISSING" ]; then ok 'missing SSH config returns no candidates'; else bad 'missing config' "got: $MISSING"; fi

echo "host candidates passed: $PASS  failed: $FAIL"
[ "$FAIL" = 0 ]
