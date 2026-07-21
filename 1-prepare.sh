#!/bin/bash
set -euo pipefail

# ============================================
# 步骤1: 挂载磁盘 + 创建目录 + 系统优化
# ============================================

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LANG_CACHE_FILE="$SCRIPT_DIR/solana-rpc-lang"
# shellcheck source=lang.sh
source "$SCRIPT_DIR/lang.sh"

BASE=${BASE:-/root/sol}
LEDGER="$BASE/ledger"
ACCOUNTS="$BASE/accounts"
ACCOUNTS_INDEX="$BASE/accounts_index"
SNAPSHOT="$BASE/snapshot"
BIN="$BASE/bin"
TOOLS="$BASE/tools"

if [[ $EUID -ne 0 ]]; then
  echo "[ERROR] Please run as root: sudo bash $0" >&2
  exit 1
fi

prompt_lang

if [[ "$LANG_SCRIPT" == "zh" ]]; then
  M_HEADER="步骤 1: 环境准备"
  M_STEP1="创建目录 ..."
  M_DIRS_OK="目录已创建"
  M_STEP2="自动检测磁盘并安全挂载（优先 accounts）..."
  M_SYS_DISKS="检测到系统盘："
  M_NO_SYS_DISK="未能检测到系统盘"
  M_MOUNTED_OK="已正确挂载：%s -> %s，跳过"
  M_MOUNT_WRONG="检测到 %s 挂载在错误位置：%s"
  M_UMOUNT="卸载 %s ..."
  M_UMOUNT_FAIL="无法卸载 %s，可能正在使用。请手动检查并卸载后重新运行脚本"
  M_FSTAB_CLEAN="清理 fstab 中的旧挂载配置：%s"
  M_FS_DETECTED="检测到现有文件系统：%s，保留"
  M_FS_UNKNOWN="检测到文件系统但类型未知，使用 auto"
  M_MKFS="为 %s 创建 ext4 文件系统（首次使用）"
  M_MOUNT_FAIL="挂载失败：%s -> %s"
  M_MOUNT_DONE="挂载完成：%s -> %s (%s)"
  M_STEP21="收集可用数据盘..."
  M_SKIP_SYS="跳过系统盘：%s"
  M_SKIP_SYS_MOUNT="跳过系统盘：%s (系统挂载：%s)"
  M_AVAIL_DISK="可用数据盘：%s (整盘, %sGB)"
  M_SCAN_PARTS="扫描磁盘分区：%s"
  M_SKIP_PART="跳过系统分区：%s -> %s"
  M_SKIP_INVALID="跳过无效分区：%s (无法读取大小)"
  M_FOUND_PART="发现非系统分区：%s (%sGB)"
  M_AVAIL_BEST="可用数据盘：%s (最大非系统分区, %sGB)"
  M_ALL_SYS="跳过 %s：所有分区均为系统分区"
  M_NO_DATA_DISK="未检测到可用数据盘，所有目录将使用系统盘"
  M_N_DISKS="检测到 %s 个可用数据盘"
  M_STEP22="检查当前挂载状态..."
  M_CURRENT="当前状态："
  M_STEP23="检测挂载优先级..."
  M_PRIO_ERR="检测到优先级错误："
  M_PRIO_ACC="Accounts 应该优先获得数据盘（性能需求最高）"
  M_PRIO_LOW="当前 Accounts 在系统盘上，而低优先级目录占用了数据盘"
  M_FIX_PRIO="自动修复优先级..."
  M_UMOUNT_DIR="卸载：%s"
  M_UMOUNT_DIR_FAIL="无法卸载 %s，可能有进程正在使用"
  M_STOP_SVC="请先停止相关服务后重新运行脚本"
  M_FSTAB_OLD="清理 /etc/fstab 旧配置"
  M_PRIO_CLEANED="优先级错误已清理，准备重新挂载"
  M_STEP24="按优先级挂载数据盘..."
  M_PRIO_ORDER="优先级：Accounts (最高) > Ledger (中等) > Snapshot (最低)"
  M_MOUNT_ACC_FAIL="挂载 accounts 失败"
  M_ACC_SYS="Accounts: 使用系统盘（无可用数据盘）"
  M_MOUNT_LED_FAIL="挂载 ledger 失败"
  M_LED_SYS="Ledger: 使用系统盘"
  M_MOUNT_SNAP_FAIL="挂载 snapshot 失败"
  M_SNAP_SYS="Snapshot: 使用系统盘"
  M_STEP3="系统优化（极限网络性能）..."
  M_NO_OPT_SCRIPT="找不到 system-optimize.sh，跳过系统优化"
  M_DONE_HEADER="步骤 1 完成!"
  M_DONE_1="目录结构创建"
  M_DONE_2="数据盘挂载（如有）"
  M_DONE_3="系统参数优化"
  M_DONE_LABEL="已完成:"
  M_NEXT="下一步: bash 2-install-jito-validator.sh"
