#!/bin/sh
# SPEC-003 test 1: after install the fork owns the previewer name; after
# uninstall system Sushi does. Leaves the fork installed.
set -eu
. "$(dirname "$0")/lib.sh"
REPO="$(cd "$(dirname "$0")/.." && pwd)"

show_v2 "file:///etc/os-release"; close_preview   # trigger activation
sleep 1
cmd="$(owner_cmdline)"
case "$cmd" in
    *"$HOME/.local/libexec/org.gnome.NautilusPreviewer"*) ;;
    *) echo "FAIL: owner is not the fork: $cmd" >&2; exit 1 ;;
esac
echo "fork owns name: OK"

"$REPO/scripts/uninstall-user.sh" >/dev/null
sleep 1
show_v2 "file:///etc/os-release" || true; close_preview || true
sleep 1
cmd="$(owner_cmdline)"
case "$cmd" in
    */usr/libexec/org.gnome.NautilusPreviewer*) ;;
    *) echo "FAIL: owner after uninstall is not system Sushi: $cmd" >&2; exit 1 ;;
esac
echo "system Sushi restored: OK"

"$REPO/scripts/install-user.sh" >/dev/null
sleep 1
show_v2 "file:///etc/os-release"; close_preview
sleep 1
cmd="$(owner_cmdline)"
case "$cmd" in
    *"$HOME/.local/libexec/org.gnome.NautilusPreviewer"*) ;;
    *) echo "FAIL: reinstall did not restore fork ownership: $cmd" >&2; exit 1 ;;
esac
echo "PASS: test-owner-pid"
