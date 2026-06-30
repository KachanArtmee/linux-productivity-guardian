#!/usr/bin/env bash

set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
guardian="$project_dir/scripts/guardian.sh"
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT

assert_file_exists() {
    [[ -e "$1" ]] || {
        printf 'Expected file to exist: %s\n' "$1" >&2
        exit 1
    }
}

assert_file_missing() {
    [[ ! -e "$1" ]] || {
        printf 'Expected file to be absent: %s\n' "$1" >&2
        exit 1
    }
}

write_config() {
    local mode="$1"
    local target="$2"
    cat > "$test_root/guardian.conf" <<EOF
SCAN_INTERVAL=1
TERM_GRACE_PERIOD=1
MODE=$mode
ALLOWED_ROOT=$test_root
PATH=$target
EOF
}

target="$test_root/forbidden file"
touch "$target"
write_config dry-run "$target"

dry_run_output="$(
    GUARDIAN_CONFIG="$test_root/guardian.conf" \
    GUARDIAN_HOME="$test_root" \
    GUARDIAN_NOTIFICATIONS=false \
    GUARDIAN_RUN_ONCE=true \
        "$guardian" files
)"
assert_file_exists "$target"
grep -q 'level=DRY-RUN' <<< "$dry_run_output"

write_config soft "$target"
GUARDIAN_CONFIG="$test_root/guardian.conf" \
GUARDIAN_HOME="$test_root" \
GUARDIAN_NOTIFICATIONS=false \
GUARDIAN_RUN_ONCE=true \
    "$guardian" files >/dev/null
assert_file_missing "$target"

target="$test_root/protected-by-fallback"
touch "$target"
write_config soft "$target"
printf 'UNKNOWN_KEY=value\n' >> "$test_root/guardian.conf"

GUARDIAN_CONFIG="$test_root/guardian.conf" \
GUARDIAN_HOME="$test_root" \
GUARDIAN_NOTIFICATIONS=false \
GUARDIAN_RUN_ONCE=true \
    "$guardian" files >/dev/null
assert_file_exists "$target"

cat > "$test_root/root-target.conf" <<EOF
SCAN_INTERVAL=1
TERM_GRACE_PERIOD=1
MODE=soft
ALLOWED_ROOT=$test_root
PATH=$test_root
EOF

GUARDIAN_CONFIG="$test_root/root-target.conf" \
GUARDIAN_HOME="$test_root" \
GUARDIAN_NOTIFICATIONS=false \
GUARDIAN_RUN_ONCE=true \
    "$guardian" files >/dev/null
assert_file_exists "$test_root"

if [[ "$(uname -s)" == "Linux" ]]; then
    process_binary="$test_root/guardian-proc"
    cp "$(command -v sleep)" "$process_binary"
    "$process_binary" 30 &
    process_pid=$!

    cat > "$test_root/process.conf" <<EOF
SCAN_INTERVAL=1
TERM_GRACE_PERIOD=1
MODE=aggressive
ALLOWED_ROOT=$test_root
PROCESS=guardian-proc
EOF

    GUARDIAN_CONFIG="$test_root/process.conf" \
    GUARDIAN_HOME="$test_root" \
    GUARDIAN_NOTIFICATIONS=false \
    GUARDIAN_RUN_ONCE=true \
        "$guardian" processes >/dev/null

    if kill -0 "$process_pid" 2>/dev/null; then
        printf 'Expected process to be terminated: %s\n' "$process_pid" >&2
        kill -KILL "$process_pid" 2>/dev/null || true
        exit 1
    fi
fi

printf 'All guardian tests passed.\n'
