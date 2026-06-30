# Productivity Guardian

Productivity Guardian is a Linux daemon written in Bash that automatically
detects and suppresses unwanted software, files, and processes.

The project started as a joke script that deleted Dota 2 whenever it appeared
on the system. It has since evolved into a long-term DevOps learning project
focused on Linux automation, service management, containers, infrastructure,
and observability.

Current version: **v2.0.0**

> **Warning**
>
> `soft`, `aggressive`, and `silent` modes delete configured paths and signal
> host processes. Keep the default `dry-run` mode until the configuration and
> logs have been reviewed.

## Features

### File monitoring

- Periodically scans configured files and directories.
- Removes detected targets in enforcing modes.
- Rejects relative paths, wildcards, critical paths, and targets outside an
  explicitly allowed root.

### Process monitoring

- Monitors configured process names independently from file detection.
- Matches exact Linux process names through `/proc`.
- Can send `SIGTERM`, escalate to `SIGKILL`, or only report in dry-run mode.

### Configuration reload

The configuration is reloaded during every scan cycle. Valid changes are
applied without restarting the daemon or containers. An invalid configuration
activates safe defaults: no targets and `dry-run` mode.

### Logging

The systemd service writes structured logs to journald with the
`productivity-guardian` tag. Containers write the same structured events to
standard output for Docker's logging driver.

Log levels are `INFO`, `WARN`, `ERROR`, `CRITICAL`, and `DRY-RUN`.

### Dependency validation

Required system utilities and `/proc` availability are checked during startup.
The service exits with a critical log entry when its runtime dependencies are
missing.

## Operating modes

- `dry-run` detects targets and logs proposed actions without changing the
  system. This is the default.
- `soft` removes files and sends `SIGTERM` to processes.
- `aggressive` removes files, sends `SIGTERM`, waits for the configured grace
  period, and escalates surviving processes to `SIGKILL`.
- `silent` removes files and immediately sends `SIGKILL`; desktop notifications
  are disabled.

Desktop notifications are attempted only in `soft` and `aggressive` modes for
the local systemd installation. Container deployments use Docker logs because
they do not share the desktop user's D-Bus session.

## Configuration

The active repository configuration is [`configs/guardian.conf`](configs/guardian.conf).
A safe template is available at
[`configs/guardian.conf.example`](configs/guardian.conf.example).

```ini
SCAN_INTERVAL=600
TERM_GRACE_PERIOD=10
MODE=dry-run

ALLOWED_ROOT=~
PATH=~/.local/share/Steam/steamapps/common/dota 2 beta
PATH=~/.local/share/Steam/steamapps/appmanifest_570.acf
PROCESS=steam
```

`PATH`, `PROCESS`, and `ALLOWED_ROOT` may be repeated. `~` means the current
user's home in a systemd installation and the `/host-home` bind mount in
Docker. Process names are matched exactly against `/proc/<pid>/comm` and are
therefore limited by the Linux process-name representation.

Protected paths include:

```text
/
/etc
/usr
/var
/proc
/sys
/dev
/home
```

Children of a configured, user-specific allowed root such as `/home/alice` are
valid; the protected directory itself is not.

## Docker deployment

Version 2.0 runs as two independent services built from one image:

| Service | Responsibility | Host access |
| --- | --- | --- |
| `guardian-files` | File and directory detection/removal | Only the configured home bind mount |
| `guardian-processes` | Exact process detection/termination | Host PID namespace and `KILL` capability |

This deployment requires native Linux Docker Engine. Docker Desktop on macOS
or Windows cannot expose macOS/Windows host processes to a Linux container.

1. Create the Compose environment file and set the absolute Linux host home:

   ```bash
   cp .env.example .env
   $EDITOR .env
   ```

2. Review `configs/guardian.conf` and keep `MODE=dry-run` for the first run.

3. Build and start both services:

   ```bash
   docker compose up -d --build
   ```

4. Inspect health and dry-run events:

   ```bash
   docker compose ps
   docker compose logs -f
   ```

5. After verifying every detected target, select an enforcing mode in
   `configs/guardian.conf`. The workers reload it during the next scan cycle.

Stop the deployment with:

```bash
docker compose down
```

The containers have no network, use read-only root filesystems, store only a
heartbeat in a small tmpfs, and receive only the Linux capabilities required by
their individual responsibility. The file worker never mounts the complete
host root.

## Local systemd installation

Requirements:

- Linux with systemd user services;
- Bash 4 or newer;
- GNU `coreutils`;
- optional `notify-send` for desktop notifications.

Install for the current desktop user (do not use `sudo`):

```bash
chmod +x install.sh
./install.sh
```

The installer places the daemon in `~/.local/bin`, creates a safe configuration
in `~/.config/productivity-guardian`, and enables the systemd user service.

Useful commands:

```bash
systemctl --user status productivity-guardian.service
journalctl --user -u productivity-guardian.service -f
systemctl --user restart productivity-guardian.service
systemctl --user disable --now productivity-guardian.service
```

## Running manually

Run all monitors in the foreground:

```bash
GUARDIAN_CONFIG=./configs/guardian.conf ./scripts/guardian.sh all
```

The `files` and `processes` roles can also be started independently.

## Project structure

```text
linux-productivity-guardian/
├── configs/
│   ├── guardian.conf
│   └── guardian.conf.example
├── docker/
│   └── healthcheck.sh
├── scripts/
│   ├── guardian.sh
│   └── uninstall-dota.sh
├── systemd/
│   └── productivity.service
├── tests/
│   └── test-guardian.sh
├── compose.yaml
├── Dockerfile
├── CHANGELOG.md
├── README.md
└── install.sh
```

## Development checks

```bash
bash -n scripts/*.sh docker/*.sh tests/*.sh install.sh
./tests/test-guardian.sh
GUARDIAN_HOST_HOME="$HOME" docker compose config --quiet
```

## Known limitations

- Linux only.
- Bash implementation.
- Linux process names exposed by `/proc/<pid>/comm` are limited to 15 visible
  characters on common kernels.
- Docker process enforcement requires the host PID namespace and `KILL`
  capability.
- No central event storage or metrics endpoint yet.

## Roadmap

### v3.0.0

- Python rewrite
- Telegram notifications
- REST API

### v4.0.0

- Kubernetes deployment
- GitLab CI/CD
- Automated releases

### v5.0.0

- Prometheus metrics
- Grafana dashboards
- Monitoring stack

## Learning goals

This project is used to practice Linux, Bash, systemd, Docker, CI/CD,
Kubernetes, monitoring, and Infrastructure as Code while continuously evolving
a single real-world codebase.
