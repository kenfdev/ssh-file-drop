# Acceptance Criteria

These criteria are carried forward from the project brief.

- Verify the full flow from dropping files onto the app through transfer and copying the path.
- Confirm that the last successful host is selected by default and can be changed.
- Transfer empty, regular, and large files.
- Confirm that names containing spaces, apostrophes, a leading `-`, `$()`, or `;` are not executed as commands.
- Confirm that sending files with the same name twice does not overwrite the earlier file.
- Reject folders, symbolic links, and unsupported drop contents with a clear reason.
- Confirm that unknown or changed host keys, authentication failures, unreachable hosts, interrupted transfers, and cancellation do not report success or update the clipboard incorrectly.
- Confirm completed files have mode `0600` and their dedicated directories have mode `0700`.
- Confirm that the app remains responsive and gives useful guidance when the SSH agent works in Terminal but is unavailable to the GUI app.
- Report clipboard-copy failures and cleanup failures separately from transfer status.
