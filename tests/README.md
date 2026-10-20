# Tests

Run the scripts from the repository root on macOS:

```sh
bash tests/host-candidates.sh
bash tests/run.sh
bash tests/install.sh
```

- `host-candidates.sh` tests SSH-config candidate extraction offline. It creates temporary SSH config files and does not connect to a server.
- `run.sh` runs the host-candidate tests, the droplet contract checks, and integration tests for `src/ssh-file-drop-send`. It connects to an SSH server, uploads files, and tests failure and cancellation cases. It removes test files and test-created remote directories when it exits. A connection-cut test can intentionally leave one temporary remote directory; the script reports the cleanup state and then attempts to remove that test directory.
- `install.sh` builds and installs into a temporary home, tests replacement safeguards, and launches the app. It needs a logged-in macOS GUI session. The script uses System Events to dismiss the app's dialog, so macOS may require Accessibility permission for the terminal or test runner. It cleans up its temporary install directory.

## SSH server requirement for `run.sh`

The default target is `localhost`, port `22`, using the current login name and SSH agent. An SSH server (`sshd`) must listen on the target port, and public-key authentication must let the test user log in without interaction. The test obtains the server's Ed25519 host key with `ssh-keyscan` and uses temporary SSH configuration and known-host files. It does not use the user's normal SSH config or known-hosts file. The helper tests also need Python 3 for the local proxy fixture and standard macOS tools such as `ssh-keyscan`, `ssh-keygen`, `dd`, `cksum`, and `pgrep`.

To use another SSH server, set one or more variables before running the script:

| Variable | Default | Purpose |
| --- | --- | --- |
| `SFD_HOSTNAME` | `localhost` | SSH server name or address. |
| `SFD_PORT` | `22` | SSH server port. |
| `SFD_USER` | current `$USER` | Remote login name. |
| `SFD_IDENTITY` | empty | Private key file. If omitted, the SSH agent is used. |
| `SFD_BIG_MB` | `200` | Size in MiB of the large-file test. |

Example:

```sh
SFD_HOSTNAME=localhost SFD_PORT=2222 SFD_USER=tester \
  SFD_IDENTITY="$HOME/.ssh/test_key" SFD_BIG_MB=50 \
  bash tests/run.sh
```

The suite creates temporary keys and SSH config files locally. It needs enough local disk space for test files, including the large-file test, and enough remote `/tmp` space. Use a test SSH account and server: the suite creates and removes test data under the remote user's home and `/tmp`.

## Other environment variables

`host-candidates.sh` normally sets up its own fixture paths. These variables can override them for direct extractor tests:

| Variable | Purpose |
| --- | --- |
| `SSH_FILE_DROP_SSH_DIR` | SSH directory used for resolving relative `Include` paths. |
| `SSH_FILE_DROP_CANDIDATES_CONFIG` | SSH config file to parse. |
| `SSH_FILE_DROP_CONFIG_DIR` | Directory containing the explicit `hosts` list. |
| `SSH_FILE_DROP_HOST_VALIDATOR` | Path to the helper used to validate host names. |

`run.sh` uses `SSH_FILE_DROP_SSH_CONFIG` internally to point the helper at each temporary test config. Avoid setting it externally; the tests pass their own configuration for each case.

`install.sh` supports these variables:

| Variable | Default | Purpose |
| --- | --- | --- |
| `SSH_FILE_DROP_INSTALL_DIR` | temporary test home under `$TMPDIR` | Install destination used by the test. |
| `SSH_FILE_DROP_QUIT_TIMEOUT_SECONDS` | `30` | Time allowed for a running app to quit before replacement. |

`install.sh` calls `scripts/build.sh`, which writes `build/SSH File Drop.app` in the worktree. It does not modify the user's installed app or SSH configuration.
