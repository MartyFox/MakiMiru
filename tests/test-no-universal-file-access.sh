#!/bin/sh
# SPEC-007 test 3 (static): the model viewer must never grant broad
# file:// privilege to the WebView — the page reaches local content
# only through the constrained 'makimiru' scheme.
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$DIR/.." && pwd)"
MODULE="$REPO/src/viewers/model.js"

fail=0

if grep -n 'allow_universal_access_from_file_urls' "$MODULE"; then
    echo "FAIL: allow_universal_access_from_file_urls found in $MODULE" >&2
    fail=1
fi
if grep -n 'allow_file_access_from_file_urls' "$MODULE"; then
    echo "FAIL: allow_file_access_from_file_urls found in $MODULE" >&2
    fail=1
fi

if [ "$fail" -eq 0 ]; then
    echo "PASS: test-no-universal-file-access"
fi
exit $fail
