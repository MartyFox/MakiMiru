#!/bin/sh
# SPEC-004 test 3: viewer.html?selftest=1 loads an embedded tiny STL and
# asserts bounding box + camera framing (FR-3) inside the page, reporting
# selftest-pass/fail via the script message handler.
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$DIR/.." && pwd)"

# SPEC-009 (external review, Low): default to the checkout, not the
# installed copy — a stale install could otherwise pass tests that don't
# reflect the current source. Set KAITEN_TEST_INSTALLED=1 to
# deliberately test the installed prefix instead.
if [ "${KAITEN_TEST_INSTALLED:-0}" = "1" ]; then
    PAGE="$HOME/.local/share/sushi/web/viewer.html"
else
    PAGE="$REPO/web/viewer.html"
fi
[ -f "$PAGE" ] || { echo "viewer.html not found at $PAGE — run scripts/install-user.sh or unset KAITEN_TEST_INSTALLED" >&2; exit 1; }

# Ensure a display when run over SSH into a session machine.
export DISPLAY="${DISPLAY:-:0}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

out="$(gjs "$DIR/page-selftest-runner.js" "$PAGE")" || {
    echo "FAIL: $out" >&2
    exit 1
}
echo "$out"
echo "PASS: test-page-selftest"
