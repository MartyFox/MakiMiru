#!/bin/sh
# SPEC-009 test 1: the timing log records extension/size/timing/category
# only, never the previewed file's full path/URI.
set -eu
. "$(dirname "$0")/lib.sh"
DIR="$(cd "$(dirname "$0")" && pwd)"

TMP="${TMPDIR:-/tmp}/makimiru-stl"
mkdir -p "$TMP"
[ -f "$TMP/sphere-ascii.stl" ] || python3 "$DIR/make-stl.py" 500 "$TMP/sphere-ascii.stl" --ascii

LOG="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/makimiru-timing.log"
log_lines() { [ -f "$LOG" ] && wc -l < "$LOG" || echo 0; }

before="$(log_lines)"
assert_visible_change true "show_v2 file://$TMP/sphere-ascii.stl"
i=0
while [ $i -lt 20 ]; do
    [ "$(log_lines)" -gt "$before" ] && break
    sleep 0.5
    i=$((i + 1))
done
if [ "$(log_lines)" -le "$before" ]; then
    echo "FAIL: no timing event logged" >&2
    exit 1
fi
assert_visible_change false "close_preview"

line="$(tail -n 1 "$LOG")"
echo "logged: $line"

case "$line" in
    *" rendered "*ext=stl*size=*) : ;;
    *) echo "FAIL: expected an anonymized 'rendered ... ext=stl size=<n>' line, got: $line" >&2; exit 1 ;;
esac

case "$line" in
    *"$TMP"*|*file://*)
        echo "FAIL: timing log line contains a file path/URI: $line" >&2
        exit 1
        ;;
esac

echo "PASS: test-log-privacy"
