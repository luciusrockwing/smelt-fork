#!/data/data/com.termux/files/usr/bin/bash
# Apply our delta to a freshly fetched upstream tree.
#
# Usage: WORKSPACE=/path/to/repo apply-patches.sh <build-tree>
#
# Patches are plain `git diff` output, applied with `git apply --3way` so an
# upstream edit near one of our hunks falls back to a three-way merge instead
# of failing outright. A conflict aborts the release rather than producing a
# half-patched build. Regenerate the patches with refresh-patches.sh.

set -euo pipefail

WORKSPACE="${WORKSPACE:-/workspace}"
TREE="${1:?usage: apply-patches.sh <build-tree>}"

die() { echo "error: $*" >&2; exit 1; }

cd "$TREE"

shopt -s nullglob
PATCHES=("$WORKSPACE"/termux/patches/*.patch)
shopt -u nullglob

if [ "${#PATCHES[@]}" -eq 0 ]; then
  echo "→ no patches in $WORKSPACE/termux/patches, nothing to apply"
else
  for patch in "${PATCHES[@]}"; do
    echo "→ applying $(basename "$patch")"
    git apply --3way "$patch" \
      || die "$(basename "$patch") did not apply; refresh it against this ref"
  done
  echo "→ applied ${#PATCHES[@]} patch(es)"
fi

# Termux installs rustc/cargo from the termux-main repository. The
# rust-toolchain.toml in this tree is a rustup-only mechanism and pins a
# channel whose aarch64-linux-android *host* toolchain rustup does not
# publish at all, so it can only ever misdirect a toolchain manager.
if [ -f rust-toolchain.toml ]; then
  echo "→ removing rust-toolchain.toml (rustup-only pin; Termux provides the toolchain)"
  rm -f rust-toolchain.toml
fi

echo "→ tree is $(git rev-parse --short HEAD) + delta"
