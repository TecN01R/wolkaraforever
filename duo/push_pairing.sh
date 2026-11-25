#!/bin/bash
# Copy a Remote Pairing file into WolkaraForever's private storage on the phone, where Built-in
# JIT reads it: Library/StikJIT/pairingFile.plist inside the app's own container (not the
# Files-visible Documents folder). The file never leaves this computer and the phone.
#
# usage: duo/push_pairing.sh                 make the pairing and copy it in (the usual way)
#        duo/push_pairing.sh <pairing.plist>  copy in a pairing file you already have
#
#   With no file: runs `pymobiledevice3 lockdown remotepairing --pair` over the connection the
#   phone already trusts (USB, or netmuxd). That is promptless, does nothing when this computer
#   is already paired, and leaves the record in ~/.local/share/pymobiledevice3/remote_<UDID>.plist,
#   which is then converted to StikJIT's format and copied in.
#   A file can also be an idevice_pair "Remote pairing" file, or the record
#   `pymobiledevice3 remote pair-host` writes. A lockdown pairing record (the kind usbmuxd keeps
#   in /var/lib/lockdown) is refused: StikJIT 2.x needs the Remote Pairing kind.
#   DUO_BUNDLE_ID  the installed app's identifier (default: the one duo/install.sh installs)
#   DUO_XTOOL      the xtool that installed it (default: as duo/install.sh picks it)
#   USBMUXD_SOCKET_ADDRESS  as in duo/install.sh (default: a netmuxd on :27099 if up, else USB)
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
pairing=${1:-}
[ -z "$pairing" ] || [ -f "$pairing" ] || { echo "usage: duo/push_pairing.sh [pairing-file.plist]" >&2; exit 2; }
xtool_bin=${DUO_XTOOL:-}
if [ -z "$xtool_bin" ]; then
    xtool_bin=xtool
    for candidate in "$(cd "$here/.." && pwd)/tools/xtool-duo" \
                     "$(cd "$here/.." && pwd)/tools/xtool-duo-$(uname -m).AppImage"; do
        [ -x "$candidate" ] && { xtool_bin=$candidate; break; }
    done
fi
bundle=${DUO_BUNDLE_ID:-XTL-$("$xtool_bin" auth status 2>/dev/null | sed -n 's/^- Team ID: //p').local.wolkaraforever.duo}
case "$bundle" in XTL-.*) echo "push_pairing: cannot tell the team ID (is xtool logged in?); set DUO_BUNDLE_ID" >&2; exit 1;; esac

if [ -z "${USBMUXD_SOCKET_ADDRESS:-}" ] && ss -ltn 2>/dev/null | grep -q '127\.0\.0\.1:27099 '; then
    export USBMUXD_SOCKET_ADDRESS=127.0.0.1:27099
fi
udid=$(timeout 30 pymobiledevice3 usbmux list 2>/dev/null | python3 -I -c '
import json, sys
try: devices = json.load(sys.stdin)
except Exception: devices = []
ids = sorted({d.get("UniqueDeviceID") or d.get("Identifier") or "" for d in devices} - {""})
print(ids[0] if len(ids) == 1 else "")' || true)
[ -n "$udid" ] || {
    echo "push_pairing: the phone is not reachable (or more than one is); connect it by USB, unlock it, retry" >&2; exit 1
}
if [ -z "$pairing" ]; then
    echo "push_pairing: pairing this computer with the phone for JIT (no prompt; skipped if already paired)"
    timeout 120 pymobiledevice3 lockdown remotepairing --pair >/dev/null
    pairing=${XDG_DATA_HOME:-$HOME/.local/share}/pymobiledevice3/remote_$udid.plist
    [ -f "$pairing" ] || { echo "push_pairing: no pairing record at $pairing" >&2; exit 1; }
fi

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

# The folder, so Library/StikJIT/ is created when missing (a lone file into it fails then).
timeout 120 pymobiledevice3 apps push "$bundle" "$stage/StikJIT" "Library"
echo "push_pairing: installed into $bundle at Library/StikJIT/pairingFile.plist"
