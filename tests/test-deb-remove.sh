#!/bin/sh
# SPEC-011 test 2: apt remove cleanly retracts the previewer
# registration (immediately, for the currently logged-in user, per
# debian/prerm) and system Sushi reclaims the bus — same proof pattern
# uninstall-user.sh's own tests already use for the dev workflow.
set -eu
. "$(dirname "$0")/lib.sh"

dpkg -l kaiten 2>/dev/null | grep -q '^ii' || {
    echo "FAIL: kaiten is not currently installed — run test-deb-install.sh first" >&2
    exit 1
}

sudo apt-get remove -y kaiten >/tmp/kaiten-deb-remove.log 2>&1 || {
    echo "FAIL: apt remove failed:" >&2
    cat /tmp/kaiten-deb-remove.log >&2
    exit 1
}

grep -q "Kaiten: removing" /tmp/kaiten-deb-remove.log || {
    echo "FAIL: prerm's transparency output not found in apt remove output" >&2
    exit 1
}

[ ! -f "$HOME/.local/share/dbus-1/services/org.gnome.NautilusPreviewer.service" ] || {
    echo "FAIL: per-user D-Bus service file still present after apt remove" >&2
    exit 1
}
[ ! -x /usr/libexec/kaiten-thumbnailer ] || {
    echo "FAIL: /usr/libexec/kaiten-thumbnailer still present after apt remove" >&2
    exit 1
}
[ ! -d /opt/kaiten ] || {
    echo "FAIL: /opt/kaiten still present after apt remove" >&2
    exit 1
}

dbus-send --session --type=method_call --dest=org.freedesktop.DBus / \
    org.freedesktop.DBus.ReloadConfig >/dev/null 2>&1 || true
pkill -9 -f "[N]autilusPreviewer" 2>/dev/null || true
sleep 1

show_v2 "file:///etc/os-release" || true; close_preview || true
sleep 1
cmd="$(owner_cmdline)"
case "$cmd" in
    */usr/libexec/org.gnome.NautilusPreviewer*) ;;
    *) echo "FAIL: owner after apt remove is not system Sushi: $cmd" >&2; exit 1 ;;
esac
echo "ok: system Sushi reclaimed the bus after apt remove"

echo "PASS: test-deb-remove"
