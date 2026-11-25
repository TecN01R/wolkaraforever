#!/bin/bash
# Build xtool-duo: upstream xtool plus duo/xtool-increased-memory-limit.patch, which makes a free
# team request the increased-memory-limit capability that stock xtool silently drops.
#
# usage: duo/build_xtool.sh
#   Output: ../tools/xtool-duo (next to this clone). Your own `xtool` is not touched.
#   Needs: git, swift (tested with 6.4.3 via swiftly), dnf, rpm2cpio. No root: the
#   libimobiledevice/libplist/libusbmuxd headers come from the matching -devel RPMs, unpacked
#   into ../tools/devroot rather than installed. The build is several GB; on this machine record
#   it in ~/.claude/shared/machine-resources.md first.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
top=$(cd "$here/.." && pwd)
src=$top/upstream/xtool
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

# Headers for the system libraries xtool links, matching the installed runtime packages.
if [ ! -f "$devroot/usr/lib64/pkgconfig/libimobiledevice-1.0.pc" ]; then
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
