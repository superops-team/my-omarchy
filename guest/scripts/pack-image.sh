#!/bin/bash

set -euo pipefail

usage() {
  echo "Usage: pack-image.sh --root ROOT --output DIR [--spec SPEC]"
}

fail() {
  echo "pack-image: $*" >&2
  exit 1
}

script_dir=$(cd "$(dirname "$0")" && pwd)
guest_dir=$(cd "$script_dir/.." && pwd)
spec="$guest_dir/spec.json"
root=""
output=""

while (($#)); do
  case "$1" in
    --root)
      root=${2:-}
      shift 2
      ;;
    --output)
      output=${2:-}
      shift 2
      ;;
    --spec)
      spec=${2:-}
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown option: $1"
      ;;
  esac
done

[[ -n $root ]] || fail "--root is required"
[[ -n $output ]] || fail "--output is required"
[[ $root == /* && $output == /* ]] || fail "root and output paths must be absolute"
kernel_source=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["runtime"].get("kernelSource", "/boot/vmlinuz-linux"))' "$spec")
initramfs_source=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["runtime"].get("initramfsSource", "/boot/initramfs-linux.img"))' "$spec")
[[ $kernel_source == /boot/* && $kernel_source != *..* ]] || fail "unsafe kernel source in spec"
[[ $initramfs_source == /boot/* && $initramfs_source != *..* ]] || fail "unsafe initramfs source in spec"
[[ -f $root$kernel_source ]] || fail "kernel missing from staged root: $kernel_source"
[[ -f $root$initramfs_source ]] || fail "initramfs missing from staged root: $initramfs_source"
for command in mke2fs e2fsck zstd python3; do
  command -v "$command" >/dev/null || fail "$command is required"
done

size_mib=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["image"]["sizeMiB"])' "$spec")
label=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["image"]["filesystemLabel"])' "$spec")
uuid=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["image"]["filesystemUuid"])' "$spec")
source_date_epoch=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["image"]["sourceDateEpoch"])' "$spec")
used_kib=$(du -sk "$root" | awk '{print $1}')
capacity_kib=$((size_mib * 1024))
(( used_kib < capacity_kib * 85 / 100 )) || fail "staged root uses ${used_kib} KiB; ${size_mib} MiB image has insufficient headroom"

mkdir -p "$output"
raw="$output/rootfs.ext4"
compressed="$output/rootfs.ext4.zst"
truncate -s "${size_mib}M" "$raw"
blocks=$((size_mib * 1024 * 1024 / 4096))

export SOURCE_DATE_EPOCH="$source_date_epoch"
export E2FSPROGS_FAKE_TIME="$source_date_epoch"
mke2fs -q -F -t ext4 -b 4096 -L "$label" -U "$uuid" \
  -E lazy_itable_init=0,lazy_journal_init=0 \
  -d "$root" "$raw" "$blocks"
e2fsck -fn "$raw"

install -m 0644 "$root$kernel_source" "$output/vmlinuz-linux"
install -m 0644 "$root$initramfs_source" "$output/initramfs-linux.img"
install -m 0644 "$root/usr/share/my-omarchy/build-spec.json" "$output/build-spec.json"
install -m 0644 "$root/usr/share/my-omarchy/provenance.json" "$output/provenance.json"
install -m 0644 "$root/usr/share/licenses/omarchy/LICENSE" "$output/LICENSE.omarchy"
if [[ -f $root/usr/share/my-omarchy/packages.lock.txt ]]; then
  install -m 0644 "$root/usr/share/my-omarchy/packages.lock.txt" "$output/packages.lock.txt"
fi

zstd --force --quiet -12 --threads=0 "$raw" -o "$compressed"
python3 "$guest_dir/scripts/write-guest-manifest.py" --directory "$output" --spec "$spec"

(
  cd "$output"
  sha256sum \
    LICENSE.omarchy \
    build-spec.json \
    guest-manifest.json \
    initramfs-linux.img \
    provenance.json \
    rootfs.ext4 \
    rootfs.ext4.zst \
    vmlinuz-linux >SHA256SUMS
  [[ ! -f packages.lock.txt ]] || sha256sum packages.lock.txt >>SHA256SUMS
)

echo "Packed guest artifacts in $output"
