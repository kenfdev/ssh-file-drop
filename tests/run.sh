#!/bin/bash
# Automated tests for the transfer helper and SSH-config host candidates.
#
# Env:
#   SFD_HOSTNAME  sshd to test against        (default localhost)
#   SFD_PORT      its port                    (default 22)
#   SFD_USER      login user                  (default $USER)
#   SFD_IDENTITY  private key file            (default: use the SSH agent)
#   SFD_BIG_MB    size of the large-file test (default 200)

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
HELPER=$HERE/../src/ssh-file-drop-send
PROXY=$HERE/fixtures/proxy.py

SFD_HOSTNAME=${SFD_HOSTNAME:-localhost}
SFD_PORT=${SFD_PORT:-22}
SFD_USER=${SFD_USER:-$USER}
SFD_IDENTITY=${SFD_IDENTITY:-}
SFD_BIG_MB=${SFD_BIG_MB:-200}

if ! bash "$HERE/host-candidates.sh"; then
  echo "host candidate tests failed" >&2
  exit 1
fi
if ! bash "$HERE/droplet-contract.sh"; then
  echo "droplet contract tests failed" >&2
  exit 1
fi

T=$(mktemp -d "${TMPDIR:-/tmp}/sfd-test.XXXXXX")
CREATED=$T/created-dirs
: >"$CREATED"
PASS=0
FAIL=0
SKIP=0
TAG=$$

ok() { PASS=$((PASS + 1)); printf 'PASS  %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL  %s\n        %s\n' "$1" "${2:-}"; }
skip() { SKIP=$((SKIP + 1)); printf 'SKIP  %s (%s)\n' "$1" "${2:-}"; }
check() { # name, command...
  local name=$1
  shift
  if "$@"; then ok "$name"; else bad "$name" "condition failed: $*"; fi
}
checkx() { # name, shell expression evaluated in this shell
  if eval "$2"; then ok "$1"; else bad "$1" "condition failed: $2"; fi
}

# ---- ssh config fixtures (self-contained, never reads ~/.ssh/config) ----

# ssh uses the first value it sees, so overrides are written before the defaults.
write_config() { # file, known_hosts, [override lines...]; NOIDENTITY=1 drops the real key
  local file=$1 kh=$2
  shift 2
  {
    echo "Host sfd"
    local line
    for line in "$@"; do echo "  $line"; done
    echo "  HostName $SFD_HOSTNAME"
    echo "  Port $SFD_PORT"
    echo "  User $SFD_USER"
    echo "  UserKnownHostsFile $kh"
    echo "  GlobalKnownHostsFile /dev/null"
    echo "  HostKeyAlgorithms ssh-ed25519"
    if [ -n "$SFD_IDENTITY" ] && [ "${NOIDENTITY:-0}" != 1 ]; then
      echo "  IdentityFile $SFD_IDENTITY"
      echo "  IdentitiesOnly yes"
    fi
  } >"$file"
}

ssh-keyscan -p "$SFD_PORT" -t ed25519 "$SFD_HOSTNAME" 2>/dev/null >"$T/known_hosts.raw"
if [ ! -s "$T/known_hosts.raw" ]; then
  echo "cannot read the ed25519 host key of $SFD_HOSTNAME:$SFD_PORT" >&2
  exit 2
fi
# Hash-free copy; the format is accepted for both port 22 and [host]:port.
cp "$T/known_hosts.raw" "$T/known_hosts"
: >"$T/known_hosts.empty"
ssh-keygen -q -t ed25519 -N '' -f "$T/other_key" >/dev/null
if [ "$SFD_PORT" = 22 ]; then KHHOST=$SFD_HOSTNAME; else KHHOST="[$SFD_HOSTNAME]:$SFD_PORT"; fi
printf '%s %s\n' "$KHHOST" "$(cut -d' ' -f1,2 "$T/other_key.pub")" >"$T/known_hosts.changed"

write_config "$T/cfg.ok" "$T/known_hosts"
write_config "$T/cfg.unknown" "$T/known_hosts.empty"
write_config "$T/cfg.changed" "$T/known_hosts.changed"
NOIDENTITY=1 write_config "$T/cfg.badauth" "$T/known_hosts" \
  "IdentityFile $T/nonexistent_key" "IdentitiesOnly yes" "IdentityAgent none" \
  "PreferredAuthentications publickey"
write_config "$T/cfg.refused" "$T/known_hosts" "Port 1"
write_config "$T/cfg.blackhole" "$T/known_hosts" "HostName 10.255.255.1"
write_config "$T/cfg.slow" "$T/known_hosts" \
  "ProxyCommand env PROXY_RATE=10000000 python3 $PROXY %h %p"
