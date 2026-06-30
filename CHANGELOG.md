# Changelog

All notable changes to Productivity Guardian are documented in this file.

## [2.0.0] - 2026-06-30

### Added

- Docker image for the Bash guardian runtime.
- Docker Compose deployment with independent file and process workers.
- Container health checks, bounded Docker logs, and safe runtime hardening.
- Exact process matching through the host PID namespace.
- Shared, reloadable configuration with dry-run defaults and allowed-root checks.

### Changed

- Refactored the daemon into `all`, `files`, and `processes` roles.
- Converted the installer to a systemd user-service installation.
- Replaced the hard-coded Dota 2 behavior with configuration-driven targets.
