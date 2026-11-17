#!/bin/sh
# SPEC-011 test 3 (static): dpkg -L kaiten fully accounts for every
# file the package places — keeps the "everything is verifiable from
# package metadata alone" transparency claim (User Story 13) honest
# over time, by diffing against a maintained expected list rather than
# trusting the claim indefinitely.
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"

dpkg -l kaiten 2>/dev/null | grep -q '^ii' || {
    echo "FAIL: kaiten is not currently installed — run test-deb-install.sh first" >&2
    exit 1
}

EXPECTED="$DIR/deb-file-manifest.expected"
[ -f "$EXPECTED" ] || { echo "FAIL: $EXPECTED not found" >&2; exit 1; }

# Locale .mo files are excluded — their count/names track upstream
# Sushi's translation coverage, not anything this project controls;
# listing every one by hand would make this test churn on unrelated
# upstream changes.
dpkg -L kaiten | grep -v '/locale/' | sort > /tmp/kaiten-deb-actual-manifest.txt
sort "$EXPECTED" > /tmp/kaiten-deb-expected-manifest.txt

if ! diff -u /tmp/kaiten-deb-expected-manifest.txt /tmp/kaiten-deb-actual-manifest.txt; then
    echo "FAIL: installed file list (excl. locale/) does not match $EXPECTED — update it if this drift is intentional" >&2
    exit 1
fi

echo "PASS: test-deb-file-manifest"
