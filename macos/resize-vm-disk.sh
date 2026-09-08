#!/bin/bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: macos/resize-vm-disk.sh --size-gib N [--state-root DIR] [--apply]

Preview growing an existing, stopped VM to N GiB (whole number, at most 8192).
Add --apply to retain a verified APFS clone backup and enlarge the disk.
The root filesystem grows automatically on the next normal guest boot.

DIR is the VM state directory containing .omarchy-qemu-storage and disks/current.
Default: ~/Library/Application Support/My Omarchy/VM/v1
Custom VM locations require --state-root; saved app preferences are not read.
EOF
}

fail() {
  printf 'resize-vm-disk: %s\n' "$*" >&2
  exit 1
}

size_gib=''
state_root="${HOME:?}/Library/Application Support/My Omarchy/VM/v1"
apply=0
while (($#)); do
  case "$1" in
    --size-gib)
      (($# >= 2)) && [[ -z $size_gib ]] || { usage >&2; exit 64; }
      size_gib=$2
      shift 2
      ;;
    --state-root)
      (($# >= 2)) || { usage >&2; exit 64; }
      state_root=$2
      shift 2
      ;;
    --apply) apply=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 64 ;;
  esac
done
[[ $size_gib =~ ^[1-9][0-9]{0,3}$ ]] || fail '--size-gib must be a whole number from 1 to 8192'
(( size_gib <= 8192 )) || fail '--size-gib cannot exceed 8192'
[[ $(uname -s) == Darwin ]] || fail 'macOS is required'
(( EUID != 0 )) || fail 'run as the macOS user who owns the VM, without sudo'
command -v python3 >/dev/null || fail 'python3 is required'
[[ ${OMARCHY_QEMU_GPU_DEVELOPMENT_MULTI_DISK:-0} == 0 ]] || fail 'development multi-disk workspaces are not supported'

script_dir=$(cd "$(dirname "$0")" && pwd -P)
# shellcheck source=qemu-persistent-storage.sh
source "$script_dir/qemu-persistent-storage.sh"

# Unlike the launch path, a maintenance command must never initialize storage.
_qps_assert_safe_root_path "$state_root"
_qps_assert_private_directory "$state_root" 'existing state root'
state_root=$(cd "$state_root" && pwd -P)
_qps_assert_safe_root_path "$state_root"
_qps_assert_volume_supported "$state_root"
_qps_validate_root_marker "$state_root/.omarchy-qemu-storage"
for child in disks boot locks; do
  _qps_assert_private_directory "$state_root/$child" "state $child directory"
done
QEMU_PERSISTENT_STORAGE_LOCKS_ROOT="$state_root/locks"
_qps_assert_private_regular_file "$state_root/locks/current.lock" 'existing workspace lock'
_qps_acquire_lock current
trap 'qemu_persistent_storage_release_lock' EXIT

workspace="$state_root/disks/current"
_qps_validate_recorded_workspace "$workspace"
[[ $QPS_METADATA_SCHEMA == "$QEMU_PERSISTENT_STORAGE_SCHEMA" ]] || fail 'launch and shut down this VM with the current app before resizing'
boot_kit="$state_root/boot/$QPS_METADATA_IDENTITY"
_qps_validate_boot_kit_directory "$boot_kit" "$QPS_METADATA_IDENTITY"
disk="$workspace/rootfs.ext4"
current_bytes=$QPS_RECORDED_EXISTING_BYTES
target_bytes=$((size_gib * 1024 * 1024 * 1024))
(( target_bytes >= current_bytes )) || fail 'shrinking a VM disk is not supported'
if (( target_bytes == current_bytes )); then
  printf 'VM disk is already %s GiB; nothing changed.\n' "$size_gib"
  exit 0
fi
[[ $(/usr/bin/stat -f '%l' "$disk") == 1 ]] || fail 'root disk must not have hard links'
disk_identity=$(_qps_file_identity "$disk")
_qps_assert_free_space "$state_root" "$((target_bytes - current_bytes + QEMU_PERSISTENT_STORAGE_HEADROOM_BYTES))"
printf 'VM disk: %s\nCurrent bytes: %s\nTarget: %s GiB (%s bytes)\n' \
  "$disk" "$current_bytes" "$size_gib" "$target_bytes"
if (( ! apply )); then
  printf 'Preview only. Re-run with --apply after shutting down the VM.\nBackup will be retained beside %s.\n' "$state_root"
  exit 0
fi

umask 077
backup=$(mktemp -d "${state_root}.resize-backup.XXXXXX")
printf 'Retaining backup: %s\n' "$backup"
# Require cloning on this APFS volume; do not silently fall back to a full copy.
/bin/cp -c "$disk" "$backup/rootfs.ext4"
/bin/cp -p "$workspace/metadata.json" "$backup/metadata.json"
mkdir "$backup/boot"
/bin/cp -cR "$boot_kit" "$backup/boot/$QPS_METADATA_IDENTITY"
_qps_assert_private_regular_file "$backup/rootfs.ext4" 'backup root disk'
[[ $(_qps_size "$backup/rootfs.ext4") == "$current_bytes" ]] || fail 'backup disk has the wrong size'
original_sha=$(_qps_sha256 "$disk")
[[ $original_sha == "$(_qps_sha256 "$backup/rootfs.ext4")" ]] || fail 'backup disk checksum mismatch; original disk unchanged'
/usr/bin/cmp -s "$workspace/metadata.json" "$backup/metadata.json" || fail 'backup metadata mismatch'
_qps_validate_boot_kit_directory "$backup/boot/$QPS_METADATA_IDENTITY" "$QPS_METADATA_IDENTITY"
printf 'originalBytes=%s\ntargetBytes=%s\noriginalSha256=%s\n' \
  "$current_bytes" "$target_bytes" "$original_sha" >"$backup/resize.txt"
_qps_fsync "$backup"

# Keep the descriptor bound to the validated inode and recheck its size before
# extending it. Never let a changed path or a concurrent growth become a shrink.
python3 - "$disk" "$current_bytes" "$target_bytes" "$disk_identity" <<'PY'
import os
import stat
import sys

path, old, new, identity = sys.argv[1:]
old, new = int(old), int(new)
fd = os.open(path, os.O_RDWR | os.O_NOFOLLOW | os.O_NONBLOCK)
try:
    info = os.fstat(fd)
    if (not stat.S_ISREG(info.st_mode) or info.st_nlink != 1
            or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o600
            or f"{info.st_dev}:{info.st_ino}" != identity
            or info.st_size != old or new <= old):
        raise SystemExit("resize-vm-disk: disk changed during backup; refusing to resize")
    os.ftruncate(fd, new)
    os.fsync(fd)
    if os.fstat(fd).st_size != new:
        raise SystemExit("resize-vm-disk: disk size verification failed; backup retained")
finally:
    os.close(fd)
PY
printf 'VM disk enlarged to %s GiB. Backup: %s\n' "$size_gib" "$backup"
printf 'Launch normally, then verify inside Omarchy with: lsblk; df -h /\n'
