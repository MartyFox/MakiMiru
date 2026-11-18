#!/bin/sh
# SPEC-008 test 3: the WebKit **page** process — not the GJS previewer
# process — is where web/main.js's decompression/allocation actually
# runs, and stays bounded while handling the 3MF zip-bomb fixture.
#
# External review caught a real bug in an earlier version of this test:
# it sampled the D-Bus owner PID, which is the GJS previewer, while all
# the loader/fflate work happens in a separate WebKitWebProcess child —
# a test sampling the wrong process could pass with flat GJS RSS while
# the actual WebKitWebProcess grew unbounded, OOMed, or crashed.
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

webprocess_pid() { # gjs previewer pid
    pgrep -P "$1" -f WebKitWebProcess 2>/dev/null | head -n1
}

rss_kb() { # pid
    [ -n "$1" ] && awk '/^VmRSS:/{print $2}' "/proc/$1/status" 2>/dev/null || echo 0
}

# Growth bound: the fixture targets ~2 GB uncompressed; an uncapped
# decompress would chase that. Bound is generous slack above the 500 MB
# cap (MAX_3MF_DECOMPRESSED_BYTES) to absorb the zip container itself,
# WebKit process baseline overhead, and one chunk's worst-case
# overshoot — still an order of magnitude below the fixture's target.
BOUND_KB=$((900 * 1024))

show_v2 "file://$TMP/zipbomb.3mf" >/dev/null 2>&1 || true
sleep 1
gjs_pid="$(owner_pid)"
[ -n "$gjs_pid" ] || { echo "FAIL: could not determine owner PID" >&2; exit 1; }
close_preview >/dev/null 2>&1 || true
# A fresh WebKitWebProcess is spawned per ShowFile — let the idle one
# from the warm-up call above exit before triggering the real run.
sleep 1

before_lines="$(log_lines)"
show_v2 "file://$TMP/zipbomb.3mf"

min_kb=0
max_kb=0
i=0
while [ $i -lt 80 ]; do
    wp_pid="$(webprocess_pid "$gjs_pid")"
    cur_kb="$(rss_kb "$wp_pid")"
    if [ "$cur_kb" -gt 0 ]; then
        [ "$min_kb" -eq 0 ] && min_kb="$cur_kb"
        [ "$cur_kb" -gt "$max_kb" ] && max_kb="$cur_kb"
    fi
    [ "$(log_lines)" -gt "$before_lines" ] && break
    sleep 0.25
    i=$((i + 1))
done

if [ "$(log_lines)" -le "$before_lines" ]; then
    echo "FAIL: no timing log event — zipbomb.3mf preview hung past the poll window" >&2
    exit 1
fi

line="$(tail -n 1 "$LOG")"
case "$line" in
    *" error crashed "*)
        echo "FAIL: previewer reported the WebKit page process crashed: $line" >&2
        exit 1
        ;;
esac

if [ "$max_kb" -eq 0 ]; then
    echo "FAIL: never observed a WebKitWebProcess child of pid $gjs_pid — sampling the wrong process" >&2
    exit 1
fi

growth_kb=$((max_kb - min_kb))
echo "WebKitWebProcess RSS: first-seen ${min_kb}KB, peak ${max_kb}KB, growth ${growth_kb}KB (bound ${BOUND_KB}KB)"
echo "final log line: $line"

if [ "$growth_kb" -ge "$BOUND_KB" ]; then
    echo "FAIL: RSS growth ${growth_kb}KB exceeds bound ${BOUND_KB}KB — decompression cap may not be firing" >&2
    exit 1
fi

close_preview >/dev/null 2>&1 || true
gjs_pid_after="$(owner_pid)"
[ "$gjs_pid_after" = "$gjs_pid" ] || { echo "FAIL: owner PID changed ($gjs_pid -> $gjs_pid_after) — previewer crashed" >&2; exit 1; }

echo "PASS: test-bomb-memory-bound"
