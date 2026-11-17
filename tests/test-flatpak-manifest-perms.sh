#!/bin/sh
# SPEC-007 test 4 (static): the model viewer never loads remote content
# (bundled assets + the one selected local file only), so the Flatpak
# manifest must not request network access.
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$DIR/.." && pwd)"
MANIFEST="$REPO/flatpak/org.gnome.NautilusPreviewer.json"

[ -f "$MANIFEST" ] || { echo "FAIL: $MANIFEST not found" >&2; exit 1; }

if grep -n -- '--share=network' "$MANIFEST"; then
    echo "FAIL: --share=network found in $MANIFEST" >&2
    exit 1
fi

echo "PASS: test-flatpak-manifest-perms"
