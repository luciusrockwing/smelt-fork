#!/data/data/com.termux/files/usr/bin/bash
# Package the built binary as a Termux .deb and emit SHA256SUMS.
#
# Usage: SMELT_VERSION=x.y.z package-deb.sh <in-dir> <out-dir>
#
#   <in-dir>   directory holding `smelt` and (optionally) BUILD_INFO,
#              as produced by build-in-container.sh
#   <out-dir>  where to write the .deb
#
# Run on the runner (Ubuntu), not in the Termux container: dpkg-deb on Ubuntu
# defaults to zstd compression, which some Termux bootstraps cannot unpack, so
# compression is pinned to xz explicitly.

set -euo pipefail

IN_DIR="${1:?usage: package-deb.sh <in-dir> <out-dir>}"
OUT_DIR="${2:?usage: package-deb.sh <in-dir> <out-dir>}"

die() { echo "error: $*" >&2; exit 1; }

BIN="$IN_DIR/smelt"
test -f "$BIN" || die "no binary at $BIN"
test -n "${SMELT_VERSION:-}" || die "SMELT_VERSION must be set"

VERSION="${SMELT_VERSION#v}"
DEB="smelt_${VERSION}_aarch64.deb"

mkdir -p "$OUT_DIR"
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT

mkdir -p "$ROOT/DEBIAN"
chmod 0755 "$ROOT"
# mktemp -d makes 0700; dpkg-deb rejects a control dir outside 0755-0775.
chmod 0755 "$ROOT/DEBIAN"

install -Dm0755 "$BIN" "$ROOT/data/data/com.termux/files/usr/bin/smelt"

# Installed-Size is in KiB, per dpkg's convention.
INSTALLED_SIZE="$(du -ks "$ROOT/data" | cut -f1)"

cat > "$ROOT/DEBIAN/control" <<EOF
Package: smelt
Version: $VERSION
Architecture: aarch64
Maintainer: smelt-termux <smelt-termux@users.noreply.github.com>
Installed-Size: $INSTALLED_SIZE
Description: Coding agent TUI (Termux build of upstream smelt)
 Upstream: https://github.com/leonardcser/smelt
 Built for Termux on aarch64-linux-android by smelt-fork.
 No upstream dependency: this is a self-contained Rust binary.
EOF


echo "→ building $DEB"
# -Zxz pins xz: Ubuntu's dpkg-deb defaults to zstd, and a zstd control.tar
# fails on Termux bootstraps whose dpkg was built without libzstd.
dpkg-deb --root-owner-group -Zxz --build "$ROOT" "$OUT_DIR/$DEB"

cp "$IN_DIR/BUILD_INFO" "$OUT_DIR/BUILD_INFO" 2>/dev/null || true

( cd "$OUT_DIR" && sha256sum "$DEB" > SHA256SUMS )
( cd "$OUT_DIR" && sha256sum -c SHA256SUMS )

ls -la "$OUT_DIR"
echo "→ packaged $DEB"
