#!/bin/bash
# Sign the External JIT .ipa with your free Apple ID through xtool and install it on the phone.
# Running it again with the same Apple ID is also the weekly signature renewal: the bundle
# identifier stays XTL-<team>.local.wolkaraforever.duo, so the game data and settings stay.
#
# usage: duo/install.sh [path.ipa]       (default: ../builds/latest.ipa)
#   DUO_UDID     the phone's UDID (default: let xtool pick the only device it finds)
#   DUO_NETWORK  1 to install over Wi-Fi only (xtool --network), 0 for USB only (--usb)
#
# Before running: close WolkaraForever on the phone (swipe it away). Replacing the app while
# the game runs corrupted the client's update index once upstream (docs/BUILDING.md, stage 0).
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
builds=${DUO_BUILDS:-$(cd "$here/.." && pwd)/builds}
ipa=$(readlink -f "${1:-$builds/latest.ipa}")
[ -f "$ipa" ] || { echo "install: no .ipa at $ipa (run duo/fetch_ipa.sh first)" >&2; exit 1; }

args=()
[ -n "${DUO_UDID:-}" ] && args+=(--udid "$DUO_UDID")
case "${DUO_NETWORK:-}" in 1) args+=(--network);; 0) args+=(--usb);; esac

if [ -t 0 ]; then
    read -r -p "Is WolkaraForever closed on the phone (swiped away, game not running)? [y/N] " answer
    case "$answer" in y|Y|yes) ;; *) echo "install: stopped; close the app first"; exit 1;; esac
fi

log="$builds/install-$(date +%Y%m%d-%H%M%S).log"
echo "install: signing and installing $(basename "$(dirname "$ipa")")/$(basename "$ipa"); log: $log"
xtool install "${args[@]}" "$ipa" 2>&1 | tee "$log"
status=${PIPESTATUS[0]}
[ "$status" -eq 0 ] || { echo "install: xtool failed ($status); see $log" >&2; exit "$status"; }
echo "install: done. The free signature lasts 7 days; run this again before then to renew it."
