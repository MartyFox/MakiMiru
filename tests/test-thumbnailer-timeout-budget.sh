#!/bin/sh
# SPEC-010 test 3: the CLI's internal timeout budget fires and exits
# cleanly (non-zero, no PNG) well before an external "outer" ceiling
# (simulating tumbler/gnome-desktop's own budget), never hanging.
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$DIR/.." && pwd)"
. "$DIR/thumbnailer-lib.sh"
assert_thumbnailer_fresh "$REPO"
BIN="${KAITEN_TEST_BIN:-$HOME/.local/libexec/kaiten-thumbnailer}"

TMP="${TMPDIR:-/tmp}/kaiten-stl"
mkdir -p "$TMP"
[ -f "$TMP/sphere-20k.stl" ] || python3 "$DIR/make-stl.py" 20000 "$TMP/sphere-20k.stl"

export DISPLAY="${DISPLAY:-:0}"
OUT="${TMPDIR:-/tmp}/thumb-timeout-test.png"
rm -f "$OUT"

# 50ms is far too short for cold WebKit startup — guaranteed to trip our
# own internal timeout, not the real render finishing. Outer ceiling
# (`timeout 5`) simulates tumbler's own budget: if we ever failed to
# respect our own timeout, this outer kill would fire instead and we'd
# see a different (timeout(1)'s) exit code, catching a genuine hang.
t0=$(date +%s%3N)
# if/else, not a bare statement — this command is *expected* to fail
# (that's the point of the test), and under `set -e` a bare non-zero
# exit here would abort the script before `code=$?` ever ran (same
# gotcha caught in test-thumbnailer-cli.sh's check_bad).
if KAITEN_THUMBNAIL_TIMEOUT_MS=50 timeout 5 "$BIN" "$TMP/sphere-20k.stl" "$OUT" 256 >/tmp/thumb-timeout-test.err 2>&1; then
    code=0
else
    code=$?
fi
t1=$(date +%s%3N)
elapsed=$((t1 - t0))

echo "exit=$code elapsed=${elapsed}ms"
cat /tmp/thumb-timeout-test.err

if [ "$code" -eq 0 ]; then
    echo "FAIL: expected non-zero exit (timeout should have fired)" >&2
    exit 1
fi
if [ "$code" -eq 124 ]; then
    echo "FAIL: outer 'timeout 5' killed it — internal timeout did not fire on its own" >&2
    exit 1
fi
if [ -f "$OUT" ]; then
    echo "FAIL: PNG written despite timeout" >&2
    exit 1
fi
# Generous upper bound — should be close to 50ms + the 100ms post-render
# grace it never reaches, definitely nowhere near the outer 5s ceiling.
if [ "$elapsed" -ge 3000 ]; then
    echo "FAIL: took ${elapsed}ms — internal timeout budget not respected" >&2
    exit 1
fi

echo "PASS: test-thumbnailer-timeout-budget"
