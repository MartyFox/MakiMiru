#!/bin/sh
# SPEC-009 test 2, strengthened per external review: the original version
# only asked this host's live `gio info` for cube.obj's content-type —
# since this host already resolves .obj -> model/obj by default, that
# passed regardless of whether our override or the code-level fallback
# actually do anything. Two real checks now:
#   1. mime-fallback-harness.js exercises the actual dispatch code
#      (mimeHandler.js's getKlass()) with a *forced* mime value of
#      'text/plain' — deterministic, independent of host mime-db state,
#      proves the documented ambiguity risk is genuinely handled.
#   2. The live gio/mime-override-file checks below stay as a secondary,
#      host-dependent sanity check that the installed override package
#      is present and the cache reflects it — useful, but explicitly not
#      proof of the fallback code path by itself.
# SPEC-011: the dev per-user install (scripts/install-user.sh) and the
# packaged .deb install put the GResource/mime-override at different
# paths (private prefix under /opt/kaiten/previewer vs $HOME/.local)
# — override via env vars to run this same test against either without
# duplicating it. Defaults match the dev workflow, unchanged.
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"
PREFIX="${KAITEN_TEST_PREFIX:-$HOME/.local}"
LIBDIR="${KAITEN_TEST_LIBDIR:-$HOME/.local/lib/$(uname -m)-linux-gnu}"
PKGDATADIR="${KAITEN_TEST_PKGDATADIR:-$PREFIX/share/sushi}"
MIME_DIR="${KAITEN_TEST_MIME_DIR:-$HOME/.local/share/mime/packages}"

[ -f "$PKGDATADIR/org.gnome.NautilusPreviewer.src.gresource" ] || {
    echo "FAIL: $PKGDATADIR/org.gnome.NautilusPreviewer.src.gresource not found — run scripts/install-user.sh (or set KAITEN_TEST_* for a .deb install)" >&2
    exit 1
}

echo "--- 1. dispatch code path (host-independent) ---"
gjs "$DIR/mime-fallback-harness.js" "$PREFIX" "$LIBDIR"

echo "--- 2. installed override + live host resolution (sanity check only) ---"
MIME_XML="$MIME_DIR/org.gnome.NautilusPreviewer-model.xml"
[ -f "$MIME_XML" ] || {
    echo "FAIL: $MIME_XML not installed — run scripts/install-user.sh" >&2
    exit 1
}
grep -q 'model/obj' "$MIME_XML" || {
    echo "FAIL: $MIME_XML does not declare model/obj" >&2
    exit 1
}

TMP="${TMPDIR:-/tmp}/kaiten-3mf-obj"
mkdir -p "$TMP"
[ -f "$TMP/cube.obj" ] || python3 "$DIR/make-obj.py" "$TMP/cube.obj"

content_type="$(gio info -a standard::content-type "$TMP/cube.obj" | sed -n 's/.*standard::content-type: //p')"
echo "observed content-type on this host: $content_type"
if [ "$content_type" != "model/obj" ]; then
    echo "NOTE: host resolves .obj to $content_type, not model/obj directly — this is exactly the case the dispatch-code fallback (check 1) exists for, not a failure of this check by itself."
fi

echo "PASS: test-obj-mime-override"
