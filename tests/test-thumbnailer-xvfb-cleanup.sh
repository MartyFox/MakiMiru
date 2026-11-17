#!/bin/sh
# Release review (2026-11-17): the thumbnailer used to SIGKILL its
# private Xvfb, leaking /tmp/.X11-unix/X<n> + /tmp/.X<n>-lock on every
# run outside GNOME's bwrap sandbox (XFCE/MATE tumbler, direct runs),
# and a stale socket could make the next run connect too early. Asserts:
# no leaked sockets/locks/processes after good runs, a failing run, and a
# run killed mid-render by an outside SIGTERM (what tumbler does on its
# own timeout).
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$DIR/.." && pwd)"
. "$DIR/thumbnailer-lib.sh"
assert_thumbnailer_fresh "$REPO"
BIN="${KAITEN_TEST_BIN:-$HOME/.local/libexec/kaiten-thumbnailer}"

STL="${TMPDIR:-/tmp}/kaiten-stl"
BAD="${TMPDIR:-/tmp}/kaiten-bad"
mkdir -p "$STL" "$BAD"
[ -f "$STL/sphere-20k.stl" ] || python3 "$DIR/make-stl.py" 20000 "$STL/sphere-20k.stl"
[ -f "$BAD/big.stl" ] || python3 "$DIR/make-bad-fixtures.py" "$BAD"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

snapshot() {
    { ls /tmp/.X11-unix/ 2>/dev/null; ls -d /tmp/.X*-lock 2>/dev/null; } | sort
}
xvfb_count() { pgrep -u "$(id -u)" -x Xvfb | wc -l; }

before="$(snapshot)"
xvfb_before="$(xvfb_count)"

for i in 1 2 3; do
    timeout 20 "$BIN" "$STL/sphere-20k.stl" "$OUT/good$i.png" 128 >/dev/null 2>&1 ||
        { echo "FAIL: good run $i exited non-zero" >&2; exit 1; }
done
timeout 20 "$BIN" "$BAD/truncated.stl" "$OUT/bad.png" 128 >/dev/null 2>&1 && {
    echo "FAIL: corrupt fixture unexpectedly succeeded" >&2; exit 1; } || true
# Killed from outside mid-render (before it can stop Xvfb itself).
timeout -s TERM 1 "$BIN" "$STL/sphere-20k.stl" "$OUT/killed.png" 128 >/dev/null 2>&1 || true

i=0
while [ $i -lt 30 ]; do
    [ "$(snapshot)" = "$before" ] && [ "$(xvfb_count)" -le "$xvfb_before" ] && break
    sleep 0.2; i=$((i + 1))
done

after="$(snapshot)"
if [ "$after" != "$before" ]; then
    echo "FAIL: X11 socket/lock files leaked:" >&2
    printf '%s\n' "$after" | grep -vxF "$before" >&2 || true
    exit 1
fi
if [ "$(xvfb_count)" -gt "$xvfb_before" ]; then
    echo "FAIL: Xvfb process(es) left running: $(pgrep -a -u "$(id -u)" -x Xvfb)" >&2
    exit 1
fi
echo "PASS: no Xvfb sockets, locks or processes leaked across 5 runs"
