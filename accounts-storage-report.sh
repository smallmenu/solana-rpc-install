#!/bin/bash
set -euo pipefail

# On-demand AccountsDB disk usage report. This script intentionally performs
# full directory scans and is not called by the continuous performance monitor.

SERVICE_NAME=${SERVICE_NAME:-sol}
RPC_URL=${RPC_URL:-http://127.0.0.1:8899}
ACCOUNTS_DIR=${ACCOUNTS_DIR:-/root/sol/accounts}
DEFAULT_ANCIENT_OFFSET=${DEFAULT_ANCIENT_OFFSET:-100000}
DEFAULT_MAX_ANCIENT_STORAGES=${DEFAULT_MAX_ANCIENT_STORAGES:-100000}
RPC_TIMEOUT=${RPC_TIMEOUT:-10}

fail() {
    echo "[ERROR] $*" >&2
    exit 1
}

warn() {
    echo "[WARN] $*" >&2
}

is_uint() {
    [[ ${1:-} =~ ^[0-9]+$ ]]
}

is_int() {
    [[ ${1:-} =~ ^-?[0-9]+$ ]]
}

format_bytes() {
    local bytes=${1:-0}
    if command -v numfmt >/dev/null 2>&1; then
        numfmt --to=iec-i --suffix=B "$bytes"
    else
        awk -v bytes="$bytes" 'BEGIN {printf "%.2fGiB", bytes / 1024 / 1024 / 1024}'
    fi
}

find_validator_pid() {
    local pid
    pid=$(systemctl show "$SERVICE_NAME" -p MainPID --value 2>/dev/null || true)
    if is_uint "$pid" && ((pid > 0)) && [[ -r "/proc/$pid/cmdline" ]]; then
        echo "$pid"
        return 0
    fi

    pid=$(pgrep -xo agave-validator 2>/dev/null || true)
    if ! is_uint "$pid" || ((pid == 0)); then
        pid=$(pgrep -fo '(^|/)solana-validator( |$)' 2>/dev/null || true)
    fi
    if is_uint "$pid" && ((pid > 0)) && [[ -r "/proc/$pid/cmdline" ]]; then
        echo "$pid"
        return 0
    fi
    return 1
}

read_validator_arguments() {
    local pid=$1 index argument
    mapfile -d '' -t validator_arguments <"/proc/$pid/cmdline"

    ancient_offset=$DEFAULT_ANCIENT_OFFSET
    max_ancient_storages=$DEFAULT_MAX_ANCIENT_STORAGES
    ancient_offset_source="default"
    max_ancient_storages_source="default"

    for ((index = 0; index < ${#validator_arguments[@]}; index++)); do
        argument=${validator_arguments[$index]}
        case "$argument" in
            --accounts)
                if ((index + 1 < ${#validator_arguments[@]})); then
                    ACCOUNTS_DIR=${validator_arguments[$((index + 1))]}
                fi
                ;;
            --accounts=*)
                ACCOUNTS_DIR=${argument#*=}
                ;;
            --accounts-db-ancient-append-vecs)
                if ((index + 1 < ${#validator_arguments[@]})); then
                    ancient_offset=${validator_arguments[$((index + 1))]}
                    ancient_offset_source="command-line"
                fi
                ;;
            --accounts-db-ancient-append-vecs=*)
                ancient_offset=${argument#*=}
                ancient_offset_source="command-line"
                ;;
            --accounts-db-max-ancient-storages)
                if ((index + 1 < ${#validator_arguments[@]})); then
                    max_ancient_storages=${validator_arguments[$((index + 1))]}
                    max_ancient_storages_source="command-line"
                fi
                ;;
            --accounts-db-max-ancient-storages=*)
                max_ancient_storages=${argument#*=}
                max_ancient_storages_source="command-line"
                ;;
        esac
    done

    is_int "$ancient_offset" || fail "Invalid ancient offset from validator command line: $ancient_offset"
    is_uint "$max_ancient_storages" || \
        fail "Invalid max ancient storages from validator command line: $max_ancient_storages"
}

read_epoch_info() {
    local response
    if is_uint "${CURRENT_SLOT:-}" && is_uint "${SLOTS_PER_EPOCH:-}" && \
        ((SLOTS_PER_EPOCH > 0)); then
        current_slot=$CURRENT_SLOT
        slots_per_epoch=$SLOTS_PER_EPOCH
        epoch=${EPOCH:-unknown}
        return 0
    fi

    command -v curl >/dev/null 2>&1 || fail "curl is required"
    command -v jq >/dev/null 2>&1 || fail "jq is required"

    response=$(curl -fsS --max-time "$RPC_TIMEOUT" -X POST "$RPC_URL" \
        -H 'Content-Type: application/json' \
        -d '{"jsonrpc":"2.0","id":1,"method":"getEpochInfo","params":[{"commitment":"finalized"}]}' \
        2>/dev/null) || fail "Unable to query getEpochInfo from $RPC_URL"

    current_slot=$(jq -er '.result.absoluteSlot | numbers' <<<"$response" 2>/dev/null) || \
        fail "getEpochInfo did not return result.absoluteSlot"
    slots_per_epoch=$(jq -er '.result.slotsInEpoch | numbers' <<<"$response" 2>/dev/null) || \
        fail "getEpochInfo did not return result.slotsInEpoch"
    epoch=$(jq -er '.result.epoch | numbers' <<<"$response" 2>/dev/null) || epoch="unknown"

    is_uint "$current_slot" || fail "Invalid current slot: $current_slot"
    is_uint "$slots_per_epoch" || fail "Invalid slots-per-epoch: $slots_per_epoch"
    ((slots_per_epoch > 0)) || fail "slots-per-epoch must be greater than zero"
}

read_du_bytes() {
    local options=$1 path=$2 result
    # shellcheck disable=SC2086
    result=$(du -x -s -B1 $options -- "$path" 2>/dev/null | awk 'NR == 1 {print $1}') || return 1
    is_uint "$result" || return 1
    echo "$result"
}

validator_pid=${VALIDATOR_PID:-}
if ! is_uint "$validator_pid" || ((validator_pid == 0)) || [[ ! -r "/proc/$validator_pid/cmdline" ]]; then
    validator_pid=$(find_validator_pid) || fail "$SERVICE_NAME.service validator process is not running"
fi
read_validator_arguments "$validator_pid"
read_epoch_info

accounts_run_dir="$ACCOUNTS_DIR/run"
[[ -d "$ACCOUNTS_DIR" ]] || fail "Accounts directory does not exist: $ACCOUNTS_DIR"
[[ -d "$accounts_run_dir" ]] || fail "Accounts run directory does not exist: $accounts_run_dir"

# Mirrors get_oldest_non_ancient_slot_from_slot():
# max_root + offset - (slots_per_epoch - 1), with saturation at zero.
cutoff=$((current_slot + ancient_offset - slots_per_epoch + 1))
((cutoff < 0)) && cutoff=0
((cutoff > current_slot)) && cutoff=$current_slot
modern_window_slots=$((current_slot - cutoff + 1))

echo "============================================================"
echo "Solana AccountsDB Storage Report"
echo "Time: $(date --iso-8601=seconds 2>/dev/null || date)"
echo "============================================================"
echo "SERVICE=$SERVICE_NAME PID=$validator_pid RPC_URL=$RPC_URL"
echo "ACCOUNTS_DIR=$ACCOUNTS_DIR"
echo "EPOCH=$epoch CURRENT_SLOT=$current_slot SLOTS_PER_EPOCH=$slots_per_epoch"
echo "ANCIENT_OFFSET=$ancient_offset SOURCE=$ancient_offset_source MODERN_WINDOW_SLOTS=$modern_window_slots CUTOFF=$cutoff"
echo "MAX_ANCIENT_STORAGES=$max_ancient_storages SOURCE=$max_ancient_storages_source"
echo

read -r filesystem total_bytes used_bytes available_bytes use_percent mountpoint < <(
    df -B1 --output=source,size,used,avail,pcent,target -- "$ACCOUNTS_DIR" | awk 'NR == 2 {print $1, $2, $3, $4, $5, $6}'
)
echo "FILESYSTEM"
echo "  source=$filesystem mount=$mountpoint total_bytes=$total_bytes used_bytes=$used_bytes available_bytes=$available_bytes use=$use_percent"
echo "  total=$(format_bytes "$total_bytes") used=$(format_bytes "$used_bytes") available=$(format_bytes "$available_bytes")"
echo

echo "Scanning $ACCOUNTS_DIR with du..."
du_start=$(date +%s)
accounts_physical_bytes=$(read_du_bytes "" "$ACCOUNTS_DIR") || fail "Unable to read physical directory size"
accounts_apparent_bytes=$(read_du_bytes "--apparent-size" "$ACCOUNTS_DIR") || \
    fail "Unable to read apparent directory size"
du_seconds=$(($(date +%s) - du_start))
echo "ACCOUNTS_DU physical_bytes=$accounts_physical_bytes apparent_bytes=$accounts_apparent_bytes scan_seconds=$du_seconds"
echo "  physical=$(format_bytes "$accounts_physical_bytes") apparent=$(format_bytes "$accounts_apparent_bytes")"
echo

echo "Scanning $accounts_run_dir and classifying storage files..."
find_start=$(date +%s)
summary=$(
    find "$accounts_run_dir" -xdev -maxdepth 1 -type f -printf '%f\t%s\t%b\n' 2>/dev/null |
        awk -F '\t' -v cutoff="$cutoff" '
        {
            split($1, name_parts, ".")
            slot_text = name_parts[1]
            logical = $2 + 0
            physical = ($3 + 0) * 512

            total_files++
            total_logical += logical
            total_physical += physical

            if (slot_text !~ /^[0-9]+$/) {
                unknown_files++
                unknown_logical += logical
                unknown_physical += physical
            } else if ((slot_text + 0) < cutoff) {
                ancient_files++
                ancient_logical += logical
                ancient_physical += physical
            } else {
                modern_files++
                modern_logical += logical
                modern_physical += physical
            }
        }
        END {
            printf "total_files=%d\n", total_files
            printf "total_logical_bytes=%.0f\n", total_logical
            printf "total_physical_bytes=%.0f\n", total_physical
            printf "ancient_files=%d\n", ancient_files
            printf "ancient_logical_bytes=%.0f\n", ancient_logical
            printf "ancient_physical_bytes=%.0f\n", ancient_physical
            printf "modern_files=%d\n", modern_files
            printf "modern_logical_bytes=%.0f\n", modern_logical
            printf "modern_physical_bytes=%.0f\n", modern_physical
            printf "unknown_files=%d\n", unknown_files
            printf "unknown_logical_bytes=%.0f\n", unknown_logical
            printf "unknown_physical_bytes=%.0f\n", unknown_physical
        }'
)
find_seconds=$(($(date +%s) - find_start))

while IFS='=' read -r key value; do
    [[ -n "$key" ]] || continue
    printf -v "$key" '%s' "$value"
done <<<"$summary"

echo "ACCOUNTS_RUN_TOTAL files=$total_files physical_bytes=$total_physical_bytes logical_bytes=$total_logical_bytes"
echo "  physical=$(format_bytes "$total_physical_bytes") logical=$(format_bytes "$total_logical_bytes")"
echo "ACCOUNTS_RUN_ANCIENT_ELIGIBLE cutoff=$cutoff files=$ancient_files physical_bytes=$ancient_physical_bytes logical_bytes=$ancient_logical_bytes"
echo "  physical=$(format_bytes "$ancient_physical_bytes") logical=$(format_bytes "$ancient_logical_bytes")"
echo "ACCOUNTS_RUN_MODERN cutoff=$cutoff files=$modern_files physical_bytes=$modern_physical_bytes logical_bytes=$modern_logical_bytes"
echo "  physical=$(format_bytes "$modern_physical_bytes") logical=$(format_bytes "$modern_logical_bytes")"

if ((unknown_files > 0)); then
    echo "ACCOUNTS_RUN_UNCLASSIFIED files=$unknown_files physical_bytes=$unknown_physical_bytes logical_bytes=$unknown_logical_bytes"
    warn "$unknown_files account storage file(s) did not begin with a numeric slot"
fi

echo "ACCOUNTS_RUN_SCAN seconds=$find_seconds"
echo
echo "Notes:"
echo "  - ANCIENT_ELIGIBLE means the storage slot is older than the ancient boundary."
echo "  - It does not mean all of those bytes are dead or immediately reclaimable."
echo "  - physical_bytes uses allocated 512-byte filesystem blocks; logical_bytes uses file sizes."
echo "============================================================"
