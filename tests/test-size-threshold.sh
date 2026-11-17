#!/bin/sh
# SPEC-006 test 3: oversized files hit the 100 MB threshold check
# immediately (no parse attempt, no multi-second wait) and log an
# 'oversized' event, not a 'rendered' or parse-'error' one.
set -eu
. "$(dirname "$0")/lib.sh"
DIR="$(cd "$(dirname "$0")" && pwd)"

TMP="${TMPDIR:-/tmp}/kaiten-bad"
mkdir -p "$TMP"
[ -f "$TMP/big.stl" ] || python3 "$DIR/make-bad-fixtures.py" "$TMP"

LOG="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/kaiten-timing.log"
log_lines() { [ -f "$LOG" ] && wc -l < "$LOG" || echo 0; }

before="$(log_lines)"
t_start="$(date +%s%3N)"
assert_visible_change true "show_v2 file://$TMP/big.stl"
i=0
while [ $i -lt 10 ]; do
    [ "$(log_lines)" -gt "$before" ] && break
    sleep 0.2
    i=$((i + 1))
done
t_end="$(date +%s%3N)"
elapsed=$((t_end - t_start))

if [ "$(log_lines)" -le "$before" ]; then
    echo "FAIL: no timing event logged for oversized file" >&2
    exit 1
fi
line="$(tail -n 1 "$LOG")"
case "$line" in
    *" error oversized "*) : ;;
    *) echo "FAIL: expected 'error oversized', got: $line" >&2; exit 1 ;;
esac
if [ "$elapsed" -ge 2000 ]; then
    echo "FAIL: oversized detection took ${elapsed}ms (>= 2000ms) — looks like a parse was attempted" >&2
    exit 1
fi
assert_visible_change false "close_preview"
echo "oversized detected in ${elapsed}ms: $line"
echo "PASS: test-size-threshold"
