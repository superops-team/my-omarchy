#!/bin/bash
set -euo pipefail

fail() { echo "mesa-venus: $*" >&2; exit 1; }
root=
work=
spec=
pacman_config=
output=
while (($#)); do
  case "$1" in
    --root) root=${2:?}; shift 2 ;;
    --work) work=${2:?}; shift 2 ;;
    --spec) spec=${2:?}; shift 2 ;;
    --pacman-config) pacman_config=${2:?}; shift 2 ;;
    --output) output=${2:?}; shift 2 ;;
    *) fail "unknown option: $1" ;;
  esac
done
[[ $work == /* && -d $work && ! -L $work ]] || fail 'invalid work directory'
[[ -f $spec && -f $pacman_config ]] || fail 'spec and pacman config are required'
[[ $(uname -m) == aarch64 ]] || fail 'native ARM64 builder required'
if [[ -n $root ]]; then
  [[ $root == /* && -d $root && ! -L $root ]] || fail 'invalid staged root'
  root=$(cd "$root" && pwd -P)
  case "$root" in /|/bin|/boot|/etc|/home|/opt|/root|/usr|/var) fail 'unsafe staged root' ;; esac
else
  [[ $output == /* && -d $output && ! -L $output ]] || fail '--root or --output is required'
fi
mapfile -t metadata < <(python3 - "$spec" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
m = s['supplyChain']['mesaVenus']
for key in ('version', 'pkgrel', 'url', 'sha256', 'patch', 'patchSha256'):
    print(m[key])
print(s['image']['sourceDateEpoch'])
PY
)
[[ ${#metadata[@]} == 7 ]] || fail 'invalid Mesa metadata'
version=${metadata[0]}
pkgrel=${metadata[1]}
url=${metadata[2]}
sha256=${metadata[3]}
patch_path="$(dirname "$spec")/${metadata[4]}"
patch_sha256=${metadata[5]}
export SOURCE_DATE_EPOCH=${metadata[6]}
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && $pkgrel =~ ^[0-9.]+$ ]] || fail 'invalid Mesa version'
verify() { printf '%s  %s\n' "$1" "$2" | sha256sum -c - >/dev/null; }
verify "$patch_sha256" "$patch_path" || fail 'Mesa patch digest mismatch'
cache="$work/download-cache"
mkdir -p "$cache"
archive="$cache/mesa-$version.tar.xz"
[[ ! -L $archive ]] || fail 'unsafe Mesa archive'
if [[ ! -f $archive ]]; then
  temporary=$(mktemp "$cache/.mesa-download.XXXXXX")
  if ! curl --fail --location --proto '=https' --proto-redir '=https' --tlsv1.2 \
    --connect-timeout 20 --max-time 900 --output "$temporary" "$url" ||
    ! verify "$sha256" "$temporary"; then
    rm -f "$temporary"
    fail 'Mesa download failed verification'
  fi
  mv "$temporary" "$archive"
fi
verify "$sha256" "$archive" || fail 'Mesa source digest mismatch'
stage=$(mktemp -d "$work/mesa-venus.XXXXXX")
trap 'rm -rf -- "$stage"' EXIT
python3 - "$spec" "$pacman_config" "$stage" "$archive" <<'PY'
import json, pathlib, re, sys, tarfile
spec, config, stage, archive = map(pathlib.Path, sys.argv[1:])
s = json.loads(spec.read_text())
component = s['supplyChain']['mesaVenus']
section = None
lines = []
for line in config.read_text().splitlines():
    if re.fullmatch(r'\[[A-Za-z0-9@._+-]+\]', line):
        section = line[1:-1]
    if section not in ('omarchy', 'my-omarchy') and not line.startswith('IgnorePkg'):
        lines.append(line)
(stage / 'pacman.conf').write_text('\n'.join(lines) + '\n')
packages = component['buildPackages']
if not packages or any(not re.fullmatch(r'[a-z0-9@._+-]+', k) or
                       not re.fullmatch(r'[A-Za-z0-9_.+:~-]+', v)
                       for k, v in packages.items()):
    raise SystemExit('invalid Mesa build package pins')
(stage / 'packages').write_text(''.join(f'{k}={v}\n' for k, v in sorted(packages.items())))
with tarfile.open(archive) as source:
    expected = f'mesa-{component["version"]}'
    for m in source.getmembers():
        path = pathlib.PurePosixPath(m.name)
        if not path.parts or path.parts[0] != expected or '..' in path.parts:
            raise SystemExit('unsafe Mesa source member')
    source.extractall(stage, filter='data')
PY
mapfile -t packages <"$stage/packages"
pacman --noconfirm --config "$stage/pacman.conf" -Syy
pacman --noconfirm --config "$stage/pacman.conf" -S --needed "${packages[@]}"
for record in "${packages[@]}"; do
  [[ $(pacman -Q "${record%%=*}") == "${record%%=*} ${record#*=}" ]] || fail "build package mismatch: $record"
done
source_root="$stage/mesa-$version"
[[ $(<"$source_root/VERSION") == "$version" ]] || fail 'Mesa source version mismatch'
patch -d "$source_root" -p1 --batch --fuzz=0 -i "$patch_path"
export CFLAGS="-O2 -ffile-prefix-map=$stage=/usr/src/my-omarchy-mesa"
export CXXFLAGS="$CFLAGS"
meson setup "$stage/build" "$source_root" --prefix=/usr --libdir=lib \
  --buildtype=release --wrap-mode=nodownload \
  -Dgallium-drivers= -Dvulkan-drivers=virtio -Dplatforms=x11,wayland \
  -Dglx=disabled -Degl=disabled -Dgbm=disabled -Dgles1=disabled -Dgles2=disabled \
  -Dopengl=false -Dllvm=disabled -Dvideo-codecs= -Dbuild-tests=false
ninja -C "$stage/build" -j6
DESTDIR="$stage/install" meson install -C "$stage/build" --no-rebuild
package="$stage/package"
install -Dm0755 "$stage/install/usr/lib/libvulkan_virtio.so" "$package/usr/lib/libvulkan_virtio.so"
install -Dm0644 "$stage/install/usr/share/vulkan/icd.d/virtio_icd.aarch64.json" \
  "$package/usr/share/vulkan/icd.d/virtio_icd.aarch64.json"
# Arch's mesa package owns the shared drirc defaults, including Venus.
library="$package/usr/lib/libvulkan_virtio.so"
icd="$package/usr/share/vulkan/icd.d/virtio_icd.aarch64.json"
[[ -f $library && -f $icd ]] || fail 'Venus driver output missing'
strip --strip-unneeded "$library"
python3 - "$library" "$icd" <<'PY'
import json, pathlib, sys
h = pathlib.Path(sys.argv[1]).read_bytes()[:20]
if h[:6] != b'\x7fELF\x02\x01' or int.from_bytes(h[18:20], 'little') != 183:
    raise SystemExit('Venus driver is not ARM64 ELF')
if pathlib.Path(json.load(open(sys.argv[2]))['ICD']['library_path']).name != 'libvulkan_virtio.so':
    raise SystemExit('Venus ICD points to an unexpected driver')
PY
install -Dm0644 "$source_root/docs/license.rst" "$package/usr/share/licenses/vulkan-virtio/LICENSE"
cat >"$package/.PKGINFO" <<EOF
pkgname = vulkan-virtio
pkgbase = mesa
pkgver = 1:$version-$pkgrel
pkgdesc = Venus Vulkan driver with Apple Silicon 16K host-page support
url = https://www.mesa3d.org/
builddate = $SOURCE_DATE_EPOCH
packager = My Omarchy guest builder
size = $(du -sb "$package/usr" | cut -f1)
arch = aarch64
license = MIT
provides = vulkan-driver
depend = gcc-libs
depend = glibc
depend = libdrm
depend = libx11
depend = libxcb
depend = libxshmfence
depend = wayland
depend = zlib
depend = zstd
depend = expat
depend = systemd-libs
EOF
package_archive="$stage/vulkan-virtio-$version-$pkgrel-aarch64.pkg.tar.zst"
tar --sort=name --mtime="@$SOURCE_DATE_EPOCH" --owner=0 --group=0 --numeric-owner \
  --format=gnu -C "$package" -cf - .PKGINFO usr | zstd -q -12 -T1 -o "$package_archive"
if [[ -n $root ]]; then
  pacman --noconfirm --config "$pacman_config" --root "$root" \
    --dbpath "$root/var/lib/pacman" -U "$package_archive"
  pacman --config "$pacman_config" --root "$root" --dbpath "$root/var/lib/pacman" \
    -Qkk vulkan-virtio >/dev/null
  output="$root/usr/share/my-omarchy/repo"
  install -d -m0755 "$output"
fi
install -m0644 "$package_archive" "$output/"
sha256sum "$library"
echo "Registered Vulkan Venus $version-$pkgrel in $output"
