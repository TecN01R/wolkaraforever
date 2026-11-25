#!/bin/bash
# Build xtool-duo: upstream xtool plus duo/xtool-increased-memory-limit.patch, which makes a free
# team request the increased-memory-limit capability that stock xtool silently drops.
#
# Most people do not need this: download the ready-made AppImage from this repository's
# "xtool-duo" release instead (docs/INSTALL-WITHOUT-A-MAC.md). Build it yourself to check it.
#
# usage: duo/build_xtool.sh
#   Output: ../tools/xtool-duo (next to this clone). Your own `xtool` is not touched.
#   Needs: git, a Swift 6.4 toolchain (https://swift.org/install/linux), and the libimobiledevice,
#   libplist and libusbmuxd development headers: install them with your package manager
#   (Debian/Ubuntu: libimobiledevice-dev libplist-dev libusbmuxd-dev; Fedora: the -devel
#   packages). On Fedora without root, the -devel RPMs are unpacked into ../tools/devroot instead.
#   The build takes several GB of disk and memory; DUO_BUILD_JOBS limits its parallel jobs.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
top=$(cd "$here/.." && pwd)
src=${DUO_XTOOL_SRC:-$top/upstream/xtool}
[ -d "$src/.git" ] || src=${DUO_XTOOL_SRC:-$top/tools/xtool-src}
devroot=$top/tools/devroot
base=9f7663744778d9b9449ab3fcee9170b0d1e55eaf   # the xtool commit the patch was made against

if [ ! -d "$src/.git" ]; then
    git clone -q https://github.com/xtool-org/xtool "$src"
fi
git -C "$src" fetch -q origin "$base" 2>/dev/null || true
if ! git -C "$src" apply --reverse --check "$here/duo/xtool-increased-memory-limit.patch" 2>/dev/null; then
    git -C "$src" checkout -q "$base"
    git -C "$src" apply "$here/duo/xtool-increased-memory-limit.patch"
fi

# Headers for the system libraries xtool links, matching the installed runtime packages: the
# system's own when installed, else (Fedora, no root) unpacked from the -devel RPMs.
if pkg-config --exists libimobiledevice-1.0 libplist-2.0 libusbmuxd-2.0 2>/dev/null; then
    :
elif ! command -v dnf >/dev/null || ! command -v rpm2cpio >/dev/null; then
    echo "build_xtool: install the libimobiledevice, libplist and libusbmuxd development packages" >&2
    exit 1
elif [ ! -f "$devroot/usr/lib64/pkgconfig/libimobiledevice-1.0.pc" ]; then
    mkdir -p "$devroot/rpms"
    ( cd "$devroot/rpms" && dnf download --arch x86_64 libplist-devel libusbmuxd-devel \
        libimobiledevice-glue-devel libimobiledevice-devel )
    ( cd "$devroot" && for r in rpms/*.x86_64.rpm; do rpm2cpio "$r" | cpio -idm --quiet; done )
    for l in "$devroot"/usr/lib64/*.so; do
        ln -sfn "/usr/lib64/$(basename "$(readlink "$l")")" "$l"
    done
    sed -i -e "s#^prefix=/usr#prefix=$devroot/usr#" -e "s#^includedir=/usr/include#includedir=$devroot/usr/include#" \
        -e "s#^libdir=.*#libdir=$devroot/usr/lib64#" "$devroot"/usr/lib64/pkgconfig/*.pc
fi
export PKG_CONFIG_PATH=$devroot/usr/lib64/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}

jobs=${DUO_BUILD_JOBS:-6}
( cd "$src" && swift build -c release --product xtool -j "$jobs" )
mkdir -p "$top/tools"
cp "$src/.build/release/xtool" "$top/tools/xtool-duo"
echo "build_xtool: $top/tools/xtool-duo"
