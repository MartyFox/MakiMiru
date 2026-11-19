#!/bin/sh
# Preview overlay + keyboard shortcuts (web/main.js, ?ui=1): runs the page
# selftest with the UI enabled, so the real keydown handler is driven —
# 1/2/3 views, R reset, W wireframe, I info, H help, Ctrl+key ignored — and
# the size/triangle overlay text is checked. Also asserts the thumbnailer
# never enables the UI (thumbnails must not show the overlay).
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$DIR/.." && pwd)"

if [ "${MAKIMIRU_TEST_INSTALLED:-0}" = "1" ]; then
    PAGE="$HOME/.local/share/sushi/web/viewer.html"
else
    PAGE="$REPO/web/viewer.html"
fi
[ -f "$PAGE" ] || { echo "FAIL: viewer.html not found at $PAGE" >&2; exit 1; }

export DISPLAY="${DISPLAY:-:0}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

out="$(MAKIMIRU_SELFTEST_QUERY='&ui=1' gjs "$DIR/page-selftest-runner.js" "$PAGE")" || {
    echo "$out" >&2
    echo "FAIL: page selftest with ui=1" >&2
    exit 1
}
echo "$out" | grep -E 'case ui-'
n="$(echo "$out" | grep -c 'case ui-.*: pass')"
[ "$n" -eq 7 ] || { echo "FAIL: expected 7 passing ui cases, got $n" >&2; exit 1; }

grep -q "&ui=1" "$REPO/src/viewers/model.js" ||
    { echo "FAIL: previewer (model.js) no longer enables the UI" >&2; exit 1; }
if grep -q "ui=1" "$REPO/src/makimiru-thumbnailer.in"; then
    echo "FAIL: thumbnailer enables the preview UI — thumbnails would show the overlay" >&2
    exit 1
fi
echo "PASS: test-preview-ui"
