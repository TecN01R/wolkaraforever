#!/bin/bash
# Sign the External JIT .ipa with your free Apple ID through xtool and install it on the phone.
# Running it again with the same Apple ID is also the weekly signature renewal: the bundle
# identifier stays XTL-<team>.local.wolkaraforever.duo, so the game data and settings stay.
#
# usage: duo/install.sh [path.ipa]       (default: ../builds/latest.ipa)
#   DUO_UDID     the phone's UDID (default: let xtool pick the only device it finds)
#   DUO_NETWORK  1 to install over Wi-Fi only (xtool --network), 0 for USB only (--usb)
#   USBMUXD_SOCKET_ADDRESS  the muxer to reach the phone through. Default: the private Wi-Fi
#                netmuxd on 127.0.0.1:27099 when one listens there (the world-editor setup,
#                world-editor/docs/fedora.md), else the system usbmuxd.
#   DUO_INSTALL_TIMEOUT  seconds before giving up on xtool (default 600): if the phone drops
#                out, xtool otherwise waits for ever.
#   DUO_XTOOL    the xtool to sign with (default: ../tools/xtool-duo when present, else xtool).
#                xtool-duo is upstream xtool plus the increased-memory-limit capability, which
#                stock xtool drops on a free team. XTL_TRY_FREE_EVA=1 also asks Apple for
#                extended-virtual-addressing (paid-only per Apple; a refusal stops the install).
#
# Before running: close WolkaraForever on the phone (swipe it away). Replacing the app while
# the game runs corrupted the client's update index once upstream (docs/BUILDING.md, stage 0).
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
builds=${DUO_BUILDS:-$(cd "$here/.." && pwd)/builds}
ipa=$(readlink -f "${1:-$builds/latest.ipa}")
[ -f "$ipa" ] || { echo "install: no .ipa at $ipa (run duo/fetch_ipa.sh first)" >&2; exit 1; }

xtool_bin=${DUO_XTOOL:-}
if [ -z "$xtool_bin" ]; then
    xtool_bin=$(cd "$here/.." && pwd)/tools/xtool-duo
    [ -x "$xtool_bin" ] || xtool_bin=xtool
fi

args=()
[ -n "${DUO_UDID:-}" ] && args+=(--udid "$DUO_UDID")
case "${DUO_NETWORK:-}" in 1) args+=(--network);; 0) args+=(--usb);; esac

# Reach the phone the way world-editor does: over Wi-Fi through a private netmuxd when one runs.
if [ -z "${USBMUXD_SOCKET_ADDRESS:-}" ] && ss -ltn 2>/dev/null | grep -q '127\.0\.0\.1:27099 '; then
    export USBMUXD_SOCKET_ADDRESS=127.0.0.1:27099
fi
# Stop before xtool when the phone is not listed: an unreachable phone makes xtool hang.
if command -v pymobiledevice3 >/dev/null; then
    listed=$(timeout 30 pymobiledevice3 usbmux list 2>/dev/null | python3 -I -c '
import json, sys
try: devices = json.load(sys.stdin)
except Exception: devices = []
for d in devices: print(d.get("ProductType", "?"), d.get("ProductVersion", "?"), d.get("ConnectionType", "?"))' || true)
    if [ -z "$listed" ]; then
        echo "install: the phone is not reachable${USBMUXD_SOCKET_ADDRESS:+ through $USBMUXD_SOCKET_ADDRESS}." >&2
        echo "install: wake and unlock it on the same Wi-Fi (and not charging from this PC), then retry." >&2
        echo "install: if it still is not listed, the netmuxd serving it may have lost it; restart" >&2
        echo "install: that one as world-editor/docs/fedora.md describes." >&2
        exit 1
    fi
    echo "install: phone reachable: $(printf '%s' "$listed" | head -1)"
fi

if [ -t 0 ]; then
    read -r -p "Is WolkaraForever closed on the phone (swiped away, game not running)? [y/N] " answer
    case "$answer" in y|Y|yes) ;; *) echo "install: stopped; close the app first"; exit 1;; esac
fi

log="$builds/install-$(date +%Y%m%d-%H%M%S).log"
echo "install: signing with $xtool_bin; installing $(basename "$(dirname "$ipa")")/$(basename "$ipa"); log: $log"
timeout "${DUO_INSTALL_TIMEOUT:-600}" "$xtool_bin" install "${args[@]}" "$ipa" 2>&1 | tee "$log"
status=${PIPESTATUS[0]}
[ "$status" -ne 124 ] || { echo "install: xtool gave no result in ${DUO_INSTALL_TIMEOUT:-600} s (phone asleep or out of reach?); see $log" >&2; exit 124; }
[ "$status" -eq 0 ] || { echo "install: xtool failed ($status); see $log" >&2; exit "$status"; }
# What Apple granted, from the profile it issued for this app: the entitlements the signed
# app may hold. The memory limit the game gets depends on this line.
granted=$("$xtool_bin" ds profiles list 2>/dev/null | grep -F 'entitlements:' | grep -F 'local.wolkaraforever.duo' | tail -1 || true)
if [ -n "$granted" ]; then
    echo "install: profile ${granted#*entitlements: }"
    case "$granted" in
        *increased-memory-limit*) echo "install: increased-memory-limit granted" ;;
        *) echo "install: increased-memory-limit NOT in the profile (default memory limit applies)" ;;
    esac
    case "$granted" in *extended-virtual-addressing*) echo "install: extended-virtual-addressing granted" ;; esac
fi
echo "install: done. The free signature lasts 7 days; run this again before then to renew it."