write_config "$T/cfg.cut" "$T/known_hosts" \
  "ProxyCommand env PROXY_RATE=10000000 PROXY_DOWN_FILE=$T/down python3 $PROXY %h %p"

# ---- helpers ----

rexec() { # config, remote command string (fixed text, never untrusted names)
  local cfg=$1
  shift
  /usr/bin/ssh -n -F "$cfg" -o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=10 -T -- sfd "$@"
}

R() { rexec "$T/cfg.ok" "$@"; }

OUT= RC= OKPATH= ERRCAT= CLEANUP=
send() { # config, file...
  local cfg=$1
  shift
  OUT=$(SSH_FILE_DROP_SSH_CONFIG=$cfg "$HELPER" sfd "$@" 2>"$T/stderr")
  RC=$?
  parse "$OUT"
}
parse() {
  OKPATH=$(printf '%s\n' "$1" | awk -F'\t' '$1=="OK"{print $2}')
  ERRCAT=$(printf '%s\n' "$1" | awk -F'\t' '$1=="ERR"{print $2}')
  CLEANUP=$(printf '%s\n' "$1" | awk -F'\t' '$1=="CLEANUP"{print $2}')
  [ -z "$OKPATH" ] || printf '%s\n' "$(dirname "$OKPATH")" >>"$CREATED"
}
remote_exists() { R "test -e '$1'"; } # only called with paths we generated (no quotes in them)
remote_dir_gone() { ! R "test -e '$1'"; }

remote_mode() { # path -> octal mode
  R "stat -c %a '$1' 2>/dev/null || stat -f %Lp '$1'"
}

cleanup_all() {
  local d
  while IFS= read -r d; do
    case $d in
      /tmp/ssh-file-drop.*[!A-Za-z0-9]*) continue ;;
      /tmp/ssh-file-drop.?*)
        R "find '$d' -mindepth 1 -maxdepth 1 -type f -delete; rmdir '$d'" 2>/dev/null
        ;;
    esac
  done <"$CREATED"
  R "rm -f sfd-pwned-$TAG-a sfd-pwned-$TAG-b sfd-pwned-$TAG-c" 2>/dev/null
  R "rm -f /tmp/ssh-file-drop.decoy-$TAG/keep; rmdir /tmp/ssh-file-drop.decoy-$TAG" 2>/dev/null
  rm -rf "$T"
}
trap cleanup_all EXIT

F=$T/files
mkdir -p "$F"

# ---- reachability ----

if ! R true; then
  echo "cannot log in to $SFD_USER@$SFD_HOSTNAME:$SFD_PORT with BatchMode (key/agent needed)" >&2
  exit 2
fi
echo "remote: $(R 'uname -sr')"

# decoy that cleanup must never touch
R "mkdir /tmp/ssh-file-drop.decoy-$TAG && touch /tmp/ssh-file-drop.decoy-$TAG/keep"

# ---- basic transfers ----

echo hello >"$F/plain.txt"
send "$T/cfg.ok" "$F/plain.txt"
checkx "plain file: exit 0 and OK line" '[ "$RC" = 0 ] && [ -n "$OKPATH" ]'
check "plain file: OK path has the expected shape" \
  bash -c '[[ "$1" =~ ^/tmp/ssh-file-drop\.[A-Za-z0-9]+/plain\.txt$ ]]' _ "$OKPATH"
check "plain file: stdout is exactly one OK line" [ "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" = 1 ]
D=$(dirname "$OKPATH")
check "plain file: content matches" \
  [ "$(R "cat '$OKPATH'")" = "hello" ]
check "plain file: directory is 0700" [ "$(remote_mode "$D")" = 700 ]
check "plain file: file is 0600" [ "$(remote_mode "$OKPATH")" = 600 ]
check "plain file: only the final name is in the directory" \
  [ "$(R "ls -1A '$D'")" = "plain.txt" ]

: >"$F/empty"
send "$T/cfg.ok" "$F/empty"
check "empty file: transferred, size 0" bash -c '[ "$1" = 0 ] && [ "$2" = "0" ]' _ "$RC" "$(R "wc -c < '$OKPATH' | tr -d ' '")"

dd if=/dev/urandom of="$F/big.bin" bs=1048576 count="$SFD_BIG_MB" 2>/dev/null
LOCAL_SUM=$(cksum <"$F/big.bin")
send "$T/cfg.ok" "$F/big.bin"
check "large file (${SFD_BIG_MB} MB): exit 0" [ "$RC" = 0 ]
check "large file: checksum matches" [ "$(R "cksum < '$OKPATH'")" = "$LOCAL_SUM" ]

