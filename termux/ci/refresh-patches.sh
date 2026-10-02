#!/data/data/com.termux/files/usr/bin/bash
# Regenerate termux/patches/ against a given upstream ref, from a working tree
# that already contains the changes.
#
# Usage: refresh-patches.sh <build-tree> [base-ref]
#
#   <build-tree>  a clone of upstream with our changes applied but uncommitted
#   [base-ref]   what the patch applies against; default HEAD
#
# This is a maintainer tool: bump versions.json, apply the delta to a fresh
# tree by hand, then run this to regenerate the patches. The CI build never
# calls it — apply-patches.sh is the consumer.

set -euo pipefail

WORKSPACE="${WORKSPACE:-/workspace}"
TREE="${1:?usage: refresh-patches.sh <build-tree> [base-ref]}"
BASE="${2:-HEAD}"

die() { echo "error: $*" >&2; exit 1; }

cd "$TREE"
git rev-parse --git-dir >/dev/null 2>&1 || die "$TREE is not a git checkout"
BASE_COMMIT="$(git rev-parse "$BASE")"
[ -n "$(git status --porcelain)" ] || die "$TREE has no uncommitted changes"

PATCH_DIR="$WORKSPACE/termux/patches"
mkdir -p "$PATCH_DIR"

# A patch whose base is the upstream commit it was generated from only applies
# where that code is still identical, so record the base alongside it.
echo "→ generating patches against $BASE_COMMIT"
git add -A
git diff --cached --binary "$BASE_COMMIT" > "$PATCH_DIR/0001-termux-root-reqwest-trust-store-in-platform-ca-bundle.patch"

cat > "$PATCH_DIR/BASE" <<EOF
$BASE_COMMIT
EOF

echo "→ wrote:"
ls -la "$PATCH_DIR"
echo "→ changed files:"
git diff --cached --name-only "$BASE_COMMIT"
echo
echo "Review the patch, then commit both files."