else
  M_HEADER="Step 1: Environment preparation"
  M_STEP1="Create directories..."
  M_DIRS_OK="Directories created"
  M_STEP2="Auto-detect disks and mount (priority: accounts)..."
  M_SYS_DISKS="System disks detected:"
  M_NO_SYS_DISK="No system disk detected"
  M_MOUNTED_OK="Already mounted: %s -> %s, skip"
  M_MOUNT_WRONG="Detected %s mounted at wrong place: %s"
  M_UMOUNT="Unmounting %s ..."
  M_UMOUNT_FAIL="Cannot unmount %s, may be in use. Unmount manually and re-run"
  M_FSTAB_CLEAN="Cleaning old fstab entry: %s"
  M_FS_DETECTED="Existing filesystem detected: %s, keeping"
  M_FS_UNKNOWN="Filesystem type unknown, using auto"
  M_MKFS="Creating ext4 on %s (first use)"
  M_MOUNT_FAIL="Mount failed: %s -> %s"
  M_MOUNT_DONE="Mounted: %s -> %s (%s)"
  M_STEP21="Collect available data disks..."
  M_SKIP_SYS="Skipping system disk: %s"
  M_SKIP_SYS_MOUNT="Skipping system disk: %s (mount: %s)"
  M_AVAIL_DISK="Available disk: %s (whole disk, %sGB)"
  M_SCAN_PARTS="Scanning partitions: %s"
  M_SKIP_PART="Skipping system partition: %s -> %s"
  M_SKIP_INVALID="Skipping invalid partition: %s (cannot read size)"
  M_FOUND_PART="Found non-system partition: %s (%sGB)"
  M_AVAIL_BEST="Available disk: %s (largest non-system partition, %sGB)"
  M_ALL_SYS="Skipping %s: all partitions are system"
  M_NO_DATA_DISK="No data disk found, all dirs will use system disk"
  M_N_DISKS="Found %s available data disk(s)"
  M_STEP22="Check current mount status..."
  M_CURRENT="Current status:"
  M_STEP23="Check mount priority..."
  M_PRIO_ERR="Priority issue detected:"
  M_PRIO_ACC="Accounts should get data disk first (highest performance need)"
  M_PRIO_LOW="Accounts on system disk while lower-priority dirs use data disk"
  M_FIX_PRIO="Auto-fixing priority..."
  M_UMOUNT_DIR="Unmounting: %s"
  M_UMOUNT_DIR_FAIL="Cannot unmount %s, may be in use"
  M_STOP_SVC="Stop the service first and re-run"
  M_FSTAB_OLD="Cleaning old /etc/fstab entries"
  M_PRIO_CLEANED="Priority cleaned, will re-mount"
  M_STEP24="Mount data disks by priority..."
  M_PRIO_ORDER="Priority: Accounts (highest) > Ledger > Snapshot (lowest)"
  M_MOUNT_ACC_FAIL="Mount accounts failed"
  M_ACC_SYS="Accounts: using system disk (no data disk)"
  M_MOUNT_LED_FAIL="Mount ledger failed"
  M_LED_SYS="Ledger: using system disk"
  M_MOUNT_SNAP_FAIL="Mount snapshot failed"
  M_SNAP_SYS="Snapshot: using system disk"
  M_STEP3="System tuning (network performance)..."
  M_NO_OPT_SCRIPT="system-optimize.sh not found, skipping"
  M_DONE_HEADER="Step 1 complete!"
  M_DONE_1="Directory structure created"
  M_DONE_2="Data disk mounted (if any)"
  M_DONE_3="System parameters tuned"
  M_DONE_LABEL="Done:"
  M_NEXT="Next: bash 2-install-jito-validator.sh"
