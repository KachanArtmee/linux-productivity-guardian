# Linux Productivity Guardian

Linux Productivity Guardian is a small Linux/systemd utility that watches for
a local Dota 2 installation and removes it when it appears.

The project is intentionally simple: an installer places a shell script into
`/usr/local/bin`, registers a systemd service, and keeps that service running in
the background.

> Warning: this tool closes Steam and deletes the local Dota 2 files without
> asking for confirmation. Use it only on your own machine and only if this is
> exactly what you want.

## What It Does

- checks the default Steam installation path for Dota 2 every 10 minutes;
- stops Steam with `pkill -9 steam` when Dota 2 is found;
- removes the Dota 2 game directory;
- removes the Steam app manifest for app ID `570`;
- sends a desktop notification after deletion.

The watched paths are defined in `scripts/uninstall-dota.sh`:

```bash
$HOME/.local/share/Steam/steamapps/common/dota 2 beta
$HOME/.local/share/Steam/steamapps/appmanifest_570.acf
```

## Project Structure

```text
linux-productivity-guardian/
+-- install.sh
+-- scripts/
|   `-- uninstall-dota.sh
`-- systemd/
    `-- productivity.service
```

## Requirements

- Linux with systemd;
- Bash;
- Steam installed under the default user path;
- `notify-send` for desktop notifications, usually provided by `libnotify`;
- root privileges for installation.

## Installation

Run the installer from the project root:

```bash
chmod +x install.sh
sudo ./install.sh
```

The installer will:

1. copy `scripts/uninstall-dota.sh` to `/usr/local/bin/focus-enforcer`;
2. make `/usr/local/bin/focus-enforcer` executable;
3. copy `systemd/productivity.service` to `/etc/systemd/system/`;
4. replace the service user placeholder with the user that ran `sudo`;
5. enable and start `productivity.service`.

## Service Management

Check service status:

```bash
systemctl status productivity.service
```

Follow logs:

```bash
journalctl -u productivity.service -f
```

Stop the service:

```bash
sudo systemctl stop productivity.service
```

Disable the service:

```bash
sudo systemctl disable productivity.service
```

## Uninstallation

```bash
sudo systemctl disable --now productivity.service
sudo rm -f /etc/systemd/system/productivity.service
sudo rm -f /usr/local/bin/focus-enforcer
sudo systemctl daemon-reload
```

## Configuration

To change what the guardian removes, edit the paths in
`scripts/uninstall-dota.sh` before running the installer.

If the service is already installed, reinstall it after editing:

```bash
sudo ./install.sh
```
