#!/bin/sh
# SPEC-009 test 3 (static): full license/notice text exists for every
# vendored third-party library, not just an attribution README.
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$DIR/.." && pwd)"
VENDOR="$REPO/web/vendor"

fail=0
for f in LICENSE-three.js LICENSE-fflate; do
    path="$VENDOR/$f"
    if [ ! -s "$path" ]; then
        echo "FAIL: $path missing or empty" >&2
        fail=1
    fi
done

# Release review (2026-11-17): LICENSE-fflate once named "fflate
# contributors" instead of the real upstream copyright holder — MIT
# requires the original notice, so pin the holders, not just presence.
grep -q "three.js authors" "$VENDOR/LICENSE-three.js" ||
    { echo "FAIL: LICENSE-three.js lacks upstream copyright line" >&2; fail=1; }
grep -q "^Copyright (c) [0-9]* Arjun Barrett$" "$VENDOR/LICENSE-fflate" ||
    { echo "FAIL: LICENSE-fflate lacks upstream copyright line (Arjun Barrett)" >&2; fail=1; }

if [ "$fail" -eq 0 ]; then
    echo "PASS: test-vendor-licenses"
fi
exit $fail
