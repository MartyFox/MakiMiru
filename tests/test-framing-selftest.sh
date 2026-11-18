#!/bin/sh
# SPEC-005 test 2: viewer.html?selftest=1 (web/main.js selftest()) now runs
# the SPEC-004 base case plus off-origin, tiny (1e-3), huge (1e6), and
# multi-object framing-hardening cases, asserting the framing contract
# (projected bounding-sphere fill 0.6-0.9, target = bbox center) for each.
# Same runner/mechanism as test-page-selftest.sh — kept as a separate file
# per SPEC-005's test list for traceability of the hardening cases.
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$DIR/.." && pwd)"

# SPEC-009 (external review, Low): default to the checkout, not the
# installed copy. MAKIMIRU_TEST_INSTALLED=1 tests the installed prefix.
if [ "${MAKIMIRU_TEST_INSTALLED:-0}" = "1" ]; then
    PAGE="$HOME/.local/share/sushi/web/viewer.html"
else
    PAGE="$REPO/web/viewer.html"
fi
[ -f "$PAGE" ] || { echo "viewer.html not found at $PAGE — run scripts/install-user.sh or unset MAKIMIRU_TEST_INSTALLED" >&2; exit 1; }

# Ensure a display when run over SSH into a session machine.
export DISPLAY="${DISPLAY:-:0}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

out="$(gjs "$DIR/page-selftest-runner.js" "$PAGE")" || {
    echo "FAIL: $out" >&2
    exit 1
}
echo "$out"
echo "PASS: test-framing-selftest"
