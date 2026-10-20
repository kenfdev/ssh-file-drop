---
name: verify-ssh-file-drop
description: Verify the SSH File Drop helper, build, and macOS droplet. Use after changing this project or when asked to prove it works.
---

# Verify SSH File Drop

Use this checklist to verify the current source on this Mac. Do not describe a GUI check as complete unless you actually performed it and recorded the evidence.

## Headless checks

### Helper contract and remote transfer

Run from the repository root:

```bash
bash tests/run.sh
```

The test runner needs an `sshd` reachable by this Mac, a working non-interactive SSH key or agent, and the remote commands used by the tests (`sh`, `mktemp`, `chmod`, `scp`, `stat`, `find`, and related standard tools). It defaults to `localhost`, port `22`, and the current `$USER`; the test host must accept that SSH login. It checks reachability before testing and exits with status 2 if login or host-key scanning fails.

Optional environment variables:

- `SFD_HOSTNAME`: SSH host name; default `localhost`.
- `SFD_PORT`: SSH port; default `22`.
- `SFD_USER`: SSH login; default `$USER`.
- `SFD_IDENTITY`: private key file; default empty, so SSH uses its agent/default keys.
- `SFD_BIG_MB`: large test-file size in MiB; default `200`.

Example for a non-default reachable SSH server:

```bash
SFD_HOSTNAME=localhost SFD_PORT=2222 SFD_USER="$USER" SFD_IDENTITY="$HOME/.ssh/id_ed25519" bash tests/run.sh
```

The runner first executes offline host-candidate extraction tests, then creates temporary local fixtures and remote test files and removes its own test artifacts. The extraction tests cover relative Include paths and globs, repeated files, filtering of wildcard/negated/bad names, ignored Match blocks, explicit-host exclusion, and a missing config. The remote suite reports individual checks and a final passed/failed/skipped count. It exercises the helper's stdout/exit-code contract, transfers, hostile names, input and host rejection, SSH failures, connection timeout, changed-source verification, TERM cancellation, cleanup, and permissions (`0700` directory and `0600` file). It does not exercise the app's Finder/Dock event handling, dialogs, progress UI, or clipboard.

### Build and launch

Build the app from the repository root:

```bash
bash scripts/build.sh
```

This recreates `build/SSH File Drop.app`, compiles the AppleScript, installs the helper, and applies an ad-hoc signature. Confirm the app bundle and embedded helper exist and that the signature verifies:

```bash
test -d 'build/SSH File Drop.app'
test -x 'build/SSH File Drop.app/Contents/Resources/ssh-file-drop-send'
test -x 'build/SSH File Drop.app/Contents/Resources/ssh-file-drop-host-candidates'
/usr/bin/codesign --verify --deep --strict 'build/SSH File Drop.app'
```

To confirm macOS launches the built app, open it and verify the process is running. The app's initial dialog is expected when it is launched without a dropped file:

```bash
open -a "$PWD/build/SSH File Drop.app"
pgrep -fl 'SSH File Drop'
```

A successful build or a running process does not prove the drop-to-clipboard workflow. Keep those claims separate from the GUI check below.

## GUI check

Use macOS GUI automation with `/usr/bin/osascript` and System Events for Finder/app interaction, and `/usr/sbin/screencapture -x` for screenshots. GUI scripting may require granting the automation runner Accessibility permission in System Settings. Exercise a real file-open/drop event to the built app, not just the helper:

1. Prepare a reachable SSH host alias in `~/.ssh/config` that is not yet in `~/.config/ssh-file-drop/hosts`, and confirm the alias works non-interactively from Terminal. Use a harmless test file whose content is safe to transfer.
2. Use Finder/System Events automation to drop the file onto the built app icon (or its Dock icon). Capture the host picker, choose “Host を追加…”, capture the candidate picker, select the SSH-config alias, and then capture its appearance in the explicit host picker. Select it and confirm the transfer.
3. Capture the progress UI while a sufficiently large harmless file is transferring. If testing cancellation, capture the cancellation result and verify that the clipboard is unchanged.
4. Capture the success dialog, then record `pbpaste` and confirm it contains only the returned remote absolute path. On the host, verify that path exists and has mode `600`; verify its containing dedicated directory has mode `700`.
5. Retain the automation transcript and screenshots for the drop, host selection, candidate picker, progress, and result. Record the test host alias and file name, but do not include private key contents or other secrets. State which UI cases were not exercised.

For repeatable event-driven GUI automation without physically dragging, `open -a "$PWD/build/SSH File Drop.app" "$PWD/path/to/test-file"` can send the file-open event to the app; label that as an app-open-event check, not as a Finder/Dock drag. Use screenshots plus `pbpaste` and remote file/mode checks as evidence. Do not infer clipboard success from the success dialog alone.

## Report

Report the exact commands and final test counts. Separate headless results from GUI results and list any untested GUI cases. Do not claim verification for tests or UI steps that were not run.