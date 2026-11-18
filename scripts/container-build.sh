#!/bin/sh
# Build the fork inside an Ubuntu 24.04 container (no host apt changes) and
# stage the install tree to build-install/ for install-user.sh to sync.
set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE=makimiru-build

podman build -q -t "$IMAGE" -f "$REPO/scripts/Containerfile.build" "$REPO/scripts"

PREFIX="$HOME/.local"

podman run --rm --userns=keep-id -v "$REPO:/src:rw" -e PREFIX="$PREFIX" \
    "$IMAGE" sh -c '
    set -eu
    meson setup build --prefix="$PREFIX" --libexecdir libexec --reconfigure >/dev/null
    meson compile -C build
    rm -rf build-install
    meson install -C build --destdir /src/build-install >/dev/null
'

echo "Staged install tree: $REPO/build-install$PREFIX"
