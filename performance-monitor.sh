#!/bin/bash
set -euo pipefail

# ============================================
# Solana RPC Node Performance Monitor
# ============================================
# Real-time monitoring and alerting for:
# - Memory usage and pressure
# - CPU utilization and throttling
# - Network bandwidth and latency
# - Disk I/O performance
# - Validator health metrics
# ============================================

LOGFILE="/var/log/solana-performance.log"
ALERT_THRESHOLD_CPU=80
ALERT_THRESHOLD_MEM=85
ALERT_THRESHOLD_DISK=80
ALERT_THRESHOLD_INODE=80
CHECK_INTERVAL=30  # seconds

# Check each filesystem separately. /root/sol is usually the root filesystem,
# while accounts/ledger/snapshot may be independent mounts.
DISK_PATHS=(/root/sol /root/sol/accounts /root/sol/ledger /root/sol/snapshot)

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGFILE"
}

log_metric() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] METRIC: $*" >> "$LOGFILE"
}

alert() {
    echo -e "${RED}[ALERT]${NC} $*" | tee -a "$LOGFILE"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" | tee -a "$LOGFILE"
}

info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

# Check if validator is running (Jito/Agave: agave-validator or solana-validator)
check_validator_running() {
    if pgrep -x agave-validator >/dev/null; then
        VALIDATOR_PID=$(pgrep -x agave-validator)
        return 0
    elif pgrep -x solana-validator >/dev/null; then
        VALIDATOR_PID=$(pgrep -x solana-validator)
        return 0
    else
        alert "Validator is NOT running!"
        return 1
    fi
}

# CPU metrics
check_cpu() {
    local cpu_usage=$(top -bn2 -d 0.5 | grep "Cpu(s)" | tail -n1 | awk '{print $2}' | cut -d'%' -f1)
    local cpu_int=${cpu_usage%.*}

    log_metric "CPU_USAGE=${cpu_usage}%"

    if [[ $cpu_int -gt $ALERT_THRESHOLD_CPU ]]; then
        alert "High CPU usage: ${cpu_usage}%"
    fi

    if check_validator_running; then
        local validator_cpu=$(ps -p $VALIDATOR_PID -o %cpu= 2>/dev/null || echo "0")
        log_metric "VALIDATOR_CPU=${validator_cpu}%"
        echo -e "${BLUE}CPU:${NC} System=${cpu_usage}% Validator=${validator_cpu}%"
    fi
}

# Memory metrics
check_memory() {
    local mem_total=$(free -m | awk 'NR==2{print $2}')
    local mem_used=$(free -m | awk 'NR==2{print $3}')
    local mem_available=$(free -m | awk 'NR==2{print $7}')
    local mem_percent=$((mem_used * 100 / mem_total))

    log_metric "MEM_TOTAL=${mem_total}MB MEM_USED=${mem_used}MB MEM_AVAIL=${mem_available}MB MEM_PERCENT=${mem_percent}%"

    if [[ $mem_percent -gt $ALERT_THRESHOLD_MEM ]]; then
        alert "High memory usage: ${mem_percent}%"
    fi

    if check_validator_running; then
        local validator_mem=$(ps -p $VALIDATOR_PID -o rss= 2>/dev/null | awk '{printf "%.2f", $1/1024/1024}')
        local validator_threads=$(ps -p $VALIDATOR_PID -o nlwp= 2>/dev/null || echo "0")
        log_metric "VALIDATOR_MEM=${validator_mem}GB VALIDATOR_THREADS=${validator_threads}"
        echo -e "${BLUE}Memory:${NC} System=${mem_percent}% (${mem_used}/${mem_total}MB) Validator=${validator_mem}GB Threads=${validator_threads}"
    fi
}

# Disk I/O metrics
check_disk() {
    local path disk_line inode_line filesystem blocks used avail usage mount
    local inode_total inode_used inode_avail inode_usage

    for path in "${DISK_PATHS[@]}"; do
        disk_line=$(df -P -B1 "$path" 2>/dev/null | awk 'NR==2{print}')
        inode_line=$(df -Pi "$path" 2>/dev/null | awk 'NR==2{print}')

        if [[ -z "$disk_line" || -z "$inode_line" ]]; then
            alert "Unable to read filesystem usage for $path"
            continue
        fi

        read -r filesystem blocks used avail usage mount <<< "$disk_line"
        read -r _ inode_total inode_used inode_avail inode_usage _ <<< "$inode_line"
        usage=${usage%\%}
        inode_usage=${inode_usage%\%}

        log_metric "DISK_USAGE path=$path filesystem=$filesystem bytes_total=${blocks} bytes_used=${used} bytes_avail=${avail} percent=${usage}%"
        log_metric "INODE_USAGE path=$path files_used=${inode_used} files_avail=${inode_avail} percent=${inode_usage}%"

        if [[ "$usage" =~ ^[0-9]+$ && "$usage" -ge "$ALERT_THRESHOLD_DISK" ]]; then
            alert "High disk usage on $path: ${usage}% (available=${avail} bytes)"
        fi
        if [[ "$inode_usage" =~ ^[0-9]+$ && "$inode_usage" -ge "$ALERT_THRESHOLD_INODE" ]]; then
            alert "High inode usage on $path: ${inode_usage}% (available=${inode_avail})"
        fi

        echo -e "${BLUE}Disk:${NC} $path Usage=${usage}% Inodes=${inode_usage}% Avail=${avail}"
    done

    # I/O stats
    if command -v iostat >/dev/null 2>&1; then
        local io_stats
        while IFS= read -r io_stats; do
            [[ -n "$io_stats" ]] && log_metric "DISK_IO: $io_stats"
        done < <(iostat -x 1 2 | awk '/^Device/{report++; next} report==2 && $1 ~ /^(nvme|sd)/ {print}')
    fi

}