fi

echo "============================================"
echo "$M_HEADER"
echo "============================================"
echo ""

echo "==> 1) $M_STEP1"
mkdir -p "$LEDGER" "$ACCOUNTS" "$ACCOUNTS_INDEX" "$SNAPSHOT" "$BIN" "$TOOLS"
echo "   ✓ $M_DIRS_OK"

# ---------- Auto-detect and mount (priority: accounts -> ledger -> snapshot) ----------
echo ""
echo "==> 2) $M_STEP2"

# 收集所有系统盘（包含 /, /boot, /boot/efi 的磁盘）
SYSTEM_DISKS=()

# 检测根分区所在磁盘
for mount_point in "/" "/boot" "/boot/efi"; do
  src=$(findmnt -no SOURCE "$mount_point" 2>/dev/null || true)
  if [[ -n "$src" ]]; then
    # 获取磁盘名（可能是 /dev/nvme0n1p2, /dev/mapper/vg0-root 等）
    disk=$(lsblk -no pkname "$src" 2>/dev/null | head -1 || true)
    if [[ -n "$disk" ]]; then
      SYSTEM_DISKS+=("/dev/$disk")
    fi
  fi
done

# 去重
SYSTEM_DISKS=($(printf '%s\n' "${SYSTEM_DISKS[@]}" | sort -u))

