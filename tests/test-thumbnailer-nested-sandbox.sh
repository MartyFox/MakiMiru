#!/bin/sh
# Regression (host, 2026-11-18): with userns sysctl 0 the thumbnailer
# enabled WebKit's sandbox inside GNOME's thumbnail-factory bwrap, which
# can't nest — exit 133 on every grid thumbnail. Recreates that: sysctl 0,
# installed thumbnailer run under gnome-desktop's bwrap args (minus its
# seccomp fd), PNG checked. Needs sudo and the .deb installed.
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"
BIN=/usr/libexec/kaiten-thumbnailer
SYSCTL=/proc/sys/kernel/apparmor_restrict_unprivileged_userns

[ -x "$BIN" ] || { echo "SKIP: $BIN not installed (deb mode only)"; exit 0; }
command -v bwrap >/dev/null || { echo "FAIL: bwrap not installed" >&2; exit 1; }

WORK="$(mktemp -d)"
orig=""
[ -f "$SYSCTL" ] && orig="$(cat "$SYSCTL")"
cleanup() {
    [ -n "$orig" ] && echo "$orig" | sudo tee "$SYSCTL" >/dev/null
    rm -rf "$WORK"
}
trap cleanup EXIT

[ -n "$orig" ] && echo 0 | sudo tee "$SYSCTL" >/dev/null

python3 "$DIR/make-stl.py" 2000 "$WORK/in.stl" >/dev/null
mkdir "$WORK/tmp"

rc=0
timeout 60 bwrap \
    --ro-bind /usr /usr --ro-bind-try /etc/ld.so.cache /etc/ld.so.cache \
    --symlink /usr/bin /bin --symlink /usr/lib64 /lib64 \
    --symlink /usr/lib /lib --symlink /usr/sbin /sbin \
    --ro-bind-try /var/cache/fontconfig /var/cache/fontconfig \
    --ro-bind-try /etc/alternatives /etc/alternatives \
    --proc /proc --dev /dev --chdir / --setenv GIO_USE_VFS local \
    --unshare-all --die-with-parent \
    --bind "$WORK/tmp" /tmp --ro-bind "$WORK/in.stl" /tmp/gnome-desktop-file-to-thumbnail.stl \
    "$BIN" /tmp/gnome-desktop-file-to-thumbnail.stl /tmp/gnome-desktop-thumbnailer.png 128 \
    >"$WORK/log" 2>&1 || rc=$?

if [ "$rc" -ne 0 ]; then
    grep -vE 'keysym|xkbcomp|not fatal|^$' "$WORK/log" | tail -15 >&2
    echo "FAIL: thumbnailer exited $rc inside a GNOME-style bwrap sandbox with userns sysctl=0" >&2
    exit 1
fi
python3 "$DIR/check-thumbnail-png.py" "$WORK/tmp/gnome-desktop-thumbnailer.png" 128

# bwrap leaves an empty mount-point file for the ro-bound input; gnome-desktop
# removes that and the PNG itself. Anything else would block its cleanup.
left="$(find "$WORK/tmp" -mindepth 1 ! -name gnome-desktop-thumbnailer.png \
    ! -name gnome-desktop-file-to-thumbnail.stl | head -5)"
if [ -n "$left" ]; then
    echo "FAIL: thumbnailer left files in the factory's temp dir (it would leak on the host):" >&2
    echo "$left" >&2
    exit 1
fi
echo "PASS: test-thumbnailer-nested-sandbox"
