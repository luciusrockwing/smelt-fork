#!/usr/bin/env bash
# Runs on the GitHub Actions runner (ubuntu-24.04-arm). Prepares a world-writable
# /out dir on the host and runs termux-docker with this repo mounted at
# /workspace and that dir mounted at /out. The actual build happens in
# build-in-container.sh.
#
# Env inputs:
#   GITHUB_WORKSPACE     set by Actions; the checked-out repo
#   SMELT_VERSION        optional; forwarded to the container script
#   SMELT_UPSTREAM_REF   optional; forwarded to the container script
#   SMELT_PROFILE        optional; forwarded to the container script
#
# Output:
#   $OUT_HOST/smelt                 the built binary
#   $OUT_HOST/BUILD_INFO            build identity
#   $OUT_HOST/upstream-commit.txt   exact upstream commit built
#
# OUT_HOST is echoed to stdout last so callers can capture it with `tail -n1`.

set -euo pipefail

: "${GITHUB_WORKSPACE:?GITHUB_WORKSPACE must be set}"

# /workspace is effectively read-only for the container's `system` user
# (termux-docker drops privileges regardless of --user), so mount a SECOND
# directory that the runner pre-creates world-writable.
mkdir -p "$GITHUB_WORKSPACE/../out"
OUT_HOST="$(cd "$GITHUB_WORKSPACE/../out" && pwd)"
chmod 0777 "$OUT_HOST"
echo "OUT_HOST=$OUT_HOST" >&2

# termux-docker's entrypoint strips inherited environment when it switches to
# the `system` user, so hand the values over through the writable /out mount.
cat > "$OUT_HOST/build-env.sh" <<EOF
export SMELT_VERSION='${SMELT_VERSION:-}'
export SMELT_UPSTREAM_REF='${SMELT_UPSTREAM_REF:-}'
export SMELT_PROFILE='${SMELT_PROFILE:-dist}'
EOF
chmod 0644 "$OUT_HOST/build-env.sh"

docker run --rm \
  -v "$GITHUB_WORKSPACE:/workspace" \
  -v "$OUT_HOST:/out" \
  -w /workspace \
  termux/termux-docker:aarch64 \
  bash /workspace/termux/ci/build-in-container.sh

echo "$OUT_HOST"
