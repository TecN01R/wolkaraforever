#!/bin/bash
# Copy a Remote Pairing file into WolkaraForever's private storage on the phone, where Built-in
# JIT reads it: Library/StikJIT/pairingFile.plist inside the app's own container (not the
# Files-visible Documents folder). The file never leaves this computer and the phone.
#
# usage: duo/push_pairing.sh <pairing-file.plist>
#   Make the file with idevice_pair (https://github.com/jkcoxson/idevice_pair, Linux AppImage):
#   choose the phone, "Remote pairing", "Create", then "Save to file...". A lockdown pairing
#   record (the kind usbmuxd keeps in /var/lib/lockdown) is refused: StikJIT 2.x needs the
#   Remote Pairing kind.
#   DUO_BUNDLE_ID  the installed app's identifier (default: the one duo/install.sh installs)
#   USBMUXD_SOCKET_ADDRESS  as in duo/install.sh (default: the private netmuxd on :27099 if up)
set -euo pipefail
pairing=${1:-}
[ -n "$pairing" ] && [ -f "$pairing" ] || { echo "usage: duo/push_pairing.sh <pairing-file.plist>" >&2; exit 2; }
bundle=${DUO_BUNDLE_ID:-XTL-$(${DUO_XTOOL:-xtool} auth status 2>/dev/null | sed -n 's/^- Team ID: //p').local.wolkaraforever.duo}
case "$bundle" in XTL-.*) echo "push_pairing: cannot tell the team ID; set DUO_BUNDLE_ID" >&2; exit 1;; esac

# Read as data. Refuse what is certainly the wrong kind, never print the file's contents.
python3 -I - "$pairing" <<'PY'
import plistlib, sys
try:
    with open(sys.argv[1], "rb") as source:
        record = plistlib.load(source)
except Exception as error:
    raise SystemExit(f"push_pairing: not a property list: {error}")
if not isinstance(record, dict) or not record:
    raise SystemExit("push_pairing: the pairing file is empty or not a dictionary")
if {"DeviceCertificate", "HostPrivateKey", "RootCertificate"} <= record.keys():
    raise SystemExit("push_pairing: this is a lockdown pairing record; Built-in JIT needs a Remote Pairing "
                     "file (idevice_pair: choose \"Remote pairing\", then Create)")
print(f"push_pairing: pairing file with {len(record)} keys")
PY

if [ -z "${USBMUXD_SOCKET_ADDRESS:-}" ] && ss -ltn 2>/dev/null | grep -q '127\.0\.0\.1:27099 '; then
    export USBMUXD_SOCKET_ADDRESS=127.0.0.1:27099
fi
timeout 30 pymobiledevice3 usbmux list 2>/dev/null | grep -q '"ProductType"' || {
    echo "push_pairing: the phone is not reachable; wake and unlock it on the same Wi-Fi, then retry" >&2; exit 1
}

# Stage it under the exact name the app reads, readable by this user only, removed afterwards.
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
chmod 700 "$stage"
mkdir "$stage/StikJIT"
install -m 600 "$pairing" "$stage/StikJIT/pairingFile.plist"
timeout 120 pymobiledevice3 apps push "$bundle" "$stage/StikJIT/pairingFile.plist" "Library/StikJIT/pairingFile.plist" ||
timeout 120 pymobiledevice3 apps push "$bundle" "$stage/StikJIT" "Library"
echo "push_pairing: installed into $bundle at Library/StikJIT/pairingFile.plist"
