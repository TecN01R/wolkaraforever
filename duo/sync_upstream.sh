#!/bin/bash
# Bring upstream WolkaraForever (jklock/wolkaraforever, main) into this fork's duo-baseline.
#
# usage: duo/sync_upstream.sh [--check] [--no-push]
#   --check    report what a sync would do (new commits, conflicts, whether our patches still
#              apply), change nothing
#   --no-push  merge and verify locally, but don't push
#
# It merges (never rebases: people following the guide `git pull`), regenerates the generated
# agent catalog (docs/agent/catalog, which both sides change on every commit) instead of
# hand-merging it, and refuses to finish when any other file conflicts. Before pushing, it
# proves the full patch series, upstream's plus ours (09xx), still applies to a fresh copy of
# the platform tree, and that the docs checks pass. A push to duo-baseline then builds and
# publishes the app through .github/workflows/duo-ipa.yml.
#
# The weekly .github/workflows/upstream-sync.yml does the same on GitHub when it can. This is
# for when it can't: a conflict, or upstream commits that change workflow files (GitHub doesn't
# let the Actions token push those).
set -euo pipefail
cd "$(dirname "$0")/.."
check=0 push=1
for arg in "$@"; do
    case $arg in
        --check) check=1 ;;
        --no-push) push=0 ;;
        *) echo "usage: duo/sync_upstream.sh [--check] [--no-push]" >&2; exit 2 ;;
    esac
done
[ "$(git branch --show-current)" = duo-baseline ] || { echo "sync: check out duo-baseline first" >&2; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "sync: the working tree has uncommitted changes" >&2; exit 1; }
git remote get-url upstream >/dev/null 2>&1 ||
    git remote add upstream https://github.com/jklock/wolkaraforever.git
git fetch -q upstream main
git fetch -q origin duo-baseline
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/duo-baseline)" ] ||
    { echo "sync: local duo-baseline differs from origin; pull or push first" >&2; exit 1; }

new=$(git rev-list --count HEAD..upstream/main)
if [ "$new" = 0 ]; then echo "sync: already up to date with upstream"; exit 0; fi
echo "sync: upstream has $new new commit(s):"
git log --oneline HEAD..upstream/main | sed 's/^/  /'
touches=$(git diff --name-only HEAD...upstream/main | grep '^\.github/workflows/' || true)
[ -z "$touches" ] || echo "sync: they change workflow files: $(echo $touches)"

before=$(git rev-parse HEAD)
undo() { git merge --abort 2>/dev/null || git reset -q --hard "$before"; }
if ! git merge -q --no-edit upstream/main >/dev/null 2>&1; then
    other=$(git diff --name-only --diff-filter=U | grep -v '^docs/agent/catalog/' || true)
    if [ -n "$other" ]; then
        echo "sync: conflicts to resolve by hand:"; echo "$other" | sed 's/^/  /'
        undo; exit 1
    fi
    git checkout -q --ours -- docs/agent/catalog/
fi
python3 wolkaraforever/tools/generate_agent_docs.py >/dev/null
git add -A docs/agent/catalog
git diff --cached --quiet || git commit -q --no-edit 2>/dev/null || git commit -q -m "Merge upstream/main into duo-baseline"

# The patch series still applies to a fresh platform tree (no Xcode needed).
tree=$(mktemp -d "${TMPDIR:-/tmp}/sync-platform.XXXXXX")
trap 'rm -rf "$tree"' EXIT
git archive HEAD:platform | tar -x -C "$tree"
if ! wolkaraforever/tools/apply.sh "$tree" >"$tree.log" 2>&1; then
    echo "sync: the patch series no longer applies:"; tail -5 "$tree.log" | sed 's/^/  /'
    rm -f "$tree.log"; undo; exit 1
fi
rm -f "$tree.log"
wolkaraforever/tools/check_docs.sh >/dev/null || { echo "sync: docs checks fail" >&2; undo; exit 1; }
echo "sync: merged; patches apply; docs checks pass"

if [ "$check" = 1 ]; then undo; echo "sync: --check, nothing kept"; exit 0; fi
if [ "$push" = 1 ]; then
    git push -q origin duo-baseline
    echo "sync: pushed; the Duo IPA workflow builds and publishes it"
else
    echo "sync: not pushed (--no-push); git push origin duo-baseline when ready"
fi
