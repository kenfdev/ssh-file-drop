# Design Notes

The acceptance criteria are maintained in [`docs/acceptance-criteria.md`](acceptance-criteria.md). This document records implementation decisions.

## Components

| File | Responsibility |
| --- | --- |
| `src/ssh-file-drop-send` | Transfer helper, compatible with Bash 3.2. It has no UI. |
| `src/droplet.applescript` | Droplet UI for host selection, progress, cancellation, results, and clipboard updates. |
| `scripts/build.sh` | Uses `osacompile` to build the app, adds the helper and `assets/AppIcon.icns`, and applies an ad-hoc signature. Removes the generated `Assets.car` because it takes precedence over the custom icon. |
| `scripts/make-icon.sh` | Creates a standard `.iconset` from `assets/icon-1024.png` and regenerates `assets/AppIcon.icns` with `sips` and `iconutil`. Normal builds do not regenerate the icon. |
| `scripts/install.sh` | Builds the app, waits for the installed app to quit, and replaces `~/Applications/SSH File Drop.app`. `SSH_FILE_DROP_INSTALL_DIR` selects a test destination. If the app does not quit within 30 seconds, installation stops and preserves the existing app. Set `SSH_FILE_DROP_QUIT_TIMEOUT_SECONDS` to change the wait from 1 to 300 seconds. The installer does not change the Dock or user settings. |
| `tests/` | Automated tests for the helper, SSH host-candidate extraction, and droplet contract. |

## Helper contract

Invocation: `ssh-file-drop-send HOST FILE`

Standard output uses tab separators and only these forms:

- Success: `OK<TAB>/tmp/ssh-file-drop.xxxxxxxx/name`
- Failure: `ERR<TAB>CATEGORY<TAB>message`
- Cleanup state on failure, on the line after ERR: `CLEANUP<TAB>none|done|failed|unknown`

Standard error is for diagnostics. Do not print file contents or secrets.

Exit codes: 0 success, 2 rejected input, 3 connection/authentication/host key, 4 remote setup, 5 upload, 6 verification, 7 finalization, and 130 cancellation.

ERR categories are `INPUT`, `CONNECT`, `REMOTE_SETUP`, `UPLOAD`, `VERIFY`, `FINALIZE`, and `CANCELLED`.

### State machine

Phases move only forward: `VALIDATE → MKDIR → UPLOAD → VERIFY → FINALIZE → DONE`.

- Set `OWNED_DIR` only after `mktemp -d` returns a path matching `^/tmp/ssh-file-drop\.[A-Za-z0-9]+$`.
- Cleanup runs only when `OWNED_DIR` is set and finalization is not complete.
- Cleanup runs only `rm -f DIR/.ssh-file-drop.partial` and `rmdir DIR`. Never use `rm -rf` or wildcards.
- If the result of the final rename is unknown, do not delete anything and return `CLEANUP unknown`.

### Input validation

- A single regular file is accepted by the helper. Directories, final-component symbolic links, and missing paths are rejected with `INPUT`.
- Reject basenames containing newlines or control characters (0x00-0x1f, 0x7f), basenames longer than 255 bytes, and the reserved name `.ssh-file-drop.partial`.
- HOST must match `^[A-Za-z0-9_][A-Za-z0-9._@:%+-]*$`. Reject leading `-`, spaces, and control characters. Pass the host to ssh after `--`.

### SSH calls

- Executables are `/usr/bin/ssh` and `/usr/bin/scp`; do not rely on PATH.
- Common options are `BatchMode=yes`, `StrictHostKeyChecking=yes`, `ConnectTimeout=10`, `ServerAliveInterval=5`, `ServerAliveCountMax=3`, `ClearAllForwardings=yes`, and `ControlMaster=no`. ssh also uses `-T`.
- If `SSH_FILE_DROP_SSH_CONFIG` is set, pass it with `-F` for tests. It is normally unset.
- Pass remote commands as a fixed shell script with `sh -c '<script>' sh <args...>`. Quote the script and every argument with the same single-quote function. Never concatenate a file name into a command string.
- Use `scp` with only a generated fixed remote path (`DIR/.ssh-file-drop.partial`). User-provided names never reach scp's remote-path parsing. Pass the local path as an absolute path to avoid interpreting it as `host:`.

