# SSH File Drop

SSH File Drop is a macOS droplet app that sends dropped files to `/tmp` on a selected SSH host and copies the remote paths to the clipboard.

## Requirements and support

- The app uses the macOS AppleScript droplet feature and built-in command-line tools. Build and install tests were run on macOS 26.5. Older macOS versions have not been tested.
- The remote host needs SSH access and POSIX tools such as `sh`, `mktemp`, `chmod`, `printf`, `wc`, and `mv`. The remote user must be able to create and write under `/tmp`. The tested remote OS was macOS (Darwin 25.5.0); Linux and other systems have not been tested.
- The app uses macOS tools including `/usr/bin/ssh`, `/usr/bin/scp`, `osacompile`, `codesign`, and `ditto`. No additional runtime is required.
- The app uses your existing SSH configuration, keys, and agent. It does not ask for or store passwords or key passphrases.

## Build and install

Run these commands from the repository root:

```sh
scripts/build.sh
scripts/install.sh
```

`build.sh` creates `build/SSH File Drop.app`. `install.sh` builds the app and installs it by default at `~/Applications/SSH File Drop.app`. If the installed app is running, the installer waits for it to quit and stops without replacing it if it does not quit. The installer does not change the Dock or SSH settings.

To add the app to the Dock, drag `~/Applications/SSH File Drop.app` from Finder to the Dock. Use the installed copy, not `build/SSH File Drop.app`, because each build replaces the app in `build/`.

## Add an SSH host

1. Find the host alias you want to use. For example, this entry in `~/.ssh/config` defines the alias `dev-server`:

   ```sshconfig
   Host dev-server
     HostName server.example.com
     User myname
     IdentityFile ~/.ssh/id_ed25519
   ```

2. The first time, run `ssh dev-server` in Terminal. Check the displayed host-key fingerprint and accept it only if you trust the host. Confirm that login works, then run `exit`. Do not configure SSH to trust host keys automatically.
3. After you drop files, the app shows the host list. Choose “+ Add Host...” to select a candidate from `~/.ssh/config`, or enter a host name. Hosts are saved one per line in `~/.config/ssh-file-drop/hosts`. Candidate extraction is simple and does not fully interpret SSH configuration. You can enter an alias that is not listed.

This is an explicit list of selectable hosts. Editing `~/.ssh/config` does not add hosts automatically. The app passes the selected host name to OpenSSH, which resolves the connection settings.

### Terminal and Finder/Dock differences

An app launched from Terminal may have different environment variables and SSH-agent access than one launched from Finder or the Dock. The app does not necessarily load your shell startup files. If the app cannot connect, try `ssh dev-server` in Terminal. If that also fails, fix the SSH connection, key, or host key. If Terminal works but the app does not, the GUI app may not be able to access your SSH agent. Check `IdentityAgent` or `AddKeysToAgent` in your SSH configuration. The app reports connection failures and does not automatically trust host keys.

## Usage

Drop one or more regular files from Finder onto the `SSH File Drop` icon in the Dock or Finder. Folders and other non-regular items are rejected before any file is sent. Choose a host and select “Transfer”. Files are sent in drop order. On success, the clipboard contains one remote path per line, for example `/tmp/ssh-file-drop.a1B2c3D4/report.pdf`. Result dialogs show up to 10 paths, followed by `... N more` when needed. The clipboard still contains every path. The app does not paste or run commands for you.

If a transfer fails or is cancelled, the app stops at that file. Paths for files already sent are copied to the clipboard, one per line. If the first file fails, the clipboard is left unchanged.

Double-clicking the app opens an information dialog; it does not send files.

Each file is placed in a new `/tmp/ssh-file-drop.*` directory on the selected host. Directories have mode `0700`, and completed files have mode `0600`. Sending files with the same name creates separate directories, so existing files are not overwritten. The OS may remove files under `/tmp`, including after a restart. Do not use this location for long-term storage.

## Rejected input and limits

- Folders, symbolic links, unreadable files, names containing line breaks or control characters, names longer than 255 bytes, and the reserved temporary name are rejected. Folders and non-regular items in a multi-item drop are rejected before transfer begins.
- Transfers show progress and can be cancelled. After the first transfer failure, later files are not sent. If cleanup cannot be confirmed after a disconnect, the app warns that an incomplete working directory may remain.
- Host names must be valid registered SSH aliases. Unsupported characters are rejected.
- Only remote paths are copied. If a path contains spaces and you use it in a shell, quote it as needed.
- The app does not automatically delete files from `/tmp`, transfer folders, or provide Finder Quick Actions.

## Uninstall

1. Quit the app if it is running.
2. Move `~/Applications/SSH File Drop.app` to the Trash in Finder. Remove it from the Dock too, if needed.
3. Only if you also want to remove the app's settings, delete `~/.config/ssh-file-drop/hosts` and `~/.config/ssh-file-drop/last_host`. Do not delete `~/.ssh/config`, keys, or `known_hosts`; they are not app settings.
4. To remove remote files, connect to a registered host and inspect your own `/tmp/ssh-file-drop.*` directories. Delete only individual directories you no longer need. Do not delete all of `/tmp` or directories you have not inspected.

See [`docs/test-results.md`](docs/test-results.md) for test results and items that have not been verified.