# Network metrics
check_network() {
    local net_iface=$(ip route | grep default | awk '{print $5}' | head -n1)

    if [[ -n "$net_iface" ]]; then
        local rx_before=$(cat /sys/class/net/$net_iface/statistics/rx_bytes)
        local tx_before=$(cat /sys/class/net/$net_iface/statistics/tx_bytes)
        sleep 1
        local rx_after=$(cat /sys/class/net/$net_iface/statistics/rx_bytes)
        local tx_after=$(cat /sys/class/net/$net_iface/statistics/tx_bytes)

        local rx_rate=$(( (rx_after - rx_before) / 1024 / 1024 ))
        local tx_rate=$(( (tx_after - tx_before) / 1024 / 1024 ))

        log_metric "NET_RX=${rx_rate}MB/s NET_TX=${tx_rate}MB/s"
        echo -e "${BLUE}Network:${NC} RX=${rx_rate}MB/s TX=${tx_rate}MB/s"
    fi

    # Connection count
    local conn_count=$(ss -s | grep estab | awk '{print $2}')
    log_metric "NET_CONNECTIONS=${conn_count}"
}

# Validator health
check_validator_health() {
    if ! check_validator_running; then
        # The monitor must remain alive after the validator fails.
        return 0
    fi

    # Check slot height
    local slot_height=$(solana slot 2>/dev/null || echo "ERROR")
    log_metric "SLOT_HEIGHT=${slot_height}"

    # Check catchup status
    local catchup=$(solana catchup --our-localhost 2>/dev/null | grep "Slot" || echo "Unknown")
    log_metric "CATCHUP=${catchup}"

    # Check health
    local health=$(curl -s -X POST http://localhost:8899 -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","id":1,"method":"getHealth"}' | grep -o '"result":"[^"]*"' || echo "Unknown")
    log_metric "HEALTH=${health}"

    echo -e "${BLUE}Validator:${NC} Slot=${slot_height} Health=${health}"

    # File descriptor usage
    local fd_count=$(ls /proc/$VALIDATOR_PID/fd 2>/dev/null | wc -l)
    local fd_limit=$(ulimit -n)
    local fd_percent=$((fd_count * 100 / fd_limit))
    log_metric "FD_USAGE=${fd_count}/${fd_limit} (${fd_percent}%)"

    if [[ $fd_percent -gt 80 ]]; then
        warn "High file descriptor usage: ${fd_percent}%"
    fi
}

# System performance issues
check_performance_issues() {
    # Check for OOM kills
    if dmesg -T | tail -n 100 | grep -qi "out of memory"; then
        alert "OOM killer detected in recent logs!"
    fi

    # Check for CPU throttling
    if dmesg -T | tail -n 100 | grep -qi "cpu.*throttl"; then
        warn "CPU throttling detected!"
    fi

    # Check load average
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',')
    local cpu_cores=$(nproc)
    local load_normalized=$(echo "$load_avg / $cpu_cores" | bc -l | awk '{printf "%.2f", $1}')

    log_metric "LOAD_AVG=${load_avg} LOAD_NORMALIZED=${load_normalized}"

    if (( $(echo "$load_normalized > 0.8" | bc -l) )); then
        warn "High normalized load average: ${load_normalized}"
    fi
}

# Performance snapshot
performance_snapshot() {
    echo "========================================="
    echo "Solana Performance Monitor"
    echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "========================================="

    check_cpu
    check_memory
    check_disk
    check_network
    check_validator_health
    check_performance_issues

    echo "========================================="
}

# Continuous monitoring mode
continuous_monitor() {
    log "Starting continuous performance monitoring (interval: ${CHECK_INTERVAL}s)"

    while true; do
        performance_snapshot
        sleep $CHECK_INTERVAL
    done
}

# Main
case "${1:-snapshot}" in
    snapshot)
        performance_snapshot
        ;;
    monitor)
        continuous_monitor
        ;;
    *)
        echo "Usage: $0 {snapshot|monitor}"
        echo "  snapshot - Single performance check"
        echo "  monitor  - Continuous monitoring"
        exit 1
        ;;
esac
