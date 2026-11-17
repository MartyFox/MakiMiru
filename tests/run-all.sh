#!/bin/sh
# Runs the whole suite in a fixed, self-contained order and prints one
# PASS/FAIL line per test plus a summary. Exit status: number of failures
# (0 = all passed).
#
#   tests/run-all.sh deb   test the built .deb (deb-build/kaiten_*.deb):
#                          installs it, runs every applicable test against
#                          /opt/kaiten + /usr, removes it, checks the
#                          postinst/prerm output, reinstalls it.
#   tests/run-all.sh dev   test the per-user dev install (~/.local, from
#                          scripts/container-build.sh + install-user.sh).
#
# Needs a logged-in GNOME session on this machine (tests drive the real
# previewer over D-Bus and open Nautilus) — run it inside a
# disposable VM, e.g. over ssh: the session environment below is
# filled in when missing. Per-test logs: $LOGDIR/<test>.log.
#
# Release review (2026-11-17): before this script the suite had no
# single entry point; tests silently depended on run order (fixtures in
# /tmp, install logs) and on six KAITEN_TEST_* variables being set
# by hand for a .deb install, so "the full suite passes" wasn't
# reproducible.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
MODE="${1:-}"
LOGDIR="${LOGDIR:-${TMPDIR:-/tmp}/kaiten-test-logs}"
PER_TEST_TIMEOUT=300

uid="$(id -u)"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$uid}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"
export DISPLAY="${DISPLAY:-:0}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"

# Tests that only make sense for one install flavour.
DEV_ONLY="test-owner-pid.sh"           # cycles install-user.sh/uninstall-user.sh
DEB_LIFECYCLE="test-deb-install.sh test-deb-remove.sh test-postinst-output.sh"

case "$MODE" in
deb)
    P=/opt/kaiten/previewer
    export KAITEN_TEST_BIN=/usr/libexec/kaiten-thumbnailer
    export KAITEN_TEST_PREFIX="$P"
    export KAITEN_TEST_LIBDIR="$P/lib/$(uname -m)-linux-gnu"
    export KAITEN_TEST_PKGDATADIR="$P/share/sushi"
    export KAITEN_TEST_MIME_DIR=/usr/share/mime/packages
    skip="$DEV_ONLY $DEB_LIFECYCLE"
    first="test-deb-install.sh"
    last="test-deb-remove.sh test-postinst-output.sh test-deb-install.sh"
    ;;
dev)
    skip="$DEB_LIFECYCLE"
    first=""
    last=""
    ;;
*)
    echo "usage: $0 deb|dev" >&2
    exit 2
    ;;
esac

middle=""
for t in "$DIR"/test-*.sh; do
    t="$(basename "$t")"
    case " $skip " in *" $t "*) continue ;; esac
    middle="$middle $t"
done

mkdir -p "$LOGDIR"
pass=0
fail=0
failed=""
for t in $first $middle $last; do
    start="$(date +%s)"
    if timeout "$PER_TEST_TIMEOUT" sh "$DIR/$t" >"$LOGDIR/$t.log" 2>&1; then
        result=PASS; pass=$((pass + 1))
    else
        result="FAIL($?)"; fail=$((fail + 1)); failed="$failed $t"
    fi
    echo "$result $t $(( $(date +%s) - start ))s"
done

echo "---"
echo "$MODE mode: $pass passed, $fail failed${failed:+ —$failed} (logs: $LOGDIR)"
exit "$fail"
