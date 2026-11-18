#!/bin/sh
# SPEC-005 test 3: confirm .obj dispatches to the 3D model viewer, not
# Sushi's text viewer. Records the observed gio content-type (note:
# Ubuntu 24.04 shared-mime-info resolves .obj -> model/obj directly, no
# text/plain collision seen — this test guards against that changing), then
# proves dispatch via the timing log: only model.js writes to it, so a new
# 'rendered' line after ShowFile means the 3D viewer handled the file, not
# the text viewer (which would show text content but log nothing here).
set -eu
. "$(dirname "$0")/lib.sh"
DIR="$(cd "$(dirname "$0")" && pwd)"

TMP="${TMPDIR:-/tmp}/makimiru-3mf-obj"
mkdir -p "$TMP"
LOG="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/makimiru-timing.log"

[ -f "$TMP/cube.obj" ] || python3 "$DIR/make-obj.py" "$TMP/cube.obj"

content_type="$(gio info -a standard::content-type "$TMP/cube.obj" | sed -n 's/.*standard::content-type: //p')"
echo "observed content-type: $content_type"
[ -n "$content_type" ] || { echo "FAIL: gio info returned no content-type" >&2; exit 1; }

log_lines() { [ -f "$LOG" ] && wc -l < "$LOG" || echo 0; }
before="$(log_lines)"
assert_visible_change true "show_v2 file://$TMP/cube.obj"

i=0
while [ $i -lt 10 ]; do
    [ "$(log_lines)" -gt "$before" ] && break
    sleep 0.5
    i=$((i + 1))
done
if [ "$(log_lines)" -le "$before" ]; then
    echo "FAIL: no rendered event logged for cube.obj — dispatched to a non-3D viewer?" >&2
    exit 1
fi
assert_visible_change false "close_preview"

echo "PASS: test-obj-dispatch (content-type=$content_type, dispatched to model viewer)"