# ---- hostile names ----

check_name() { # description, file name (created under $F)
  local desc=$1 name=$2
  printf 'payload for %s\n' "$desc" >"$F/$name"
  send "$T/cfg.ok" "$F/$name"
  if [ "$RC" != 0 ]; then
    bad "name: $desc" "rc=$RC out=$OUT"
    return
  fi
  local d
  d=$(dirname "$OKPATH")
  local want got
  want=$(cksum <"$F/$name")
  got=$(R "cd '$d' && find . -type f -exec sh -c 'cksum < \"\$1\"' _ {} \\;")
  if [ "$OKPATH" = "$d/$name" ] && [ "$want" = "$got" ]; then ok "name: $desc"; else bad "name: $desc" "path=$OKPATH want=$want got=$got"; fi
}
check_name "ordinary filename" "meeting-notes.pdf"
check_name "space" "with space.txt"
check_name "apostrophe" "it's here.txt"
check_name "leading dash" "-rf"
check_name "leading dash option-like" "--help"
check_name "emoji" "🚀rocket.txt"
check_name "command substitution" "\$(touch sfd-pwned-$TAG-a).txt"
check_name "semicolon" "a;touch sfd-pwned-$TAG-b;.txt"
check_name "backticks" "\`touch sfd-pwned-$TAG-c\`.txt"
check_name "double quote and glob" "q\"*?[x].txt"
check_name "dollar and ampersand" "\$HOME & \${PATH} | x.txt"
check_name "colon (scp host: form)" "host:name.txt"
check_name "leading dot" ".hidden"
R "touch sfd-pwned-$TAG-control"
check "injection check can see a file in the remote home (control)" remote_exists "sfd-pwned-$TAG-control"
R "rm -f sfd-pwned-$TAG-control"
check "no injected command ran (a)" remote_dir_gone "sfd-pwned-$TAG-a"
check "no injected command ran (b)" remote_dir_gone "sfd-pwned-$TAG-b"
check "no injected command ran (c)" remote_dir_gone "sfd-pwned-$TAG-c"

long=$(printf 'n%.0s' $(seq 1 250)).txt
check_name "long name (254 bytes)" "$long"

# ---- repeated names ----

echo one >"$F/dup.txt"
send "$T/cfg.ok" "$F/dup.txt"
FIRST=$OKPATH
echo two >"$F/dup.txt"
send "$T/cfg.ok" "$F/dup.txt"
SECOND=$OKPATH
checkx "same name twice: different directories" '[ -n "$FIRST" ] && [ -n "$SECOND" ] && [ "$FIRST" != "$SECOND" ]'
check "same name twice: first file untouched" [ "$(R "cat '$FIRST'")" = one ]
check "same name twice: second file has new content" [ "$(R "cat '$SECOND'")" = two ]

# ---- rejected inputs (no connection needed to be reachable) ----

expect_reject() { # description, args...
  local desc=$1
  shift
  send "$T/cfg.ok" "$@"
  if [ "$RC" = 2 ] && [ "$ERRCAT" = INPUT ] && [ -z "$OKPATH" ] && [ "$CLEANUP" = none ]; then ok "reject: $desc"; else bad "reject: $desc" "rc=$RC out=$OUT"; fi
}
mkdir "$F/adir"
ln -s "$F/plain.txt" "$F/alink"
printf 'x' >"$F/nl$(printf '\nname')"
expect_reject "directory" "$F/adir"
expect_reject "symlink" "$F/alink"
expect_reject "missing file" "$F/does-not-exist"
expect_reject "newline in name" "$F/nl$(printf '\nname')"
expect_reject "multiple inputs" "$F/plain.txt" "$F/empty"
expect_reject "no input"

reject_host() { # description, host
  local desc=$1 host=$2
  local out rc
  out=$(SSH_FILE_DROP_SSH_CONFIG=$T/cfg.ok "$HELPER" "$host" "$F/plain.txt" 2>/dev/null)
  rc=$?
  if [ "$rc" = 2 ] && ! printf '%s' "$out" | grep -q '^OK'; then ok "reject host: $desc"; else bad "reject host: $desc" "rc=$rc out=$out"; fi
}
reject_host "leading dash" "-oProxyCommand=touch"
reject_host "option with value" "-F/etc/passwd"
reject_host "space" "a b"
reject_host "semicolon" "a;b"
reject_host "newline" "$(printf 'a\nb')"
reject_host "empty" ""
reject_host "scp colon" "a:b"

# ---- connection failures: no OK, no clipboard-relevant output ----

