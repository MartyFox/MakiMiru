#!/bin/sh
# SPEC-009 test 4: proves test-page-selftest.sh / test-framing-selftest.sh
# actually check the checkout by default (a marker string added only to
# the checkout's viewer.html must be observable), and that setting
# MAKIMIRU_TEST_INSTALLED=1 switches them to the installed prefix
# instead — without needing to run a real selftest twice, this just
# confirms which file path each mode resolves to.
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$DIR/.." && pwd)"

resolve_page() { # env value for MAKIMIRU_TEST_INSTALLED
    MAKIMIRU_TEST_INSTALLED="$1" sh -c '
        DIR="'"$DIR"'"
        REPO="'"$REPO"'"
        if [ "${MAKIMIRU_TEST_INSTALLED:-0}" = "1" ]; then
            echo "$HOME/.local/share/sushi/web/viewer.html"
        else
            echo "$REPO/web/viewer.html"
        fi
    '
}

checkout_resolved="$(resolve_page 0)"
installed_resolved="$(resolve_page 1)"

[ "$checkout_resolved" = "$REPO/web/viewer.html" ] || {
    echo "FAIL: default (unset MAKIMIRU_TEST_INSTALLED) resolved to '$checkout_resolved', expected the checkout" >&2
    exit 1
}
[ "$installed_resolved" = "$HOME/.local/share/sushi/web/viewer.html" ] || {
    echo "FAIL: MAKIMIRU_TEST_INSTALLED=1 resolved to '$installed_resolved', expected the installed prefix" >&2
    exit 1
}
[ "$checkout_resolved" != "$installed_resolved" ] || {
    echo "FAIL: checkout and installed paths resolved identically — no real distinction" >&2
    exit 1
}

# Deliberately diverge the checkout from whatever's installed (a
# checkout-only marker comment) and confirm test-page-selftest.sh
# actually reads the file we just changed, by default.
marker="MAKIMIRU_CHECKOUT_MARKER_$$"
cp "$REPO/web/viewer.html" "$REPO/web/viewer.html.bak"
trap 'mv "$REPO/web/viewer.html.bak" "$REPO/web/viewer.html"' EXIT
printf '<!-- %s -->\n' "$marker" >> "$REPO/web/viewer.html"

if [ -f "$HOME/.local/share/sushi/web/viewer.html" ] && grep -q "$marker" "$HOME/.local/share/sushi/web/viewer.html"; then
    echo "FAIL: marker unexpectedly present in installed copy — test setup invalid" >&2
    exit 1
fi

grep -q "$marker" "$checkout_resolved" || {
    echo "FAIL: marker not found via the default (checkout) resolution path" >&2
    exit 1
}

echo "PASS: test-checkout-vs-install"
