#!/bin/sh
# SPEC-004 test 1: binary and ASCII STL fixtures preview (Visible=true) and
# log a 'rendered' event; warm ShowFile→rendered for the 1 MB binary fixture
# must beat the 2000 ms hard-fail line (NFR-1 target ~1 s; loose to avoid
# flaky failures — real numbers go in the regression checklist).
set -eu
. "$(dirname "$0")/lib.sh"
DIR="$(cd "$(dirname "$0")" && pwd)"

TMP="${TMPDIR:-/tmp}/makimiru-stl"
mkdir -p "$TMP"
LOG="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/makimiru-timing.log"

# ~1 MB binary (20k triangles) and a small ASCII sphere.
[ -f "$TMP/sphere-20k.stl" ] || python3 "$DIR/make-stl.py" 20000 "$TMP/sphere-20k.stl"
[ -f "$TMP/sphere-ascii.stl" ] || python3 "$DIR/make-stl.py" 500 "$TMP/sphere-ascii.stl" --ascii

log_lines() { [ -f "$LOG" ] && wc -l < "$LOG" || echo 0; }

# Show a fixture, assert Visible=true via PropertiesChanged, then require a
# new 'rendered' line in the timing log within 5 s.
show_and_check() { # path
    before="$(log_lines)"
    assert_visible_change true "show_v2 file://$1"
    i=0
    while [ $i -lt 10 ]; do
        [ "$(log_lines)" -gt "$before" ] && break
        sleep 0.5
        i=$((i + 1))
    done
    if [ "$(log_lines)" -le "$before" ]; then
        echo "FAIL: no rendered event logged for $1" >&2
        exit 1
    fi
    assert_visible_change false "close_preview"
    echo "ok: $1"
}

show_and_check "$TMP/sphere-20k.stl"
show_and_check "$TMP/sphere-ascii.stl"

# Warm timing: previewer process is alive from the runs above.
before="$(log_lines)"
t_start="$(date +%s%3N)"
show_v2 "file://$TMP/sphere-20k.stl"
i=0
while [ $i -lt 20 ]; do
    [ "$(log_lines)" -gt "$before" ] && break
    sleep 0.1
    i=$((i + 1))
done
t_end="$(date +%s%3N)"
close_preview || true
elapsed=$((t_end - t_start))
if [ "$(log_lines)" -le "$before" ]; then
    echo "FAIL: warm run logged no rendered event" >&2
    exit 1
fi
if [ "$elapsed" -ge 2000 ]; then
    echo "FAIL: warm ShowFile->rendered took ${elapsed}ms (>= 2000ms)" >&2
    exit 1
fi
echo "warm ShowFile->rendered: ${elapsed}ms"
echo "PASS: test-stl-preview"
