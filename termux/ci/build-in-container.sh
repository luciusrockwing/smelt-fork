#!/data/data/com.termux/files/usr/bin/bash
# Runs INSIDE termux-docker (aarch64). Fetches upstream smelt at the ref pinned
# by versions.json, applies our delta, builds with the Termux toolchain, and
# hands the binary to package-deb.sh.
#
# Mounts expected:
#   /workspace  = this repo (read-only in practice)
#   /out        = writable host dir for the artifact handoff
#
# Env inputs (read from /out/build-env.sh, written by build-on-runner.sh):
#   SMELT_VERSION      version to stamp and release as; default comes from
#                      versions.json
#   SMELT_UPSTREAM_REF optional; build this branch/commit instead of the pinned tag
#   SMELT_PROFILE      cargo profile; default dist

set -euo pipefail

export WORKSPACE="${WORKSPACE:-/workspace}"

if [ -f /out/build-env.sh ]; then
  # shellcheck disable=SC1091
  . /out/build-env.sh
fi
SMELT_VERSION="${SMELT_VERSION:-}"
SMELT_UPSTREAM_REF="${SMELT_UPSTREAM_REF:-}"
SMELT_PROFILE="${SMELT_PROFILE:-dist}"
export SMELT_UPSTREAM_REF

die() { echo "error: $*" >&2; exit 1; }

echo "=== diag ==="
id || true
echo "HOME=$HOME PREFIX=${PREFIX:-unset}"
mount | grep -E "workspace|overlay|/out" || true
(touch /out/.write_test && rm -f /out/.write_test && echo "/out: WRITABLE") \
  || die "/out is not writable"
echo "==========="

# Pin the canonical mirror so package versions stay consistent across runs.
echo "deb https://packages.termux.dev/apt/termux-main stable main" \
  > "${PREFIX:-/data/data/com.termux/files/usr}/etc/apt/sources.list"
apt update -y
# git + ca-certificates to clone upstream, python to read versions.json, the
# clang/lld/cmake/ninja toolchain that rustc and the native build scripts
# (aws-lc-sys, libsqlite3-sys, mlua-sys, onig_sys, zstd-sys) need.
apt install -y git ca-certificates python clang lld cmake make ninja pkg-config

# The whole point of building in here rather than cross-compiling: the host
# triple is already the target triple, so there is no NDK and no cross-linker.
echo "=== toolchain ==="
rustc --version --verbose
case "$(rustc -vV | sed -n 's/^host: //p')" in
  aarch64-linux-android) ;;
  *) die "expected host aarch64-linux-android, got $(rustc -vV | sed -n 's/^host: //p')" ;;
esac

if [ -z "$SMELT_VERSION" ]; then
  SMELT_VERSION="$(python3 -c \
    "import json;print(json.load(open('$WORKSPACE/versions.json'))['smelt'])")"
fi
echo "building smelt $SMELT_VERSION (profile=$SMELT_PROFILE, ref=${SMELT_UPSTREAM_REF:-<pinned tag>})"

BUILD_ROOT="$HOME/smelt"
"$WORKSPACE/termux/ci/prepare-build-tree.sh" "$BUILD_ROOT" "$SMELT_UPSTREAM_REF"
cd "$BUILD_ROOT"

# CI owns versioning per RELEASE.md. prepare-release materialises the tag
# version across the workspace manifests; SMELT_RELEASE_TAG is the documented
# override crates/tui/build.rs reads for the build identity.
cargo xtask prepare-release "$SMELT_VERSION"

# Termux rust is built with its own LLVM, so a fat-LTO + panic=abort release
# is heavy. Keep codegen jobs bounded; the ARM runner has headroom but this
# also keeps the shared arm64 runner polite.
CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-4}"
export CARGO_BUILD_JOBS

echo "=== build ==="
SMELT_RELEASE_TAG="v$SMELT_VERSION" \
  cargo build --locked --profile "$SMELT_PROFILE" --bin smelt

BIN="$BUILD_ROOT/target/$SMELT_PROFILE/smelt"
test -f "$BIN" || die "no binary at $BIN"
chmod 0755 "$BIN"
ls -la "$BIN"

# ELF sanity without pulling in binutils: e_ident at 0, e_machine at 0x12.
MAGIC="$(head -c 4 "$BIN" | od -An -tx1 | tr -d ' \n')"
[ "$MAGIC" = "7f454c46" ] || die "not an ELF file (magic=$MAGIC)"
MACHINE="$(dd if="$BIN" bs=1 skip=18 count=2 2>/dev/null | od -An -tx1 | tr -d ' \n')"
[ "$MACHINE" = "b700" ] || die "e_machine is not AArch64 (got $MACHINE)"

# This container IS aarch64, so unlike the desktop release matrix we can
# actually execute the artifact here.
echo "=== smoke ==="
"$BIN" --version
test -n "$("$BIN" --version 2>&1)" || die "smelt --version produced no output"

echo "=== publishing artifact ==="
cp "$BIN" /out/smelt
chmod 0755 /out/smelt
{
  echo "smelt:        $SMELT_VERSION"
  echo "upstream:     ${SMELT_UPSTREAM_REF:-v$SMELT_VERSION}"
  echo "upstream_ref: $(cat /out/upstream-commit.txt 2>/dev/null || echo unknown)"
  echo "profile:      $SMELT_PROFILE"
  echo "host:         $(rustc -vV | sed -n 's/^host: //p')"
  echo "rustc:        $(rustc --version)"
  echo "built:        $(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > /out/BUILD_INFO
ls -la /out/
echo "=== done ==="
