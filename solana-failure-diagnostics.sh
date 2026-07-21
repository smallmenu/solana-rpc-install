#!/bin/bash
set -u

SERVICE_RESULT_VALUE=${SERVICE_RESULT:-unknown}
EXIT_CODE_VALUE=${EXIT_CODE:-unknown}
EXIT_STATUS_VALUE=${EXIT_STATUS:-unknown}

# ExecStopPost also runs after an intentional systemctl stop.
if [[ "$SERVICE_RESULT_VALUE" == "success" ]]; then
    exit 0
fi

LOG_DIR=/var/log
TIMESTAMP=$(date -u '+%Y%m%dT%H%M%SZ')
LOG_FILE="$LOG_DIR/solana-failure-$TIMESTAMP.log"
umask 077

exec >> "$LOG_FILE" 2>&1

echo "Solana validator failure diagnostics"
echo "timestamp_utc=$(date -u --iso-8601=seconds)"
echo "service_result=$SERVICE_RESULT_VALUE"
echo "exit_code=$EXIT_CODE_VALUE"
echo "exit_status=$EXIT_STATUS_VALUE"
echo

echo "== Filesystem capacity =="
df -P -B1 / /root/sol /root/sol/accounts /root/sol/accounts_index /root/sol/ledger /root/sol/snapshot || true
echo

echo "== Filesystem inodes =="
df -Pi / /root/sol /root/sol/accounts /root/sol/accounts_index /root/sol/ledger /root/sol/snapshot || true
echo

echo "== Mounts =="
for path in /root/sol /root/sol/accounts /root/sol/accounts_index /root/sol/ledger /root/sol/snapshot; do
    findmnt -T "$path" -o TARGET,SOURCE,FSTYPE,OPTIONS || true
done
echo

echo "== Filesystem metadata =="
for path in /root/sol /root/sol/accounts /root/sol/accounts_index /root/sol/ledger /root/sol/snapshot; do
    stat -f -c 'path=%n type=%T blocks=%b free=%f avail=%a block_size=%S files=%c files_free=%d' "$path" || true
done
echo

echo "== Block devices =="
lsblk -o NAME,TYPE,SIZE,FSTYPE,FSAVAIL,FSUSE%,MOUNTPOINTS || true
echo

echo "== Quota =="
quota -vs root 2>&1 || true
if [[ "$(findmnt -n -o FSTYPE -T /root/sol/accounts 2>/dev/null)" == "xfs" ]] && command -v xfs_quota >/dev/null 2>&1; then
    xfs_quota -x -c 'report -h' /root/sol/accounts || true
fi
echo

echo "== Recent validator journal =="
journalctl -u sol.service -n 1000 -o short-iso-precise --no-pager || true
echo

echo "== Recent kernel journal =="
journalctl -k -n 500 -o short-iso-precise --no-pager || true
echo

echo "== Latest core dump metadata =="
coredumpctl info -1 --no-pager 2>&1 || true
