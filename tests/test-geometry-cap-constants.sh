#!/bin/sh
# SPEC-008 acceptance criterion: every new cap is a single named constant.
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$DIR/.." && pwd)"
MODULE="$REPO/web/main.js"

fail=0
for name in MAX_TRIANGLE_COUNT MAX_VERTEX_COUNT MAX_3MF_DECOMPRESSED_BYTES MAX_TEXTURE_BYTES; do
    n="$(grep -c "^const $name *=" "$MODULE" || true)"
    if [ "$n" -ne 1 ]; then
        echo "FAIL: expected exactly 1 definition of $name in $MODULE, found $n" >&2
        fail=1
    fi
done

if [ "$fail" -eq 0 ]; then
    echo "PASS: test-geometry-cap-constants"
fi
exit $fail
