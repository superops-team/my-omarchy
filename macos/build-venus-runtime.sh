#!/bin/bash

set -euo pipefail

[[ $# == 5 ]] || { echo 'Usage: build-venus-runtime.sh WORK ARCHIVES ANGLE EPOXY NINJA' >&2; exit 64; }
work=$1
archives=$2
angle=$3
epoxy=$4
ninja=$5
native_dir=$(cd "$(dirname "$0")" && pwd -P)
for tool in cmake python3 patch; do
  command -v "$tool" >/dev/null || { echo "venus-build: missing $tool" >&2; exit 1; }
done
mkdir -p "$work/sources" "$work/tools" "$work/install/lib"
python3 - "$native_dir/venus-sources.json" "$archives" "$work" <<'PY'
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import zipfile

manifest, archives, work = map(Path, sys.argv[1:])
for name, entry in json.loads(manifest.read_text()).items():
    archive = archives / entry['archive']
    if not archive.exists():
        subprocess.run(['curl', '--fail', '--location', '--silent', '--show-error',
                        '--proto', '=https', '--proto-redir', '=https', '--tlsv1.2',
                        '--retry', '3', '--output', str(archive), entry['url']], check=True)
    if archive.is_symlink() or hashlib.sha256(archive.read_bytes()).hexdigest() != entry['sha256']:
        raise SystemExit(f'venus-build: checksum mismatch: {name}')
    destination = work / 'sources' / name
    destination.mkdir()
    if archive.name.endswith('.tar.gz'):
        with tarfile.open(archive) as source:
            members = source.getmembers()
            roots = {Path(m.name).parts[0] for m in members}
            if len(roots) != 1:
                raise SystemExit(f'venus-build: invalid archive root: {name}')
            source.extractall(destination, filter='data')
        root = destination / roots.pop()
        for child in root.iterdir():
            shutil.move(str(child), destination / child.name)
        root.rmdir()
    elif archive.suffix == '.whl':
        with zipfile.ZipFile(archive) as source:
            if any(Path(n).is_absolute() or '..' in Path(n).parts for n in source.namelist()):
                raise SystemExit('venus-build: unsafe wheel')
            source.extractall(destination)
    else:
        shutil.copyfile(archive, destination / archive.name)
PY

sources="$work/sources"
virgl="$sources/virglrenderer"
darwin="$sources/darwin-patches"
for name in \
  virglrenderer-debug-init-logging \
  virglrenderer-default-debug-log \
  virglrenderer-macos-unified \
  virglrenderer-venus-metal-func-ptrs \
  virglrenderer-gallium-endian \
  virglrenderer-macos-a8-swizzle \
  virglrenderer-corefoundation-link \
  virglrenderer-a8-shader-swizzle \
  virglrenderer-a8-shader-swizzle-texture \
  virglrenderer-a8-unpack-alignment \
  virglrenderer-bgra-upload-swizzle-core \
  virglrenderer-msaa-assertion-fix \
  virglrenderer-ignore-surface0-clear \
  virglrenderer-venus-errno-debug \
  virglrenderer-macos-profile-forcing \
  virglrenderer-macos-egl-profile \
  virglrenderer-texture-swizzle-core \
  virglrenderer-bgra-unified \
  virglrenderer-core-profile-frag-datalocation \
  virglrenderer-macos-core-profile-fixes \
  virglrenderer-gles-dual-source-output; do
  patch -d "$virgl" -p1 -f -i "$darwin/patches/$name.patch"
done
patch -d "$virgl" -p1 -f -i "$native_dir/patches/virglrenderer-venus-darwin.patch"
patch -d "$virgl" -p1 -f -i "$native_dir/patches/virglrenderer-darwin-control-buffer.patch"
python3 "$native_dir/Tests/venus-socket.test.py" "$virgl"
patch -d "$sources/moltenvk" -p1 -f -i "$native_dir/patches/moltenvk-native-arrays.patch"

mkdir -p "$work/cpm/cpm"
install -m 0644 "$sources/cpm/CPM.cmake" "$work/cpm/cpm/CPM_0.40.8.cmake"
cmake -S "$sources/moltenvk" -B "$work/moltenvk-build" \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DMVK_EXCLUDE_SPIRV_TOOLS=ON -DMVK_EXCLUDE_CEREAL=ON \
  -DMVK_USE_METAL_PRIVATE_API=OFF -DMOLTEN_VK_WITH_CCACHE=OFF \
  -DCPM_SOURCE_CACHE="$work/cpm" \
  -DCPM_LOCAL_PACKAGES_ONLY=ON \
  -DFETCHCONTENT_FULLY_DISCONNECTED=ON \
  "-DCPM_SPIRV-Cross_SOURCE=$sources/spirv-cross" \
  "-DCPM_Vulkan-Headers_SOURCE=$sources/vulkan-headers"
cmake --build "$work/moltenvk-build" --parallel 6
install -m 0755 "$work/moltenvk-build/MoltenVK/libMoltenVK.dylib" "$work/install/lib/"

cmake -S "$sources/vulkan-headers" -B "$work/headers-build" \
  -DCMAKE_INSTALL_PREFIX="$work/headers" -DVULKAN_HEADERS_ENABLE_INSTALL=ON
cmake --install "$work/headers-build"
cmake -S "$sources/vulkan-loader" -B "$work/loader-build" \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
  -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_PREFIX_PATH="$work/headers" \
  -DBUILD_TESTS=OFF -DUPDATE_DEPS=OFF -DBUILD_WERROR=ON
cmake --build "$work/loader-build" --parallel 6
install -m 0755 "$work/loader-build/loader/libvulkan.1.4.357.dylib" "$work/install/lib/libvulkan.1.dylib"

export MACOSX_DEPLOYMENT_TARGET=15.0
export PYTHONPATH="$sources/meson:$sources/pyyaml/lib"
export PKG_CONFIG_PATH=
export PKG_CONFIG_LIBDIR="$epoxy/lib/pkgconfig:$angle/lib/pkgconfig"
export DYLD_LIBRARY_PATH="$epoxy/lib:$angle/lib"
export NINJA="$ninja"
python3 -m mesonbuild.mesonmain setup "$work/virgl-build" "$virgl" \
  --prefix="$work/install" --libdir=lib --buildtype=release --wrap-mode=nodownload \
  "-Dc_args=-I$angle/include -mmacosx-version-min=15.0" \
  -Dplatforms=egl -Ddrm-renderers=[] -Dvenus=true -Drender-server-worker=thread \
  -Dtests=false -Dvideo=false -Dtracing=none
"$ninja" -C "$work/virgl-build"
python3 -m mesonbuild.mesonmain install -C "$work/virgl-build"
