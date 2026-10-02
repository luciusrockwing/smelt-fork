#!/data/data/com.termux/files/usr/bin/bash
# Clone upstream smelt at a known-good ref into a build tree.
#
# Usage: WORKSPACE=/path/to/repo fetch-upstream.sh <dest-dir> [ref]
#
# Ref defaults to the tag implied by versions.json. Pass a branch or commit to
# build something other than a release.
#
# Not a shallow clone on purpose: crates/tui/build.rs shells out to
# `git describe --tags --long` to stamp the build identity, and a depth-1
# clone of a tag carries only that one tag. Keeping history also lets
# `git am --3way` fall back on blobs when a hunk does not apply cleanly.

set -euo pipefail

WORKSPACE="${WORKSPACE:-/workspace}"
DEST="${1:?usage: fetch-upstream.sh <dest-dir> [ref]}"
REF="${2:-}"

pinned() {
  python3 -c "import json;print(json.load(open('$WORKSPACE/versions.json'))['$1'])"
}

if [ -z "$REF" ]; then
  REF="v$(pinned smelt)"
fi

echo "→ fetching upstream smelt $REF"
rm -rf "$DEST"
# Shallow by design. crates/tui/build.rs runs `git describe --tags`, and a
# depth-1 clone of a tag still answers that correctly because it carries the
# tag itself. `git am --3way` can still find pre-image blobs, because for a
# patch generated against this ref they *are* the checked-out tree. Cloning
# the full history costs minutes and buys nothing here.
#
# A raw commit SHA cannot go through `clone -b`, so that case uses init+fetch.
case "$REF" in
  [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f])
    git init -q "$DEST"
    cd "$DEST"
    git remote add origin https://github.com/leonardcser/smelt.git
    git fetch --depth 1 --quiet origin "$REF"
    git checkout --detach --quiet FETCH_HEAD
    ;;
  *)
    git clone --depth 1 --branch "$REF" --quiet https://github.com/leonardcser/smelt.git "$DEST"
    ;;
esac
cd "$DEST"

# Record the exact commit so the release job can print it and so a moved tag
# is detectable rather than silent.
RESOLVED="$(git rev-parse HEAD)"
PINNED="$(pinned smeltCommit 2>/dev/null || true)"
echo "→ upstream $REF = $RESOLVED"
if [ -n "$PINNED" ] && [ "$RESOLVED" != "$PINNED" ]; then
  echo "error: tag $REF resolved to $RESOLVED but versions.json pins $PINNED" >&2
  echo "       upstream may have moved the tag; update versions.json deliberately" >&2
  exit 1
fi

# Only meaningful inside the container; skipped for local verification runs.
if [ -d /out ] && [ -w /out ]; then
  echo "$RESOLVED" > /out/upstream-commit.txt
fi
