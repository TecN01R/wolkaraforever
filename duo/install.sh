#!/bin/bash
# Sign the External JIT .ipa with your free Apple ID through xtool and install it on the phone.
# Running it again with the same Apple ID is also the weekly signature renewal: the bundle
# identifier stays XTL-<team>.local.wolkaraforever.duo, so the game data and settings stay.
#
# usage: duo/install.sh [path.ipa]       (default: ../builds/latest.ipa)
#   DUO_UDID     the phone's UDID (default: let xtool pick the only device it finds)
#   DUO_NETWORK  1 to install over Wi-Fi only (xtool --network), 0 for USB only (--usb)
#   USBMUXD_SOCKET_ADDRESS  the muxer to reach the phone through. Default: a netmuxd (Wi-Fi) on
#                127.0.0.1:27099 when one listens there, else the system usbmuxd (USB cable).
#   DUO_INSTALL_TIMEOUT  seconds before giving up on xtool (default 600): if the phone drops
#                out, xtool otherwise waits for ever.
#   DUO_XTOOL    the xtool to sign with. Default, the first that exists: ../tools/xtool-duo,
#                ../tools/xtool-duo-x86_64.AppImage (the download from this repository's
#                "xtool-duo" release), else `xtool` on PATH. xtool-duo is upstream xtool plus the
#                increased-memory-limit capability, which stock xtool drops on a free team. XTL_TRY_FREE_EVA=1 also asks Apple for
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
    xtool_bin=xtool
    for candidate in "$(cd "$here/.." && pwd)/tools/xtool-duo" \
                     "$(cd "$here/.." && pwd)/tools/xtool-duo-$(uname -m).AppImage"; do
        [ -x "$candidate" ] && { xtool_bin=$candidate; break; }
    done
fi
command -v "$xtool_bin" >/dev/null || {
    echo "install: no xtool found; download xtool-duo (docs/INSTALL-WITHOUT-A-MAC.md, step 2)" >&2; exit 1
}

args=()
[ -n "${DUO_UDID:-}" ] && args+=(--udid "$DUO_UDID")
case "${DUO_NETWORK:-}" in 1) args+=(--network);; 0) args+=(--usb);; esac

# Over Wi-Fi through a netmuxd when one runs on the usual port; otherwise USB through usbmuxd.
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
        echo "install: connect it with a USB cable (or, with netmuxd, the same Wi-Fi), unlock it," >&2
        echo "install: tap Trust if it asks, then retry. Check with: pymobiledevice3 usbmux list" >&2
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
# What Apple granted, from the profiles it issued: the app's own (the entitlements the signed
# app may hold; the memory limit the game gets depends on it) and when the signature ends. The
# app's application-identifier ends in .local.wolkaraforever.duo; the helper's in .jithelper.
profiles=$("$xtool_bin" ds profiles list 2>/dev/null || true)
pick() {   # pick SUFFIX FIELD: FIELD of the profile whose application-identifier ends in SUFFIX
    printf '%s\n' "$profiles" | awk -v suffix="$1\"" -v field="$2" '
        /^- id:/ { if (match_ && value != "") print value; match_ = 0; value = "" }
        index($0, "application-identifier") && index($0, suffix) { match_ = 1 }
        $0 ~ "^ *" field ":" { value = substr($0, index($0, ":") + 2) }
        END { if (match_ && value != "") print value }' | tail -1
}
granted=$(pick .local.wolkaraforever.duo entitlements)
if [ -n "$granted" ]; then
    echo "install: profile $granted"
    case "$granted" in
        *increased-memory-limit*) echo "install: increased-memory-limit granted" ;;
        *) echo "install: increased-memory-limit NOT in the profile (default memory limit applies)" ;;
    esac
    case "$granted" in *extended-virtual-addressing*) echo "install: extended-virtual-addressing granted" ;; esac
fi
app_expiry=$(pick .local.wolkaraforever.duo "expiration date")
helper_expiry=$(pick .local.wolkaraforever.duo.jithelper "expiration date")
[ -z "$app_expiry" ] || echo "install: the app's signature ends ${app_expiry}; run this again before then"
[ -z "$helper_expiry" ] || [ "$helper_expiry" = "$app_expiry" ] ||
    echo "install: the JIT helper's signature ends ${helper_expiry}"
echo "install: done. The free signature lasts 7 days; run this again before then to renew it."
