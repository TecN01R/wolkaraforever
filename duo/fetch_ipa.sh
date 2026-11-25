#!/bin/bash
# Download the newest successful "Duo IPA" workflow build from your GitHub fork and check it.
#
# usage: duo/fetch_ipa.sh [run-id]
#   DUO_REPO   owner/name of the fork (default: this clone's "origin")
#   DUO_BRANCH branch whose runs count (default: duo-baseline)
#   DUO_BUILDS where builds are kept (default: ../builds next to this clone)
#
# Writes $DUO_BUILDS/<commit>/wolkaraforever-duo-unsigned.ipa and points
# $DUO_BUILDS/latest.ipa at it. Nothing is installed; duo/install.sh does that.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
repo=${DUO_REPO:-$(cd "$here" && gh repo view --json nameWithOwner --jq .nameWithOwner)}
branch=${DUO_BRANCH:-duo-baseline}
builds=${DUO_BUILDS:-$(cd "$here/.." && pwd)/builds}
ipa_name=wolkaraforever-duo-unsigned.ipa

if [ -n "${1-}" ]; then
    run=$1
    sha=$(gh run view "$run" -R "$repo" --json headSha --jq .headSha)
else
    read -r run sha < <(gh run list -R "$repo" --workflow duo-ipa.yml --branch "$branch" \
        --status success --limit 1 --json databaseId,headSha --jq '.[0] | "\(.databaseId) \(.headSha)"')
fi
[ -n "${run:-}" ] && [ "$run" != null ] || { echo "fetch_ipa: no successful Duo IPA run on $repo@$branch" >&2; exit 1; }

dest="$builds/${sha:0:12}"
mkdir -p "$dest"
if [ ! -f "$dest/$ipa_name" ]; then
    echo "fetch_ipa: downloading run $run (commit ${sha:0:12}) from $repo"
    work=$(mktemp -d "$builds/.download.XXXXXX")
    trap 'rm -rf "$work"' EXIT
    gh run download "$run" -R "$repo" -n wolkaraforever-duo-ipa -D "$work"
    mv "$work"/* "$dest"/
fi

# The checksum the runner wrote, against the file we hold.
( cd "$dest" && sha256sum -c "$ipa_name.sha256" )

# Shape checks that need no macOS tools: one app under Payload/, no app extension, no profile.
listing=$(unzip -Z1 "$dest/$ipa_name")
apps=$(printf '%s\n' "$listing" | grep -E '^Payload/[^/]+\.app/$' | wc -l)
[ "$apps" -eq 1 ] || { echo "fetch_ipa: expected one app in Payload/, found $apps" >&2; exit 1; }
! printf '%s\n' "$listing" | grep -q '\.appex/' || { echo "fetch_ipa: unexpected app extension" >&2; exit 1; }
! printf '%s\n' "$listing" | grep -q 'embedded\.mobileprovision$' || { echo "fetch_ipa: unexpected provisioning profile" >&2; exit 1; }
printf '%s\n' "$listing" | grep -q 'CompatibilityRootCertificates\.plist$' ||
    { echo "fetch_ipa: no root certificates; Battle.net login would fail (BLZ51900003)" >&2; exit 1; }

# Bundle identifier and version, read as data (the archive is untrusted input).
app=$(printf '%s\n' "$listing" | grep -E '^Payload/[^/]+\.app/Info\.plist$' | head -1)
unzip -p "$dest/$ipa_name" "$app" | python3 -I -c '
import plistlib, sys
info = plistlib.loads(sys.stdin.buffer.read())
for key in ("CFBundleIdentifier", "CFBundleDisplayName", "CFBundleShortVersionString", "CFBundleVersion", "MinimumOSVersion"):
    print(f"  {key}: {info.get(key)}")'

ln -sfn "${sha:0:12}/$ipa_name" "$builds/latest.ipa"
echo "fetch_ipa: ready: $builds/latest.ipa -> ${sha:0:12}/$ipa_name"
