#!/bin/sh
# SPEC-006 test 2: corrupt/unreadable/empty fixtures show error panels (not
# crashes), the D-Bus name owner PID never changes, and a valid preview
# afterward proves the previewer is still healthy (recovery).
set -eu
. "$(dirname "$0")/lib.sh"
DIR="$(cd "$(dirname "$0")" && pwd)"

TMP="${TMPDIR:-/tmp}/makimiru-bad"
mkdir -p "$TMP"
[ -f "$TMP/garbage.stl" ] || python3 "$DIR/make-bad-fixtures.py" "$TMP"

LOG="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/makimiru-timing.log"
log_lines() { [ -f "$LOG" ] && wc -l < "$LOG" || echo 0; }

owner_pid() {
    gdbus call --session --dest org.freedesktop.DBus --object-path / \
        --method org.freedesktop.DBus.GetConnectionUnixProcessID "$DEST" 2>/dev/null \
        | sed 's/.*uint32 \([0-9]*\).*/\1/'
}

# Activate the previewer first so we can snapshot its owner PID.
show_v2 "file://$TMP/garbage.stl" >/dev/null 2>&1 || true
sleep 1
pid_before="$(owner_pid)"
[ -n "$pid_before" ] || { echo "FAIL: could not determine owner PID" >&2; exit 1; }
close_preview >/dev/null 2>&1 || true

# category: expected value of the 3rd field model.js logs — "<iso> error <category> <uri>"
check_error() { # path, category
    path="$1"; category="$2"
    before="$(log_lines)"
    assert_visible_change true "show_v2 file://$path"
    i=0
    while [ $i -lt 40 ]; do
        [ "$(log_lines)" -gt "$before" ] && break
        sleep 0.5
        i=$((i + 1))
    done
    if [ "$(log_lines)" -le "$before" ]; then
        echo "FAIL: no timing log event for $path (expected category=$category)" >&2
        exit 1
    fi
    line="$(tail -n 1 "$LOG")"
    case "$line" in
        *" error $category "*) : ;;
        *) echo "FAIL: expected 'error $category' for $path, got: $line" >&2; exit 1 ;;
    esac
    assert_visible_change false "close_preview"
    echo "ok: $path -> $line"
}

check_error "$TMP/truncated.stl" "corrupt"
check_error "$TMP/garbage.stl" "corrupt"
check_error "$TMP/notreally.3mf" "corrupt"

# empty.stl is a special case: gio resolves 0-byte files to
# application/x-zerosize regardless of extension (verified via `gio info`),
# so mimeHandler.js dispatches it to upstream's existing FallbackRenderer,
# not our module — it never reaches model.js at all. That's correct,
# pre-existing graceful behavior (file-info panel, no crash, no NaN
# camera — our renderer simply never runs), so there's no timing-log line
# to check here; just confirm it doesn't hang or crash the previewer.
assert_visible_change true "show_v2 file://$TMP/empty.stl"
assert_visible_change false "close_preview"
echo "ok: $TMP/empty.stl -> dispatched to FallbackRenderer (application/x-zerosize), no crash"

pid_mid="$(owner_pid)"
[ "$pid_mid" = "$pid_before" ] || { echo "FAIL: owner PID changed ($pid_before -> $pid_mid) — previewer crashed" >&2; exit 1; }

# Recovery proof: a valid STL still renders after the error sequence.
VALID="${TMPDIR:-/tmp}/makimiru-stl/sphere-ascii.stl"
mkdir -p "$(dirname "$VALID")"
[ -f "$VALID" ] || python3 "$DIR/make-stl.py" 500 "$VALID" --ascii
before="$(log_lines)"
assert_visible_change true "show_v2 file://$VALID"
i=0
while [ $i -lt 20 ]; do
    [ "$(log_lines)" -gt "$before" ] && break
    sleep 0.5
    i=$((i + 1))
done
line="$(tail -n 1 "$LOG")"
case "$line" in
    *" rendered "*) : ;;
    *) echo "FAIL: recovery load did not render, got: $line" >&2; exit 1 ;;
esac
assert_visible_change false "close_preview"

pid_after="$(owner_pid)"
[ "$pid_after" = "$pid_before" ] || { echo "FAIL: owner PID changed after recovery ($pid_before -> $pid_after)" >&2; exit 1; }

echo "PASS: test-error-paths"
