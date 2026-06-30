#!/usr/bin/env bash

set -uo pipefail

readonly SERVICE_NAME="productivity-guardian"
readonly DEFAULT_SCAN_INTERVAL=600
readonly DEFAULT_TERM_GRACE_PERIOD=10

ROLE="${1:-all}"
CONFIG_FILE="${GUARDIAN_CONFIG:-$HOME/.config/productivity-guardian/guardian.conf}"
GUARDIAN_HOME="${GUARDIAN_HOME:-$HOME}"
HEARTBEAT_FILE="${GUARDIAN_HEARTBEAT_FILE:-/tmp/productivity-guardian.heartbeat}"

SCAN_INTERVAL=$DEFAULT_SCAN_INTERVAL
TERM_GRACE_PERIOD=$DEFAULT_TERM_GRACE_PERIOD
MODE="dry-run"
STOP_REQUESTED=0
declare -a ALLOWED_ROOTS=()
declare -a TARGET_PATHS=()
declare -a TARGET_PROCESSES=()
declare -a MATCHED_PIDS=()

trim() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

log_message() {
    local level="$1"
    shift

    local timestamp message line
    timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || printf 'unknown-time')"
    message="$*"
    message="${message//\\/\\\\}"
    message="${message//\"/\\\"}"
    line="timestamp=$timestamp level=$level service=$ROLE message=\"$message\""

    if [[ "${GUARDIAN_LOG_TARGET:-stdout}" == "journald" ]] && command -v logger >/dev/null 2>&1; then
        logger --tag "$SERVICE_NAME" -- "$line"
    else
        printf '%s\n' "$line"
    fi
}

reset_to_safe_defaults() {
    SCAN_INTERVAL=$DEFAULT_SCAN_INTERVAL
    TERM_GRACE_PERIOD=$DEFAULT_TERM_GRACE_PERIOD
    MODE="dry-run"
    ALLOWED_ROOTS=("$GUARDIAN_HOME")
    TARGET_PATHS=()
    TARGET_PROCESSES=()
}

is_protected_path() {
    case "$1" in
        /|/etc|/usr|/var|/proc|/sys|/dev|/home)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

expand_guardian_home() {
    case "$1" in
        '~')
            printf '%s' "$GUARDIAN_HOME"
            ;;
        '~/'*)
            printf '%s/%s' "${GUARDIAN_HOME%/}" "${1#\~/}"
            ;;
        *)
            printf '%s' "$1"
            ;;
    esac
}

