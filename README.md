# smelt-fork

Termux builds of [smelt](https://github.com/leonardcser/smelt), a coding agent TUI.

Upstream publishes prebuilt binaries for five desktop targets — Linux x86_64/aarch64,
macOS x86_64/aarch64, Windows x86_64. None of them run on Android: they link glibc
or musl, and Android's Bionic loader rejects both. So a Termux user has no way to run
an official smelt release.

This repo builds smelt natively for `aarch64-linux-android` and publishes it as a
`.deb` installable with `dpkg -i`.

## This repo holds no smelt source

It is a delta repository, in the style of
[bd-loser/opencode-bionic](https://github.com/bd-loser/opencode-bionic). Upstream
source is **not** vendored here. Each build clones upstream at a ref pinned in
[`versions.json`](versions.json), applies the patches in [`termux/patches/`](termux/patches/),
and builds the result. The upstream tag is the single source of truth; there is no
merge to keep up to date.

```
versions.json                 pin: upstream smelt version + exact commit
termux/patches/*.patch        the delta
termux/ci/                    fetch, patch, build, package
install.sh                    one-line installer
```

## Why a container and not a cross-compile

The build runs inside `termux/termux-docker:aarch64` on a `ubuntu-24.04-arm` runner.
That runner is already aarch64, so inside the container `rustc`'s host triple *is*
`aarch64-linux-android`. There is no NDK, no cross-linker, and no API-level pinning —
the toolchain is the same one Termux users already have, so a binary built here runs
on a real device without an ABI mismatch.

ARM64 hosted runners are free for public repositories.

## The delta

One patch: `0001-termux-root-reqwest-trust-store-in-platform-ca-bundle.patch`.

On Android, `reqwest` selects `rustls-platform-verifier` as its only available
certificate verifier. That verifier is JVM-backed — it reaches
`GLOBAL.get().expect("Expect rustls-platform-verifier to be initialized")`. A bare
Termux process has no JVM, so the **first HTTPS handshake panics** and takes the agent
down with a message that names neither the provider nor the cause.

The patch adds `smelt_provider::apply_platform_tls`, the identity function on every
platform except Android, where it switches `reqwest` to `tls_certs_only` with the CA
bundle from `$SSL_CERT_FILE`, `$PREFIX/etc/tls/cert.pem`, or the Termux default.
All four `reqwest::Client::builder()` sites route through it. No new dependencies, so
`Cargo.lock` stays valid and `--locked` keeps working.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/luciusrockwing/smelt-fork/main/install.sh | bash
```

Pin a specific release:

```sh
curl -fsSL .../install.sh | SMELT_VERSION=0.5.0-alpha.13 bash
```

Only `aarch64` is built.

## Releasing a new version

1. Update the `smelt` version and `smeltCommit` in `versions.json`. `smeltCommit` is
   what `git ls-remote` reports for that tag; the build aborts if the tag resolves to
   anything else, so a moved upstream tag cannot slip through silently.
2. Refresh the patch against the new tree (`git format-patch` from a clone of that tag
   with the changes applied). Patches are applied with `git am --3way`, so an upstream
   edit near a hunk three-way merges instead of failing outright.
3. Dispatch **release-android** from the Actions tab, or:
   ```sh
   gh workflow run release-android.yml -f version=0.5.0-alpha.14
   ```

There is deliberately **no upstream watcher**. Upstream ships prereleases often, so an
automated poller would spend a full ARM build on every alpha. Dispatch is manual.

Use `upstream_ref` to build a branch or commit instead of the pinned tag; that produces
a `v<version>-termux.<run>` tag so it cannot collide with a release build.

## Layout of a build

| Step | Script |
| --- | --- |
| clone upstream at the pinned ref | `termux/ci/fetch-upstream.sh` |
| apply the delta, drop `rust-toolchain.toml` | `termux/ci/apply-patches.sh` |
| both of the above | `termux/ci/prepare-build-tree.sh` |
| run the container | `termux/ci/build-on-runner.sh` |
| compile inside Termux | `termux/ci/build-in-container.sh` |
| build the `.deb` + `SHA256SUMS` | `termux/ci/package-deb.sh` |

`apply-patches.sh` removes `rust-toolchain.toml` from the build tree. That file is a
rustup-only mechanism, and rustup publishes no `aarch64-linux-android` *host* toolchain
at all, so it can only ever misdirect a toolchain manager. Termux supplies `rustc` and
`cargo` from the `termux-main` repository.

## License

smelt is MIT licensed; see [`LICENSE`](LICENSE). The patches here are distributed under
the same terms.
