#!/bin/sh
# SPEC-010 test 2: the thumbnailer's rendering path (offscreen WebKit +
# its own 'makimiru://' scheme wiring) produces the same framing
# contract already established for the previewer — fillRatio in the
# 0.6-0.9 band SPEC-005's selftest pins, same as what a live preview of
# the same file would show (thumbnail and preview must agree).
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$DIR/.." && pwd)"

# External review (SPEC-010 follow-up): default to the checkout's own
# web/ dir, not a possibly-stale install — same SPEC-009 pattern as
# test-page-selftest.sh/test-framing-selftest.sh. thumbnailer-framing-
# probe.js only ever reads PKGDATADIR/web/..., never touches the
# GResource, so $REPO works directly with no build step.
# MAKIMIRU_TEST_INSTALLED=1 opts into testing the installed prefix.
if [ "${MAKIMIRU_TEST_INSTALLED:-0}" = "1" ]; then
    PKGDATADIR="$HOME/.local/share/sushi"
else
    PKGDATADIR="$REPO"
fi
[ -d "$PKGDATADIR/web" ] || { echo "FAIL: $PKGDATADIR/web not found" >&2; exit 1; }

TMP="${TMPDIR:-/tmp}/makimiru-stl"
mkdir -p "$TMP"
[ -f "$TMP/sphere-20k.stl" ] || python3 "$DIR/make-stl.py" 20000 "$TMP/sphere-20k.stl"

export DISPLAY="${DISPLAY:-:0}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

out="$(gjs "$DIR/thumbnailer-framing-probe.js" "$TMP/sphere-20k.stl" "$PKGDATADIR" stl)" || {
    echo "FAIL: probe errored: $out" >&2
    exit 1
}
echo "bounds: $out"

fill_ratio="$(echo "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["fillRatio"])')"
python3 -c "
fr = $fill_ratio
assert 0.6 <= fr <= 0.9, f'fillRatio {fr} outside the 0.6-0.9 framing contract'
"

echo "PASS: test-thumbnailer-framing-match (fillRatio=$fill_ratio)"
