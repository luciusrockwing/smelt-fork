#!/data/data/com.termux/files/usr/bin/bash
# Fetch upstream at a pinned ref and apply our delta, producing a ready-to-build
# source tree.
#
# Usage: WORKSPACE=/path/to/repo prepare-build-tree.sh <dest-dir> [ref]

set -euo pipefail

WORKSPACE="${WORKSPACE:-/workspace}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DEST="${1:?usage: prepare-build-tree.sh <dest-dir> [ref]}"
REF="${2:-}"

"$HERE/fetch-upstream.sh" "$DEST" "$REF"
"$HERE/apply-patches.sh" "$DEST"
