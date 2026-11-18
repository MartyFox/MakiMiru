#!/bin/sh
# SPEC-008 test 2: a small on-disk file that lies about its geometry (STL
# claimed face count) or hides a huge decompressed payload (3MF zip bomb)
# hits the preflight caps in web/main.js and fails fast/cleanly — not a
# hang, not an unbounded allocation, not a crash. Same shape as SPEC-006's
# test-error-paths.sh, extended for the SPEC-008 fixtures.
set -eu
. "$(dirname "$0")/lib.sh"
DIR="$(cd "$(dirname "$0")" && pwd)"

TMP="${TMPDIR:-/tmp}/makimiru-bombs"
mkdir -p "$TMP"
[ -f "$TMP/zipbomb.3mf" ] || python3 "$DIR/make-bomb-fixtures.py" "$TMP"

LOG="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/makimiru-timing.log"
log_lines() { [ -f "$LOG" ] && wc -l < "$LOG" || echo 0; }

owner_pid() {
    gdbus call --session --dest org.freedesktop.DBus --object-path / \
        --method org.freedesktop.DBus.GetConnectionUnixProcessID "$DEST" 2>/dev/null \
        | sed 's/.*uint32 \([0-9]*\).*/\1/'
}

show_v2 "file://$TMP/zipbomb.3mf" >/dev/null 2>&1 || true
sleep 1
pid_before="$(owner_pid)"
[ -n "$pid_before" ] || { echo "FAIL: could not determine owner PID" >&2; exit 1; }
close_preview >/dev/null 2>&1 || true

# Bomb fixtures must fail as 'corrupt' (our preflight throws, same page
# 'error' event path as any other parse failure) within a bounded time —
# well under SPEC-006's 15 s load timeout, since the preflight check
# should reject before the timeout would ever need to fire.
check_bomb() { # path
    path="$1"
    before="$(log_lines)"
    t_start="$(date +%s%3N)"
    assert_visible_change true "show_v2 file://$path"
    i=0
    while [ $i -lt 30 ]; do
        [ "$(log_lines)" -gt "$before" ] && break
        sleep 0.5
        i=$((i + 1))
    done
    t_end="$(date +%s%3N)"
    elapsed=$((t_end - t_start))
    if [ "$(log_lines)" -le "$before" ]; then
        echo "FAIL: no timing log event for $path (hung past the poll window)" >&2
        exit 1
    fi
    line="$(tail -n 1 "$LOG")"
    case "$line" in
        *" error corrupt "*) : ;;
        *) echo "FAIL: expected 'error corrupt' for $path, got: $line" >&2; exit 1 ;;
    esac
    if [ "$elapsed" -ge 15000 ]; then
        echo "FAIL: $path took ${elapsed}ms — looks like the preflight didn't fire before the load timeout" >&2
        exit 1
    fi
    assert_visible_change false "close_preview"
    echo "ok: $path -> $line (${elapsed}ms)"
}

check_bomb "$TMP/lied-facecount.stl"
check_bomb "$TMP/zipbomb.3mf"

pid_mid="$(owner_pid)"
[ "$pid_mid" = "$pid_before" ] || { echo "FAIL: owner PID changed ($pid_before -> $pid_mid) — previewer crashed" >&2; exit 1; }

# Recovery proof: a valid STL still renders after both bomb fixtures.
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

echo "PASS: test-allocation-bombs"