### Transfer steps

1. Create a remote directory with `umask 077` and `mktemp -d /tmp/ssh-file-drop.XXXXXXXX`. Validate the output and set `OWNED_DIR`.
2. Upload to `.ssh-file-drop.partial` with `scp`. Record local size and modification time before starting.
3. Verify that the local size and modification time did not change and that remote `wc -c` matches the local size.
4. Finalize with `chmod 600 partial && mv -- partial 'name'`, then confirm the file exists. The directory remains mode `0700`.
5. Print `OK`.

### Cancellation

- Trap TERM and INT. Run child processes in the background and wait for them so traps can run promptly.
- Stop the child, clean up when safe, print `ERR CANCELLED` and a `CLEANUP` line, then exit with status 130.

## Droplet behavior

- `on open` accepts one or more dropped items. It checks every item with `--check-file` before sending any file. If any item is not a regular file, the entire drop is rejected and an alert identifies the item and reason.
- The user chooses one host for the whole drop. Files are sent sequentially in drop order through the unchanged single-file helper. Progress names the current file and its position.
- Each helper call creates a fresh remote directory, so equal basenames never overwrite one another.
- On full success, the clipboard contains all returned remote paths in drop order, separated by line breaks with no trailing line break. A one-file drop copies one path with no trailing line break.
- On failure or cancellation, sending stops at the current file. The helper's existing cleanup handles that file's partial upload. Previously completed paths are copied to the clipboard, one per line. If the first file fails, the clipboard is left unchanged. The alert identifies the failed file and reason, states the number of copied paths, and retains the helper's transfer-category and cleanup-failure details.
- The host list is `~/.config/ssh-file-drop/hosts` (one alias per line; `#` comments are allowed). The last successful host is stored in `~/.config/ssh-file-drop/last_host`.
- “+ Add Host...” runs `src/ssh-file-drop-host-candidates` to extract candidates from `~/.ssh/config`. Includes are glob-expanded relative to `~/.ssh`, to a maximum recursion depth of 8. Repeated files are skipped and Match blocks are ignored. Names containing `*`, `?`, or a leading `!`, and names rejected by the transfer helper's host validator, are excluded. Extraction supports simple whitespace-separated Include paths and globs. It does not support quoted paths with spaces, evaluate Match conditions, or expand Host patterns to their actual connection targets.
- The user can choose a candidate or enter a host manually. Only the selected host is validated and appended to `hosts`. The list remains an explicit selection list and is not synchronized automatically because SSH configuration can include wildcards or Host declarations that are not connection targets.
- The host picker shows the dropped file names, uses “Transfer” and “Cancel” buttons, and places “+ Add Host...” at the end of the list.
- The helper runs in the background and writes stdout to a temporary file. The app shows a spinner with `progress total steps` and `progress description`, and waits for exit with `kill -0`. Stop raises AppleScript error -128, so the app sends TERM to the helper and waits for it to finish before showing cancellation.
- The app updates the clipboard only after success. If copying fails, it shows the path and offers a retry without repeating the transfer.
- Failure messages differ by CATEGORY. For `CONNECT`, the app asks the user to run `ssh HOST` in Terminal to check the connection and host key.
- If `CLEANUP` is `failed` or `unknown`, the app warns that an incomplete directory may remain on the host.

## Rejected alternatives

| Alternative | Reason |
| --- | --- |
| Transfer with `ssh host 'cat > path'` | `scp` is sufficient and was specified for this app. |
| Use a user-provided filename as the remote scp path | scp path parsing differs between SFTP and legacy modes. Upload to a fixed name and rename it with `mv`. |
| Use `~/.ssh/config` as the permanent host list | Host patterns and conditional settings can be present. Candidates are offered during add-host; the actual selection list contains only explicitly registered aliases. |
| Use a Python or Node helper | Avoid an external runtime; Bash and AppleScript are sufficient. |