expect_conn_fail() { # description, config
  local desc=$1 cfg=$2
  local start=$SECONDS
  send "$cfg" "$F/plain.txt"
  if [ "$RC" = 3 ] && [ "$ERRCAT" = CONNECT ] && [ -z "$OKPATH" ]; then ok "connect failure: $desc"; else bad "connect failure: $desc" "rc=$RC out=$OUT stderr=$(cat "$T/stderr")"; fi
  LAST_ELAPSED=$((SECONDS - start))
}
expect_conn_fail "unknown host key" "$T/cfg.unknown"
check "unknown host key: known_hosts was not modified" [ ! -s "$T/known_hosts.empty" ]
expect_conn_fail "changed host key" "$T/cfg.changed"
expect_conn_fail "authentication failure" "$T/cfg.badauth"
expect_conn_fail "connection refused" "$T/cfg.refused"
expect_conn_fail "unroutable address (timeout bound)" "$T/cfg.blackhole"
check "unroutable address: gave up within 30 s" [ "$LAST_ELAPSED" -le 30 ]
expect_conn_fail "config says StrictHostKeyChecking no, helper still refuses" "$T/cfg.unknown"

# ---- source changes while uploading ----

dd if=/dev/urandom of="$F/growing.bin" bs=1048576 count=100 2>/dev/null
(SSH_FILE_DROP_SSH_CONFIG=$T/cfg.slow "$HELPER" sfd "$F/growing.bin" >"$T/grow.out" 2>/dev/null; echo $? >"$T/grow.rc") &
sleep 4
printf 'more' >>"$F/growing.bin"
wait
parse "$(cat "$T/grow.out")"
checkx "source changed mid-transfer: reported as failure, no OK" '[ "$(cat "$T/grow.rc")" = 6 ] && [ "$ERRCAT" = VERIFY ] && [ -z "$OKPATH" ]'
check "source changed mid-transfer: remote directory cleaned" [ "$CLEANUP" = done ]
check "decoy directory survived cleanup" R "test -f /tmp/ssh-file-drop.decoy-$TAG/keep"

# ---- cancel (TERM) during upload ----

before=$(R 'ls -1d /tmp/ssh-file-drop.* 2>/dev/null | sort')
(SSH_FILE_DROP_SSH_CONFIG=$T/cfg.slow "$HELPER" sfd "$F/big.bin" >"$T/cancel.out" 2>/dev/null; echo $? >"$T/cancel.rc") &
sleep 4
CPID=$(pgrep -f "ssh-file-drop-send sfd $F/big.bin" | head -1)
kill -TERM "$CPID"
wait
parse "$(cat "$T/cancel.out")"
after=$(R 'ls -1d /tmp/ssh-file-drop.* 2>/dev/null | sort')
checkx "cancel: exit 130, CANCELLED, no OK line" '[ "$(cat "$T/cancel.rc")" = 130 ] && [ "$ERRCAT" = CANCELLED ] && [ -z "$OKPATH" ]'
checkx "cancel: owned directory removed" '[ "$CLEANUP" = done ] && [ "$before" = "$after" ]'
sleep 1
checkx "cancel: no stray proxy processes left" '! pgrep -f "fixtures/proxy.py" >/dev/null'

# ---- connection cut during upload ----

before_cut=$(R 'ls -1d /tmp/ssh-file-drop.* 2>/dev/null | sort')
(SSH_FILE_DROP_SSH_CONFIG=$T/cfg.cut "$HELPER" sfd "$F/big.bin" >"$T/cut.out" 2>/dev/null; echo $? >"$T/cut.rc") &
sleep 4
touch "$T/down"
wait
rm -f "$T/down"
parse "$(cat "$T/cut.out")"
checkx "connection cut: UPLOAD failure, no OK" '[ "$(cat "$T/cut.rc")" = 5 ] && [ "$ERRCAT" = UPLOAD ] && [ -z "$OKPATH" ]'
check "connection cut: cleanup failure is reported, not hidden" [ "$CLEANUP" = failed ]
after_cut=$(R 'ls -1d /tmp/ssh-file-drop.* 2>/dev/null | sort')
leftover=$(printf '%s\n' "$after_cut" | grep -vxF "$before_cut")
[ -z "$leftover" ] || printf '%s\n' "$leftover" >>"$CREATED"
checkx "connection cut: exactly one directory was left behind (removed by this test afterwards)" '[ "$(printf "%s\n" "$leftover" | grep -c .)" = 1 ]'

# ---- summary ----

echo
echo "passed: $PASS  failed: $FAIL  skipped: $SKIP"
[ "$FAIL" = 0 ]
