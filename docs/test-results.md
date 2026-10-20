# Test Results

Test date: 2026-10-20. Tested app source: working tree based on commit `c372080`; the project has no separately numbered app version.

Tests ran on macOS 26.5 (build 25F71) with OpenSSH 10.2p1. SSH integration tests connected to `localhost:22` on the same Mac, which reported remote OS `Darwin 25.5.0`. These tests do not verify dropping files through Finder or the Dock.

## Executed tests

| Acceptance area | Command and result |
| --- | --- |
| Transfer empty, regular, and large files; verify paths, contents, and permissions. | `bash tests/run.sh` passed. The 200 MiB checksum matched; empty and regular files also passed. Remote directories were mode `0700` and completed files were mode `0600`. Final count: `passed: 61  failed: 0  skipped: 0`. |
| Ensure special file names are not executed as commands and repeat transfers do not overwrite existing files. | `bash tests/run.sh` passed for spaces, apostrophes, leading hyphens, command substitutions, semicolons, backticks, quotes, glob characters, emoji, and other names. No injection marker files were created. Repeated names used separate paths and preserved both contents. |
| Reject folders, symbolic links, multiple helper inputs, and invalid host names. | `bash tests/run.sh` passed. The helper rejects multiple arguments. The droplet checks every dropped item before starting transfers and rejects the entire drop if any item is not a regular file. |
| Reject unknown or changed host keys, authentication failures, refused connections, and unreachable hosts. | `bash tests/run.sh` passed for all cases, including a check that an unknown host key does not change the temporary known-hosts file. The unreachable address failed within 30 seconds. |
| Detect a source file changed during transfer and clean up its owned incomplete directory. | `bash tests/run.sh` passed. The helper returned a verification failure without an OK path and reported successful cleanup. |
| Cancel an active transfer and clean up its owned incomplete directory. | `bash tests/run.sh` passed. Sending TERM to the helper returned status 130 and completed cleanup. The app's progress Stop button was not exercised. |
| Report cleanup failure after a connection cut. | `bash tests/run.sh` passed. The helper returned an upload failure and `CLEANUP failed`; the test observed the one leftover directory and removed its test data afterward. |
| Extract host candidates from SSH configuration. | `bash tests/host-candidates.sh` passed: `host candidates passed: 4  failed: 0`. `bash tests/run.sh` also runs these four checks. |
| Build, install, sign, and test replacement safeguards and host-file preservation. | `bash tests/install.sh` passed: `install passed: 20  failed: 0`. It installed and launched the signed app in a temporary home, dismissed the information dialog with System Events, and tested replacement and refusal cases. It did not change the user's installed app or SSH configuration. |
| Build the app and verify its bundle and signature. | `bash scripts/build.sh` passed. The bundle and both embedded helpers existed and were executable, and `codesign --verify --deep --strict 'build/SSH File Drop.app'` passed. `osacompile` accepted the translated AppleScript during the build. |

## Static checks

The following behavior was checked in `src/droplet.applescript`, `src/ssh-file-drop-send`, and `src/ssh-file-drop-host-candidates`. These checks did not exercise a real file drop.

| Behavior | Code observation |
| --- | --- |
| Select the last successful host by default and allow choosing another host. | The droplet reads `last_host` and uses it as the default when it is in the host list. The host picker allows another selection, and the helper saves the host after a successful transfer. |
| Handle multi-file drops and reject folders before transfer. | The droplet validates each item before host selection or transfer. It sends files in drop order. If any validation fails, it rejects the whole drop. If a transfer fails or is cancelled, it stops at that file. Paths for earlier completed transfers are copied one per line; if the first transfer fails, the clipboard is left unchanged. |
| Set the clipboard after successful transfers and report copy failures separately. | The droplet copies the returned path list after full success. On a later-file failure, it copies paths for already sent files. It offers a retry if clipboard copying fails after a successful transfer. Actual clipboard contents were not checked. |
| Give guidance when the GUI app cannot use the SSH agent. | SSH uses batch mode and connection-liveness limits. The `CONNECT` message suggests checking the connection and host key from Terminal and mentions GUI access to the SSH agent. This GUI condition was not exercised. |
| Distinguish transfer failures from remote cleanup failures. | The droplet displays separate cleanup notes for `failed` and `unknown`. The helper's cleanup-failure response was exercised by the connection-cut test, but the GUI message was not triggered. |

## Not verified

| Area | What was not tested |
| --- | --- |
| Finder or Dock drop flow. | No file was dropped through Finder or the Dock. The install test only launched the app and dismissed its information dialog. |
| Host picker and multi-file UI. | Host selection, last-host default, progress UI, multi-file sequencing, and early rejection of a mixed drop were checked in code or through droplet contract checks, not through a GUI session. |
| GUI cancellation and errors. | The app's Stop button, GUI display of connection and transfer errors, clipboard-copy failure, and cleanup warnings were not exercised. |
| Real clipboard contents. | The tests did not inspect `pbpaste` or otherwise verify the clipboard. |
| GUI SSH-agent access. | No GUI test was run with an agent that worked in Terminal but was unavailable to the app. |
| Other remote operating systems. | Only Darwin 25.5.0 was tested. Linux and other systems were not tested. |
| Minimum supported macOS version. | Build, signature, install, and launch were checked on macOS 26.5. Compatibility with older releases was not checked. |
