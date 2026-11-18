#!/bin/sh
# SPEC-007 follow-up (external review): live integration test for the
# 'makimiru://' scheme handler, not just static grep. Loads the real
# installed ModelRenderer via its actual GResource and drives real
# page-side fetch() calls attempting path traversal and reserved-path
# override, asserting none of them can read an arbitrary host file.
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"

# Deliberately the installed copy, not the checkout (unlike SPEC-009's
# checkout-vs-install fix elsewhere): model.js only exists as loose
# source in the checkout — it ships compiled into the GResource, which
# only exists post-install. This test's whole point is exercising the
# real installed/shipped scheme handler. SPEC-011: override for a .deb
# install, whose GResource lives under a private prefix instead of
# $HOME/.local — default matches the dev workflow, unchanged.
PKGDATADIR="${MAKIMIRU_TEST_PKGDATADIR:-$HOME/.local/share/sushi}"
[ -f "$PKGDATADIR/org.gnome.NautilusPreviewer.src.gresource" ] || {
    echo "FAIL: $PKGDATADIR/org.gnome.NautilusPreviewer.src.gresource not found — run scripts/install-user.sh" >&2
    exit 1
}

TMP="${TMPDIR:-/tmp}/makimiru-stl"
mkdir -p "$TMP"
[ -f "$TMP/sphere-ascii.stl" ] || python3 "$DIR/make-stl.py" 500 "$TMP/sphere-ascii.stl" --ascii

export DISPLAY="${DISPLAY:-:0}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

out="$(gjs "$DIR/uri-scheme-scope-harness.js" "$PKGDATADIR" "$TMP/sphere-ascii.stl")" || {
    echo "$out"
    echo "FAIL: uri-scheme-scope-harness reported a leak or error" >&2
    exit 1
}
echo "$out"
echo "PASS: test-uri-scheme-scope"
