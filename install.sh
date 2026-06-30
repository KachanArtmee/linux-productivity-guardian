#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
bin_dir="${HOME}/.local/bin"
config_dir="${HOME}/.config/productivity-guardian"
unit_dir="${HOME}/.config/systemd/user"

if [[ "${EUID}" -eq 0 ]]; then
    printf 'Run this installer as the desktop user, without sudo.\n' >&2
    exit 1
fi

printf 'Installing Productivity Guardian for %s...\n' "$USER"

install -d -m 0755 "$bin_dir" "$config_dir" "$unit_dir"
install -m 0755 "$script_dir/scripts/guardian.sh" "$bin_dir/productivity-guardian"
install -m 0644 "$script_dir/systemd/productivity.service" "$unit_dir/productivity-guardian.service"

if [[ ! -e "$config_dir/guardian.conf" ]]; then
    install -m 0600 "$script_dir/configs/guardian.conf.example" "$config_dir/guardian.conf"
    printf 'Created safe dry-run configuration: %s\n' "$config_dir/guardian.conf"
else
    printf 'Preserved existing configuration: %s\n' "$config_dir/guardian.conf"
fi

systemctl --user daemon-reload
systemctl --user enable --now productivity-guardian.service

printf 'Installation complete. Follow logs with:\n'
printf '  journalctl --user -u productivity-guardian.service -f\n'
