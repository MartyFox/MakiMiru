#!/bin/sh
# SPEC-006 test 4 (static): pins NFR-2 (no sync file I/O on the GJS main
# thread in the model path) and the single-named-constant acceptance
# criterion for the 100 MB threshold and 15 s timeout.
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$DIR/.." && pwd)"
MODULE="$REPO/src/viewers/model.js"

fail=0

if grep -nE '\bload_contents\(' "$MODULE"; then
    echo "FAIL: sync load_contents( found in $MODULE" >&2
    fail=1
fi
if grep -nE '\bquery_info\(' "$MODULE"; then
    echo "FAIL: sync query_info( found in $MODULE" >&2
    fail=1
fi
if grep -nE '\.read\(' "$MODULE"; then
    echo "FAIL: sync .read( found in $MODULE" >&2
    fail=1
fi

threshold_defs="$(grep -c 'OVERSIZED_THRESHOLD_BYTES *=' "$MODULE")"
if [ "$threshold_defs" -ne 1 ]; then
    echo "FAIL: expected exactly 1 definition of OVERSIZED_THRESHOLD_BYTES, found $threshold_defs" >&2
    fail=1
fi

timeout_defs="$(grep -c 'LOAD_TIMEOUT_MS *=' "$MODULE")"
if [ "$timeout_defs" -ne 1 ]; then
    echo "FAIL: expected exactly 1 definition of LOAD_TIMEOUT_MS, found $timeout_defs" >&2
    fail=1
fi

if [ "$fail" -ne 0 ]; then
    exit 1
fi
echo "PASS: test-async-audit ($MODULE clean; threshold+timeout each defined once)"
