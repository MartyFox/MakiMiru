#!/bin/sh
# SPEC-006 test 5, scoping fixed in SPEC-009 (external review): kill the
# WebKitWebProcess mid-preview and confirm the previewer (the gjs
# process, a different PID) survives and recovers. Targets only the
# WebKit child *belonging to the previewer instance under test* (found
# via its parent PID, same pattern as test-bomb-memory-bound.sh) — not
# "first match by name," which could kill an unrelated WebKit consumer
# (Epiphany, Devhelp, ...) on a general-purpose desktop.
set -eu
. "$(dirname "$0")/lib.sh"
DIR="$(cd "$(dirname "$0")" && pwd)"

VALID="${TMPDIR:-/tmp}/makimiru-stl/sphere-ascii.stl"
mkdir -p "$(dirname "$VALID")"
[ -f "$VALID" ] || python3 "$DIR/make-stl.py" 500 "$VALID" --ascii

LOG="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/makimiru-timing.log"
log_lines() { [ -f "$LOG" ] && wc -l < "$LOG" || echo 0; }

owner_pid() {
    gdbus call --session --dest org.freedesktop.DBus --object-path / \
        --method org.freedesktop.DBus.GetConnectionUnixProcessID "$DEST" 2>/dev/null \
        | sed 's/.*uint32 \([0-9]*\).*/\1/'
}

webprocess_pid_of() { # gjs previewer pid
    pgrep -P "$1" -f WebKitWebProcess 2>/dev/null | head -n1
}

before="$(log_lines)"
assert_visible_change true "show_v2 file://$VALID"
i=0
while [ $i -lt 20 ]; do
    [ "$(log_lines)" -gt "$before" ] && break
    sleep 0.5
    i=$((i + 1))
done
if [ "$(log_lines)" -le "$before" ]; then
    echo "FAIL: initial load never rendered — can't proceed to kill test" >&2
    exit 1
fi

previewer_pid="$(owner_pid)"
webprocess_pid="$(webprocess_pid_of "$previewer_pid")"
if [ -z "$webprocess_pid" ]; then
    echo "SKIP: no WebKitWebProcess child of pid $previewer_pid found — could not target it reliably (documented per spec, not a test failure)"
    close_preview >/dev/null 2>&1 || true
    exit 0
fi

before="$(log_lines)"
kill -9 "$webprocess_pid"
i=0
while [ $i -lt 40 ]; do
    [ "$(log_lines)" -gt "$before" ] && break
    sleep 0.5
    i=$((i + 1))
done
line="$(tail -n 1 "$LOG" 2>/dev/null || true)"
case "$line" in
    *" error crashed "*) : ;;
    *) echo "FAIL: expected 'error crashed' after killing web process, got: $line" >&2; exit 1 ;;
esac

pid_after_kill="$(owner_pid)"
[ "$pid_after_kill" = "$previewer_pid" ] || {
    echo "FAIL: previewer PID changed after web-process kill ($previewer_pid -> $pid_after_kill) — previewer crashed too" >&2
    exit 1
}
close_preview >/dev/null 2>&1 || true

# Recovery: next ShowFile still works.
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
    *) echo "FAIL: recovery load after web-process kill did not render, got: $line" >&2; exit 1 ;;
esac
assert_visible_change false "close_preview"

echo "PASS: test-webprocess-kill (killed pid $webprocess_pid, previewer pid $previewer_pid stable)"
