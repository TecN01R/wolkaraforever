#!/bin/bash
# Copy a Remote Pairing file into WolkaraForever's private storage on the phone, where Built-in
# JIT reads it: Library/StikJIT/pairingFile.plist inside the app's own container (not the
# Files-visible Documents folder). The file never leaves this computer and the phone.
#
# usage: duo/push_pairing.sh <pairing-file.plist>
#   Make the file from the terminal on iOS 27 (no cable):
#     pymobiledevice3 remote pair-host --name "WolkaraForever (Fedora)"
#   then on the phone Settings > Developer > Paired Macs > Other Devices > that name > Pair, and
#   type the code it prints. Pass the record it reports (~/.pymobiledevice3/remote_<udid>.plist);
#   it is converted to StikJIT's format here. An idevice_pair "Remote pairing" file works as is.
#   Or, with no interaction at all, over the already-trusted lockdown connection:
#     pymobiledevice3 lockdown remotepairing --pair   (record in ~/.local/share/pymobiledevice3/)
#   A lockdown pairing record (the kind usbmuxd keeps in /var/lib/lockdown) is refused: StikJIT
#   2.x needs the Remote Pairing kind.
#   DUO_BUNDLE_ID  the installed app's identifier (default: the one duo/install.sh installs)
#   USBMUXD_SOCKET_ADDRESS  as in duo/install.sh (default: the private netmuxd on :27099 if up)
set -euo pipefail
pairing=${1:-}
[ -n "$pairing" ] && [ -f "$pairing" ] || { echo "usage: duo/push_pairing.sh <pairing-file.plist>" >&2; exit 2; }
bundle=${DUO_BUNDLE_ID:-XTL-$(${DUO_XTOOL:-xtool} auth status 2>/dev/null | sed -n 's/^- Team ID: //p').local.wolkaraforever.duo}
case "$bundle" in XTL-.*) echo "push_pairing: cannot tell the team ID; set DUO_BUNDLE_ID" >&2; exit 1;; esac

# Stage it under the exact name the app reads, readable by this user only, removed afterwards.
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
chmod 700 "$stage"
mkdir "$stage/StikJIT"

# Read as data and write StikJIT's Remote Pairing format (idevice RpPairingFile: public_key,
# private_key, identifier, optional alt_irk). Accepts that format as is, or converts the record
# `pymobiledevice3 remote pair-host` writes (host_identifier, peer_alt_irk). Refuses a lockdown
# record. Never prints key material.
# A record made over lockdown (`pymobiledevice3 lockdown remotepairing --pair`) does not store the
# host identifier: it is pymobiledevice3's deterministic one for this computer.
host_id=$(python3 -c 'from pymobiledevice3.pair_records import generate_host_id; print(generate_host_id())' 2>/dev/null || true)
python3 -I - "$pairing" "$stage/StikJIT/pairingFile.plist" "$host_id" <<'PY'
import os, plistlib, sys
try:
    with open(sys.argv[1], "rb") as source:
        record = plistlib.load(source)
except Exception as error:
    raise SystemExit(f"push_pairing: not a property list: {error}")
if not isinstance(record, dict) or not record:
    raise SystemExit("push_pairing: the pairing file is empty or not a dictionary")
if {"DeviceCertificate", "HostPrivateKey", "RootCertificate"} <= record.keys():
    raise SystemExit("push_pairing: this is a lockdown pairing record; Built-in JIT needs a Remote Pairing "
                     "file (idevice_pair \"Remote pairing\", or pymobiledevice3 remote pair-host)")
for key in ("public_key", "private_key"):
    if not isinstance(record.get(key), bytes) or len(record[key]) != 32:
        raise SystemExit(f"push_pairing: {key} is missing or not a 32-byte Ed25519 key")
identifier = record.get("identifier") or record.get("host_identifier")
if not identifier and "remote_unlock_host_key" in record and len(sys.argv) > 3:
    identifier = sys.argv[3]   # pymobiledevice3 host-initiated record: this computer's host id
if not isinstance(identifier, str) or not identifier:
    raise SystemExit("push_pairing: no host identifier (identifier / host_identifier)")
out = {"public_key": record["public_key"], "private_key": record["private_key"], "identifier": identifier}
alt_irk = record.get("alt_irk", record.get("peer_alt_irk"))
if isinstance(alt_irk, bytes) and len(alt_irk) == 16:
    out["alt_irk"] = alt_irk
source = ("pymobiledevice3 pair-host record" if "host_identifier" in record else
          "pymobiledevice3 lockdown record" if "remote_unlock_host_key" in record else "Remote Pairing file")
fd = os.open(sys.argv[2], os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(fd, "wb") as target:
    plistlib.dump(out, target, fmt=plistlib.FMT_XML)
print(f"push_pairing: {source}, host {identifier}, device alt IRK {'present' if 'alt_irk' in out else 'absent'}")
PY

if [ -z "${USBMUXD_SOCKET_ADDRESS:-}" ] && ss -ltn 2>/dev/null | grep -q '127\.0\.0\.1:27099 '; then
    export USBMUXD_SOCKET_ADDRESS=127.0.0.1:27099
fi
timeout 30 pymobiledevice3 usbmux list 2>/dev/null | grep -q '"ProductType"' || {
    echo "push_pairing: the phone is not reachable; wake and unlock it on the same Wi-Fi, then retry" >&2; exit 1
}

# The folder, so Library/StikJIT/ is created when missing (a lone file into it fails then).
timeout 120 pymobiledevice3 apps push "$bundle" "$stage/StikJIT" "Library"
echo "push_pairing: installed into $bundle at Library/StikJIT/pairingFile.plist"
