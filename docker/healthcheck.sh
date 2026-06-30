#!/usr/bin/env bash

set -uo pipefail

heartbeat_file="${GUARDIAN_HEARTBEAT_FILE:-/tmp/productivity-guardian.heartbeat}"
config_file="${GUARDIAN_CONFIG:-/etc/productivity-guardian/guardian.conf}"
scan_interval=600

trim() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

if [[ -r "$config_file" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        line="$(trim "$line")"
        case "$line" in
            SCAN_INTERVAL=*)
                candidate="$(trim "${line#*=}")"
                if [[ "$candidate" =~ ^[0-9]+$ ]] && (( candidate >= 1 && candidate <= 86400 )); then
                    scan_interval="$candidate"
                fi
                ;;
        esac
    done < "$config_file"
fi

[[ -f "$heartbeat_file" ]] || exit 1

now="$(date +%s)"
last_heartbeat="$(stat -c %Y "$heartbeat_file")"
maximum_age=$((scan_interval + 60))

(( now - last_heartbeat <= maximum_age ))
