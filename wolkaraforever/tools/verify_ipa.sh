#!/bin/bash
# Verify that an unsigned External-JIT .ipa is what a source build of this tree produces: the
# same public root certificates (without them the client cannot validate Battle.net and every
# login is refused), the same emulated runtime, External JIT preselected, no profile and no
# signing team. Run it before a package is handed to a sideloader or published.
#
# usage: wolkaraforever/tools/verify_ipa.sh <wolkaraforever-unsigned.ipa> [report-path]
set -euo pipefail
cd "$(dirname "$0")/../.."

ipa=${1:-}
report=${2:-}
[ -n "$ipa" ] && [ -f "$ipa" ] || { echo "usage: wolkaraforever/tools/verify_ipa.sh <ipa> [report-path]" >&2; exit 2; }
[ "$#" -le 2 ] || { echo "verify_ipa: too many arguments" >&2; exit 2; }
case "$ipa" in /*) ;; *) ipa="$PWD/$ipa";; esac
if [ -z "$report" ]; then
    report="${ipa%.ipa}.verification.txt"
elif [[ "$report" != /* ]]; then
    report="$PWD/$report"
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
unzip -tqq "$ipa"
unzip -qq "$ipa" -d "$tmp"

app="$tmp/Payload/TolkaraDiagnostics.app"
[ -d "$app" ] || { echo "verify_ipa: Payload/TolkaraDiagnostics.app is missing" >&2; exit 1; }
[ "$(find "$tmp/Payload" -mindepth 1 -maxdepth 1 -type d -name '*.app' | wc -l | tr -d ' ')" = 1 ] || {
    echo "verify_ipa: expected exactly one app under Payload" >&2; exit 1
}
[ ! -e "$app/embedded.mobileprovision" ] || { echo "verify_ipa: provisioning profile present" >&2; exit 1; }
# One extension, and only this one: the Built-in JIT helper (StikJIT), on the extension point it
# uses as a vehicle, with StikJIT's framework and universal script inside it.
helper="$app/PlugIns/WolkaraJITHelper.appex"
[ -d "$helper" ] || { echo "verify_ipa: the Built-in JIT helper (PlugIns/WolkaraJITHelper.appex) is missing" >&2; exit 1; }
[ "$(find "$app/PlugIns" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" = 1 ] || {
    echo "verify_ipa: the only app extension allowed is the Built-in JIT helper" >&2; exit 1
}
[ ! -e "$helper/embedded.mobileprovision" ] || { echo "verify_ipa: the JIT helper carries a provisioning profile" >&2; exit 1; }
[ "$(plutil -extract NSExtension.NSExtensionPointIdentifier raw "$helper/Info.plist")" = com.apple.ar.viewer ] || {
    echo "verify_ipa: the JIT helper is not on its com.apple.ar.viewer vehicle extension point" >&2; exit 1
}
stikjit="$helper/Frameworks/StikJIT.framework"
[ -f "$stikjit/StikJIT" ] && [ -f "$stikjit/universal.js" ] || {
    echo "verify_ipa: the JIT helper does not carry StikJIT.framework with universal.js" >&2; exit 1
}
stikjit_version=$(plutil -extract CFBundleShortVersionString raw "$stikjit/Info.plist")
# StikJIT is MPL-2.0: the binary carries its licence and where its source is.
for notice in StikJIT-LICENSE.txt StikJIT-NOTICE.txt; do
    [ -f "$helper/$notice" ] || { echo "verify_ipa: the JIT helper lacks $notice (StikJIT's MPL-2.0 notice)" >&2; exit 1; }
done

# The one build input a reduced package is most likely to be missing, and the one that decides
# whether any login can work: the public root certificates a source build exports from the
# builder's Mac. Absent, the app cannot answer the client's request for macOS's system roots.
roots="$app/CompatibilityRootCertificates.plist"
[ -f "$roots" ] || {
    echo "verify_ipa: no system root certificates: this package is not what a source build produces," >&2
    echo "  and the client cannot validate Battle.net without them (login is refused)." >&2
    exit 1
}
roots_count=$(python3 - "$roots" <<'PY'
import plistlib, sys
with open(sys.argv[1], "rb") as source:
    anchors = plistlib.load(source)
if not isinstance(anchors, list) or not anchors:
    raise SystemExit("verify_ipa: the system root certificate list is empty or not a list")
if not all(isinstance(anchor, bytes) and anchor for anchor in anchors):
    raise SystemExit("verify_ipa: the system root certificate list holds something that is not a certificate")
print(len(anchors))
PY
)

mode=$(plutil -extract TolkaraPreselectedExecutionMode raw "$app/Info.plist")
runtime=$(plutil -extract TolkaraGuestRuntime raw "$app/Info.plist")
[ "$mode" = external-jit ] || { echo "verify_ipa: expected external-jit, got $mode" >&2; exit 1; }
[ "$runtime" = emulated ] || { echo "verify_ipa: expected emulated guest runtime, got $runtime" >&2; exit 1; }
# Game Mode: what raises the memory limit once iOS turns it on (Info.plist, launcher).
[ "$(plutil -extract LSApplicationCategoryType raw "$app/Info.plist" 2>/dev/null)" = public.app-category.games ] &&
[ "$(plutil -extract GCSupportsGameMode raw "$app/Info.plist" 2>/dev/null)" = true ] || {
    echo "verify_ipa: the app does not declare iOS Game Mode (games category and GCSupportsGameMode)" >&2; exit 1
}

entitlements="$tmp/entitlements.plist"
codesign -d --entitlements :- "$app" > "$entitlements" 2>/dev/null
python3 - "$entitlements" <<'PY'
import plistlib, sys
with open(sys.argv[1], "rb") as source:
    entitlements = plistlib.load(source)
for key in ("com.apple.developer.kernel.increased-memory-limit",
            "com.apple.developer.kernel.extended-virtual-addressing"):
    if entitlements.get(key) is not True:
        raise SystemExit("verify_ipa: missing entitlement " + key)
PY

signature=$(codesign -dvv "$app" 2>&1) || { echo "verify_ipa: app signature is invalid" >&2; exit 1; }
printf '%s\n' "$signature" | grep -qx 'TeamIdentifier=not set' || {
    echo "verify_ipa: IPA carries a signing team" >&2; exit 1
}

sha=$(shasum -a 256 "$ipa" | awk '{print $1}')
revision=$(git rev-parse HEAD)
mkdir -p "$(dirname "$report")"
{
    echo "IPA: $ipa"
    echo "SHA256: $sha"
    echo "Source revision: $revision"
    echo "Bundle: TolkaraDiagnostics.app"
    echo "Execution mode: $mode"
    echo "Guest runtime: $runtime"
    echo "Profile: absent"
    echo "Signing team: absent"
    echo "System root certificates: present ($roots_count)"
    echo "Entitlements: increased-memory-limit, extended-virtual-addressing"
    echo "Built-in JIT helper: WolkaraJITHelper.appex, StikJIT $stikjit_version"
    echo "iOS Game Mode: declared (games category, GCSupportsGameMode)"
} > "$report"
echo "verify_ipa: PASS ($report)"