normalize_config_path() {
    local raw_path="$1"
    local expanded_path

    if [[ -z "$raw_path" || "$raw_path" == *$'\n'* || "$raw_path" == *$'\r'* ]]; then
        return 1
    fi

    case "$raw_path" in
        *'*'*|*'?'*|*'['*|*']'*)
            return 1
            ;;
    esac

    case "/$raw_path/" in
        */../*)
            return 1
            ;;
    esac

    expanded_path="$(expand_guardian_home "$raw_path")"
    [[ "$expanded_path" == /* ]] || return 1
    realpath -m -- "$expanded_path"
}

validate_number() {
    local value="$1"
    local minimum="$2"
    local maximum="$3"

    [[ "$value" =~ ^[0-9]+$ ]] || return 1
    (( value >= minimum && value <= maximum ))
}

load_config() {
    reset_to_safe_defaults

    if [[ ! -r "$CONFIG_FILE" ]]; then
        log_message "ERROR" "configuration is not readable: $CONFIG_FILE; safe defaults are active"
        return 1
    fi

    local candidate_interval=$DEFAULT_SCAN_INTERVAL
    local candidate_grace=$DEFAULT_TERM_GRACE_PERIOD
    local candidate_mode="dry-run"
    local line key value normalized
    local line_number=0
    local invalid=0
    local -a candidate_roots=()
    local -a candidate_paths=()
    local -a candidate_processes=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_number += 1))
        line="${line%$'\r'}"
        line="$(trim "$line")"

        [[ -z "$line" || "${line:0:1}" == "#" ]] && continue

        if [[ "$line" != *=* ]]; then
            log_message "ERROR" "invalid configuration line $line_number: expected KEY=VALUE"
            invalid=1
            continue
        fi

        key="$(trim "${line%%=*}")"
        value="$(trim "${line#*=}")"

        case "$key" in
            SCAN_INTERVAL)
                if validate_number "$value" 1 86400; then
                    candidate_interval="$value"
                else
                    log_message "ERROR" "SCAN_INTERVAL must be between 1 and 86400 seconds"
                    invalid=1
                fi
                ;;
            TERM_GRACE_PERIOD)
                if validate_number "$value" 0 300; then
                    candidate_grace="$value"
                else
                    log_message "ERROR" "TERM_GRACE_PERIOD must be between 0 and 300 seconds"
                    invalid=1
                fi
                ;;
            MODE)
                case "$value" in
                    dry-run|soft|aggressive|silent)
                        candidate_mode="$value"
                        ;;
                    *)
                        log_message "ERROR" "MODE must be dry-run, soft, aggressive, or silent"
                        invalid=1
                        ;;
                esac
                ;;
            ALLOWED_ROOT)
                if normalized="$(normalize_config_path "$value")" && ! is_protected_path "$normalized"; then
                    candidate_roots+=("${normalized%/}")
                else
                    log_message "ERROR" "unsafe ALLOWED_ROOT on line $line_number: $value"
                    invalid=1
                fi
                ;;
            PATH)
                if normalized="$(normalize_config_path "$value")" && ! is_protected_path "$normalized"; then
                    candidate_paths+=("${normalized%/}")
                else
                    log_message "ERROR" "unsafe PATH on line $line_number: $value"
                    invalid=1
                fi
                ;;
            PROCESS)
                if [[ "$value" =~ ^[a-zA-Z0-9._+-]{1,15}$ ]]; then
                    candidate_processes+=("$value")
                else
                    log_message "ERROR" "process name must contain 1-15 safe characters on line $line_number: $value"
                    invalid=1
                fi
                ;;
            *)
                log_message "ERROR" "unknown configuration key on line $line_number: $key"
                invalid=1
                ;;
        esac
    done < "$CONFIG_FILE"

    if (( invalid != 0 )); then
        log_message "WARN" "configuration validation failed; safe dry-run defaults are active"
        return 1
    fi

    if (( ${#candidate_roots[@]} == 0 )); then
        if normalized="$(normalize_config_path "$GUARDIAN_HOME")" && ! is_protected_path "$normalized"; then
            candidate_roots=("${normalized%/}")
        else
            log_message "ERROR" "GUARDIAN_HOME is unsafe; safe defaults are active"
            return 1
        fi
    fi

    SCAN_INTERVAL="$candidate_interval"
    TERM_GRACE_PERIOD="$candidate_grace"
    MODE="$candidate_mode"
    ALLOWED_ROOTS=("${candidate_roots[@]}")
    TARGET_PATHS=("${candidate_paths[@]}")
    TARGET_PROCESSES=("${candidate_processes[@]}")

    log_message "INFO" "configuration loaded: mode=$MODE interval=${SCAN_INTERVAL}s"
    return 0
}

path_is_allowed() {
    local target="$1"
    local root

    is_protected_path "$target" && return 1

    for root in "${ALLOWED_ROOTS[@]}"; do
        [[ "$target" == "$root" ]] && return 1
    done

    for root in "${ALLOWED_ROOTS[@]}"; do
        if [[ "$target" == "$root/"* ]]; then
            return 0
        fi
    done

    return 1
}

send_notification() {
    local message="$1"

    [[ "$MODE" == "soft" || "$MODE" == "aggressive" ]] || return 0
    [[ "${GUARDIAN_NOTIFICATIONS:-true}" == "true" ]] || return 0

    if command -v notify-send >/dev/null 2>&1; then
        notify-send "Productivity Guardian" "$message" >/dev/null 2>&1 || \
            log_message "WARN" "desktop notification could not be delivered"
    fi
}

run_file_cycle() {
    local configured_target target

    for configured_target in "${TARGET_PATHS[@]}"; do
        if ! target="$(realpath -m -- "$configured_target")"; then
            log_message "ERROR" "could not resolve configured path: $configured_target"
            continue
        fi

        if ! path_is_allowed "$target"; then
            log_message "CRITICAL" "blocked path outside allowed roots: $target"
            continue
        fi

        [[ -e "$target" || -L "$target" ]] || continue
        log_message "WARN" "detected forbidden path: $target"

        if [[ "$MODE" == "dry-run" ]]; then
            log_message "DRY-RUN" "would remove path: $target"
            continue
        fi

        if rm -rf -- "$target"; then
            log_message "INFO" "removed path: $target"
            send_notification "Removed forbidden path: $target"
        else
            log_message "ERROR" "failed to remove path: $target"
        fi
    done
}

collect_matching_pids() {
    local target_name="$1"
    local comm_file pid process_name
    MATCHED_PIDS=()

    for comm_file in /proc/[0-9]*/comm; do
        [[ -r "$comm_file" ]] || continue
        pid="${comm_file#/proc/}"
        pid="${pid%/comm}"

        [[ "$pid" =~ ^[0-9]+$ ]] || continue
        (( pid > 1 )) || continue
        [[ "$pid" != "$$" && "$pid" != "$PPID" ]] || continue

        IFS= read -r process_name < "$comm_file" || continue
        [[ "$process_name" == "$target_name" ]] && MATCHED_PIDS+=("$pid")
    done
}

