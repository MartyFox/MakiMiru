#!/bin/sh
# SPEC-011 test 4: postinst/prerm print required plain-language
# statements, not just run silently and succeed (User Story 13).
# Checks the captured output from the most recent real
# test-deb-install.sh / test-deb-remove.sh runs rather than
# re-triggering install/remove itself, to avoid a third redundant
# install/remove cycle in the same test pass.
set -eu

INSTALL_LOG=/tmp/makimiru-deb-install.log
REMOVE_LOG=/tmp/makimiru-deb-remove.log

check_contains() { # file, substring, label
    file="$1"; needle="$2"; label="$3"
    [ -f "$file" ] || { echo "FAIL: $file not found — run test-deb-install.sh/test-deb-remove.sh first" >&2; exit 1; }
    grep -qF "$needle" "$file" || {
        echo "FAIL: $label not found in $file" >&2
        exit 1
    }
    echo "ok: $label"
}

check_contains "$INSTALL_LOG" "MakiMiru: installing" "postinst intro line"
check_contains "$INSTALL_LOG" "makimiru-thumbnailer" "postinst names the thumbnailer program"
check_contains "$INSTALL_LOG" "org.gnome.NautilusPreviewer" "postinst names the previewer program"
check_contains "$INSTALL_LOG" "next time you log in" "postinst explains the per-user activation timing"
check_contains "$INSTALL_LOG" "system Sushi" "postinst states system Sushi is left alone"

check_contains "$REMOVE_LOG" "MakiMiru: removing" "prerm intro line"
# Release review (2026-11-17): these two checks still looked for the
# pre-SPEC-012 prerm wording ("currently logged-in user", "next login")
# and had been failing since that remediation changed prerm to clean up
# every local user itself — pinned to the current wording.
check_contains "$REMOVE_LOG" "every local user" "prerm explains it reverts every local user"
check_contains "$REMOVE_LOG" "not just currently logged-in ones" "prerm explains logged-out users are covered too"

echo "PASS: test-postinst-output"