if ((${#SYSTEM_DISKS[@]} > 0)); then
  echo "   $M_SYS_DISKS"
  for disk in "${SYSTEM_DISKS[@]}"; do
    echo "     - $disk"
  done
else
  echo "   ⚠️  $M_NO_SYS_DISK"
fi

MAP_DISKS=($(lsblk -dn -o NAME,TYPE | awk '$2=="disk"{print $1}'))

is_mounted_dev() { findmnt -no TARGET "$1" &>/dev/null; }
has_fs() { blkid -o value -s TYPE "$1" &>/dev/null; }

mount_one() {
  local dev="$1"; local target="$2"

  # Check if device is already mounted
  if is_mounted_dev "$dev"; then
    local current_mount=$(findmnt -no TARGET "$dev")
    if [[ "$current_mount" == "$target" ]]; then
      printf "   - $M_MOUNTED_OK\n" "$dev" "$target"
      return 0
    fi
    printf "   - $M_MOUNT_WRONG\n" "$dev" "$current_mount"
    printf "   - $M_UMOUNT\n" "$dev"
    umount "$dev" || {
      printf "   ⚠️  $M_UMOUNT_FAIL\n" "$dev"
      return 1
    }
    if grep -q "$current_mount" /etc/fstab 2>/dev/null; then
      printf "   - $M_FSTAB_CLEAN\n" "$current_mount"
      sed -i "\|$current_mount|d" /etc/fstab
    fi
  fi

  local fs_type=""
  if has_fs "$dev"; then
    fs_type=$(blkid -o value -s TYPE "$dev" 2>/dev/null || echo "")
    if [[ -n "$fs_type" ]]; then
      printf "   - $M_FS_DETECTED\n" "$fs_type"
    else
      fs_type="auto"
      echo "   - $M_FS_UNKNOWN"
    fi
  else
    printf "   - $M_MKFS\n" "$dev"
    mkfs.ext4 -F "$dev" >/dev/null 2>&1
    fs_type="ext4"
  fi

  mkdir -p "$target"
  mount "$dev" "$target" || {
    printf "   ⚠️  $M_MOUNT_FAIL\n" "$dev" "$target"
    return 1
  }

  sed -i "\|^${dev} |d" /etc/fstab 2>/dev/null || true
  sed -i "\|^[^ ]* ${target} |d" /etc/fstab 2>/dev/null || true

  echo "$dev $target $fs_type defaults 0 0" >> /etc/fstab

  printf "   - ✅ $M_MOUNT_DONE\n" "$dev" "$target" "$fs_type"
}

# ---------- Step 2.1: Collect available data disks ----------
echo "==> 2.1) $M_STEP21"

# 辅助函数：严格检查是否为系统关键分区
is_system_partition() {
  local dev="$1"

  # 未挂载的分区不是系统分区
  if ! findmnt -no TARGET "$dev" &>/dev/null; then
    return 1
  fi

  local mount_point=$(findmnt -no TARGET "$dev" 2>/dev/null || echo "")

  # 严格匹配系统关键路径
  case "$mount_point" in
    "/"|\
    "/boot"|\
    "/boot/"*|\
    "/boot/efi"|\
    "/efi"|\
    "/efi/"*|\
    *"/swap"*|\
    "[SWAP]")
      return 0  # 是系统分区
      ;;
    *)
      return 1  # 不是系统分区
      ;;
  esac
}

AVAILABLE_DISKS=()
for d in "${MAP_DISKS[@]}"; do
  disk="/dev/$d"

  # Skip system disks
  is_sys_disk=false
  for sys_disk in "${SYSTEM_DISKS[@]}"; do
    if [[ "$disk" == "$sys_disk" ]]; then
      printf "   - $M_SKIP_SYS\n" "$disk"
      is_sys_disk=true
      break
    fi
  done
  [[ "$is_sys_disk" == true ]] && continue

  parts=($(lsblk -n -o NAME,TYPE "$disk" | awk '$2=="part"{gsub(/^[├─└│ ]*/, "", $1); print $1}'))

  if ((${#parts[@]}==0)); then
    if is_system_partition "$disk"; then
      printf "   - $M_SKIP_SYS_MOUNT\n" "$disk" "$(findmnt -no TARGET "$disk" 2>/dev/null)"
      continue
    fi

    size=$(lsblk -bno SIZE "$disk" 2>/dev/null | head -1 | tr -d '[:space:]')
    size_gb=$((size / 1024 / 1024 / 1024))
    AVAILABLE_DISKS+=("$disk")
    printf "   - $M_AVAIL_DISK\n" "$disk" "$size_gb"
  else
    printf "   - $M_SCAN_PARTS\n" "$disk"
    best=""; best_size=0

    for p in "${parts[@]}"; do
      part="/dev/$p"

      if is_system_partition "$part"; then
        mnt=$(findmnt -no TARGET "$part" 2>/dev/null || echo "-")
        printf "     ✗ $M_SKIP_PART\n" "$part" "$mnt"
        continue
      fi

      size=$(lsblk -bno SIZE "$part" 2>/dev/null | head -1 | tr -d '[:space:]')

      if [[ -z "$size" ]] || [[ ! "$size" =~ ^[0-9]+$ ]]; then
        printf "     ✗ $M_SKIP_INVALID\n" "$part"
        continue
      fi

      size_gb=$((size / 1024 / 1024 / 1024))
      printf "     ✓ $M_FOUND_PART\n" "$part" "$size_gb"

      # 选择最大的分区
      if (( size > best_size )); then
        best="$part"
        best_size=$size
      fi
    done

    if [[ -n "$best" ]]; then
      best_size_gb=$((best_size / 1024 / 1024 / 1024))
      AVAILABLE_DISKS+=("$best")
      printf "   - $M_AVAIL_BEST\n" "$best" "$best_size_gb"
    else
      printf "   - $M_ALL_SYS\n" "$disk"
    fi
  fi
done

if ((${#AVAILABLE_DISKS[@]}==0)); then
    echo "   ⚠️  $M_NO_DATA_DISK"
else
    echo ""
    printf "   $M_N_DISKS\n" "${#AVAILABLE_DISKS[@]}"
fi

echo ""
echo "==> 2.2) $M_STEP22"
CURRENT_ACC_MOUNT=$(df -P "$ACCOUNTS" 2>/dev/null | tail -1 | awk '{print $6}')
CURRENT_LED_MOUNT=$(df -P "$LEDGER" 2>/dev/null | tail -1 | awk '{print $6}')
CURRENT_SNAP_MOUNT=$(df -P "$SNAPSHOT" 2>/dev/null | tail -1 | awk '{print $6}')

CURRENT_ACC_DEV=$(df -P "$ACCOUNTS" 2>/dev/null | tail -1 | awk '{print $1}')
CURRENT_LED_DEV=$(df -P "$LEDGER" 2>/dev/null | tail -1 | awk '{print $1}')
CURRENT_SNAP_DEV=$(df -P "$SNAPSHOT" 2>/dev/null | tail -1 | awk '{print $1}')

echo "   $M_CURRENT"
echo "   - Accounts: ${CURRENT_ACC_DEV} -> ${CURRENT_ACC_MOUNT}"
echo "   - Ledger:   ${CURRENT_LED_DEV} -> ${CURRENT_LED_MOUNT}"
echo "   - Snapshot: ${CURRENT_SNAP_DEV} -> ${CURRENT_SNAP_MOUNT}"

# ---------- Step 2.3: Detect and fix priority ----------
echo ""
echo "==> 2.3) $M_STEP23"
NEED_FIX=false

if [[ "$CURRENT_ACC_MOUNT" != "$ACCOUNTS" ]]; then
    if [[ "$CURRENT_LED_MOUNT" == "$LEDGER" ]] || [[ "$CURRENT_SNAP_MOUNT" == "$SNAPSHOT" ]]; then
        echo "   ⚠️  $M_PRIO_ERR"
        echo "   - $M_PRIO_ACC"
        echo "   - $M_PRIO_LOW"
        NEED_FIX=true
    fi
fi

if $NEED_FIX && ((${#AVAILABLE_DISKS[@]}>0)); then
    echo ""
    echo "   🔧 $M_FIX_PRIO"

    for dir in "$SNAPSHOT" "$LEDGER" "$ACCOUNTS"; do
        if mountpoint -q "$dir" 2>/dev/null; then
            printf "   - $M_UMOUNT_DIR\n" "$dir"
            umount "$dir" || {
                printf "   ⚠️  $M_UMOUNT_DIR_FAIL\n" "$dir"
                echo "   $M_STOP_SVC"
                exit 1
            }
        fi
    done

    echo "   - $M_FSTAB_OLD"
    sed -i "\|$ACCOUNTS|d" /etc/fstab 2>/dev/null || true
    sed -i "\|$LEDGER|d" /etc/fstab 2>/dev/null || true
    sed -i "\|$SNAPSHOT|d" /etc/fstab 2>/dev/null || true

    echo "   ✓ $M_PRIO_CLEANED"
    echo ""
fi

# ---------- Step 2.4: Mount by priority ----------
echo "==> 2.4) $M_STEP24"
echo "   $M_PRIO_ORDER"
echo ""

if ((${#AVAILABLE_DISKS[@]} >= 1)); then
    mount_one "${AVAILABLE_DISKS[0]}" "$ACCOUNTS" || echo "   ⚠️  $M_MOUNT_ACC_FAIL"
else
    echo "   - $M_ACC_SYS"
fi

if ((${#AVAILABLE_DISKS[@]} >= 2)); then
    mount_one "${AVAILABLE_DISKS[1]}" "$LEDGER" || echo "   ⚠️  $M_MOUNT_LED_FAIL"
else
    echo "   - $M_LED_SYS"
fi

if ((${#AVAILABLE_DISKS[@]} >= 3)); then
    mount_one "${AVAILABLE_DISKS[2]}" "$SNAPSHOT" || echo "   ⚠️  $M_MOUNT_SNAP_FAIL"
else
    echo "   - $M_SNAP_SYS"
fi

echo ""
echo "==> 3) $M_STEP3"
if [[ -f "$SCRIPT_DIR/system-optimize.sh" ]]; then
  bash "$SCRIPT_DIR/system-optimize.sh"
else
  echo "   ⚠️  $M_NO_OPT_SCRIPT"
fi

echo ""
echo "============================================"
echo "✅ $M_DONE_HEADER"
echo "============================================"
echo ""
echo "$M_DONE_LABEL"
echo "  - $M_DONE_1"
echo "  - $M_DONE_2"
echo "  - $M_DONE_3"
echo ""
echo "$M_NEXT"
echo ""
