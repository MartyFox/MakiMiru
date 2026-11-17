#!/bin/sh
# SPEC-005 test 1: 3MF (single + two-object) and OBJ fixtures preview
# (Visible=true) and log a 'rendered' event, same as STL in SPEC-004.
set -eu
. "$(dirname "$0")/lib.sh"
DIR="$(cd "$(dirname "$0")" && pwd)"

TMP="${TMPDIR:-/tmp}/kaiten-3mf-obj"
mkdir -p "$TMP"
LOG="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/kaiten-timing.log"

[ -f "$TMP/cube.3mf" ] || python3 "$DIR/make-3mf.py" "$TMP/cube.3mf"
[ -f "$TMP/two-object.3mf" ] || python3 "$DIR/make-3mf.py" "$TMP/two-object.3mf" --two-object
[ -f "$TMP/cube.obj" ] || python3 "$DIR/make-obj.py" "$TMP/cube.obj"

log_lines() { [ -f "$LOG" ] && wc -l < "$LOG" || echo 0; }

# Show a fixture, assert Visible=true via PropertiesChanged, then require
# specifically a 'rendered' line (not just any new line — SPEC-008 caught
# a real bug here: SPEC-007's fixed model URL broke format inference, and
# every non-STL file was silently misparsed as STL, which still produced
# *some* timing-log line, just an 'error' one, and this check didn't
# distinguish the two).
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
        echo "FAIL: no timing event logged for $1" >&2
        exit 1
    fi
    line="$(tail -n 1 "$LOG")"
    case "$line" in
        *" rendered "*) : ;;
        *) echo "FAIL: expected 'rendered' for $1, got: $line" >&2; exit 1 ;;
    esac
    assert_visible_change false "close_preview"
    echo "ok: $1 -> $line"
}

show_and_check "$TMP/cube.3mf"
show_and_check "$TMP/two-object.3mf"
show_and_check "$TMP/cube.obj"

echo "PASS: test-3mf-obj-preview"