pid_still_matches() {
    local pid="$1"
    local expected_name="$2"
    local actual_name

    [[ -r "/proc/$pid/comm" ]] || return 1
    IFS= read -r actual_name < "/proc/$pid/comm" || return 1
    [[ "$actual_name" == "$expected_name" ]]
}

terminate_process() {
    local pid="$1"
    local process_name="$2"
    local deadline

    case "$MODE" in
        dry-run)
            log_message "DRY-RUN" "would terminate process: name=$process_name pid=$pid"
            ;;
        soft)
            if kill -TERM "$pid" 2>/dev/null; then
                log_message "INFO" "sent SIGTERM to process: name=$process_name pid=$pid"
                send_notification "Stopped forbidden process: $process_name"
            else
                log_message "ERROR" "failed to send SIGTERM: name=$process_name pid=$pid"
            fi
            ;;
        aggressive)
            if ! kill -TERM "$pid" 2>/dev/null; then
                log_message "ERROR" "failed to send SIGTERM: name=$process_name pid=$pid"
                return
            fi

            log_message "INFO" "sent SIGTERM to process: name=$process_name pid=$pid"
            deadline=$((SECONDS + TERM_GRACE_PERIOD))
            while (( SECONDS < deadline )) && pid_still_matches "$pid" "$process_name"; do
                sleep 1
            done

            if pid_still_matches "$pid" "$process_name"; then
                if kill -KILL "$pid" 2>/dev/null; then
                    log_message "WARN" "escalated to SIGKILL: name=$process_name pid=$pid"
                else
                    log_message "ERROR" "failed to send SIGKILL: name=$process_name pid=$pid"
                fi
            fi
            send_notification "Stopped forbidden process: $process_name"
            ;;
        silent)
            if kill -KILL "$pid" 2>/dev/null; then
                log_message "INFO" "sent SIGKILL to process: name=$process_name pid=$pid"
            else
                log_message "ERROR" "failed to send SIGKILL: name=$process_name pid=$pid"
            fi
            ;;
    esac
}

run_process_cycle() {
    local process_name pid

    for process_name in "${TARGET_PROCESSES[@]}"; do
        collect_matching_pids "$process_name"
        for pid in "${MATCHED_PIDS[@]}"; do
            log_message "WARN" "detected forbidden process: name=$process_name pid=$pid"
            terminate_process "$pid" "$process_name"
        done
    done
}

write_heartbeat() {
    if ! touch "$HEARTBEAT_FILE" 2>/dev/null; then
        log_message "WARN" "could not update heartbeat: $HEARTBEAT_FILE"
    fi
}

check_dependencies() {
    local command_name
    local -a required=(date realpath sleep touch)

    if [[ "$ROLE" == "files" || "$ROLE" == "all" ]]; then
        required+=(rm)
    fi

    for command_name in "${required[@]}"; do
        if ! command -v "$command_name" >/dev/null 2>&1; then
            log_message "CRITICAL" "required utility is missing: $command_name"
            return 1
        fi
    done

    if [[ "$ROLE" == "processes" || "$ROLE" == "all" ]]; then
        if [[ ! -r /proc/1/comm ]]; then
            log_message "CRITICAL" "/proc is unavailable; process monitoring cannot start"
            return 1
        fi
    fi
}

request_stop() {
    STOP_REQUESTED=1
    log_message "INFO" "shutdown requested"
}

main() {
    case "$ROLE" in
        all|files|processes)
            ;;
        *)
            printf 'Usage: %s [all|files|processes]\n' "$0" >&2
            return 64
            ;;
    esac

    check_dependencies || return 1
    trap request_stop INT TERM
    log_message "INFO" "guardian worker started"

    while (( STOP_REQUESTED == 0 )); do
        load_config || true

        case "$ROLE" in
            all)
                run_file_cycle
                run_process_cycle
                ;;
            files)
                run_file_cycle
                ;;
            processes)
                run_process_cycle
                ;;
        esac

        write_heartbeat

        if [[ "${GUARDIAN_RUN_ONCE:-false}" == "true" ]]; then
            break
        fi

        sleep "$SCAN_INTERVAL" &
        wait $! || true
    done

    log_message "INFO" "guardian worker stopped"
}

main
