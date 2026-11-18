#!/bin/sh
# SPEC-011 test 1: installs the built .deb, asserts the previewer owns
# org.gnome.NautilusPreviewer and real grid thumbnails render — the
# live proof deferred from SPEC-010 (which could only prove the CLI
# correct via direct invocation, not via GNOME's real, bwrap-sandboxed
# thumbnail factory).
#
# Requires: deb-build/makimiru_*.deb already built (scripts/build-deb.sh),
# sudo (installs system-wide), a makimiru-activate.service systemd
# --user unit run at least once (normally happens on next login — this
# test triggers it manually via `systemctl --user start`, matching what
# a real login does, since VM test sessions don't re-login mid-run).
set -eu
. "$(dirname "$0")/lib.sh"
DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$DIR/.." && pwd)"

DEB="$(ls "$REPO"/deb-build/makimiru_*_amd64.deb 2>/dev/null | head -n1)"
[ -n "$DEB" ] || { echo "FAIL: no .deb found under $REPO/deb-build — run scripts/build-deb.sh" >&2; exit 1; }

echo "installing $DEB..."
# --reinstall: a rebuilt .deb keeps the same version, and apt may then
# report "already the newest version" and silently keep the previously
# installed build (hit during the 2026-11-17 release review).
sudo apt-get install --reinstall -y "$DEB" >/tmp/makimiru-deb-install.log 2>&1 || {
    echo "FAIL: apt install failed:" >&2
    cat /tmp/makimiru-deb-install.log >&2
    exit 1
}

dpkg -l makimiru | grep -q '^ii' || { echo "FAIL: makimiru not reported installed by dpkg" >&2; exit 1; }

# Per-user D-Bus activation: normally happens on next graphical login
# (systemd --user + graphical-session.target.wants) — trigger it once
# manually here, matching what a real login does, since this test
# doesn't re-login the session.
systemctl --user start makimiru-activate.service
[ -f "$HOME/.local/share/dbus-1/services/org.gnome.NautilusPreviewer.service" ] || {
    echo "FAIL: makimiru-activate-user did not write the per-user D-Bus service file" >&2
    exit 1
}
dbus-send --session --type=method_call --dest=org.freedesktop.DBus / \
    org.freedesktop.DBus.ReloadConfig >/dev/null 2>&1 || true

pkill -9 -f "[N]autilusPreviewer" 2>/dev/null || true
sleep 1

show_v2 "file:///etc/os-release"; close_preview
sleep 1
cmd="$(owner_cmdline)"
case "$cmd" in
    */opt/makimiru/previewer/libexec/org.gnome.NautilusPreviewer*) ;;
    *) echo "FAIL: previewer owner is not the .deb-installed binary: $cmd" >&2; exit 1 ;;
esac
echo "ok: previewer owns the bus via the .deb-installed binary"

# Thumbnailer: system-wide, no per-user step — confirm it's directly
# invokable immediately (test-deb-install doesn't re-verify the full
# CLI matrix here, that's test-thumbnailer-cli.sh's job; this just
# proves the .deb placed a working binary at the expected system path).
[ -x /usr/libexec/makimiru-thumbnailer ] || { echo "FAIL: /usr/libexec/makimiru-thumbnailer not installed" >&2; exit 1; }

# Live grid-thumbnail proof — the check SPEC-010 could not perform from
# a per-user-only install.
#
# External review, Medium, real gap: an earlier version only used
# sphere.stl and only checked "some file exists in large/" — but the
# system also has f3d's own pre-existing .thumbnailer entries for
# model/stl (confirmed via /usr/share/thumbnailers/f3d-plugin-native.
# thumbnailer), so a passing STL thumbnail
# doesn't actually prove *our* thumbnailer ran — f3d could have won
# that one. f3d has no 3MF reader at all (same file, no model/3mf
# entry) — a .3mf fixture is the unambiguous case with no competing
# thumbnailer on this system. Both fixtures are checked; the .3mf one
# is what actually proves MakiMiru's own thumbnailer path ran.
TMP="${TMPDIR:-/tmp}/makimiru-deb-grid-test"
rm -rf "$TMP" "$HOME/.cache/thumbnails"
mkdir -p "$TMP"
mkdir -p "${TMPDIR:-/tmp}/makimiru-stl"
[ -f "${TMPDIR:-/tmp}/makimiru-stl/sphere-20k.stl" ] || python3 "$DIR/make-stl.py" 20000 "${TMPDIR:-/tmp}/makimiru-stl/sphere-20k.stl"
[ -f "${TMPDIR:-/tmp}/makimiru-3mf-obj/cube.3mf" ] || {
    mkdir -p "${TMPDIR:-/tmp}/makimiru-3mf-obj"
    python3 "$DIR/make-3mf.py" "${TMPDIR:-/tmp}/makimiru-3mf-obj/cube.3mf"
}
cp "${TMPDIR:-/tmp}/makimiru-stl/sphere-20k.stl" "$TMP/sphere.stl"
cp "${TMPDIR:-/tmp}/makimiru-3mf-obj/cube.3mf" "$TMP/cube.3mf"

pkill -9 nautilus 2>/dev/null || true
sleep 1
# Release review (2026-11-17): gnome-desktop gives each sandboxed
# thumbnail its own host /tmp/gnome-desktop-thumbnailer-XXXXXX and
# can't delete it if the thumbnailer leaves files behind (Xvfb's
# .X11-unix / lock) — one leaked directory per thumbnail. Count them.
leaked_before="$(ls -d /tmp/gnome-desktop-thumbnailer-* 2>/dev/null | wc -l)"
export DISPLAY="${DISPLAY:-:0}"
nohup nautilus "$TMP" >/tmp/makimiru-deb-nautilus.log 2>&1 &
sleep 12
pkill -9 nautilus 2>/dev/null || true

# GNOME's thumbnail cache filename is md5(uri).png — compute the exact
# expected path for cube.3mf (not just "does /large/ have anything in
# it") so we can validate that specific file's actual content, not any
# file that happens to be there.
cube_uri="file://$TMP/cube.3mf"
cube_hash="$(python3 -c "import hashlib,sys; print(hashlib.md5(sys.argv[1].encode()).hexdigest())" "$cube_uri")"
cube_thumb="$HOME/.cache/thumbnails/large/$cube_hash.png"

[ -f "$cube_thumb" ] || {
    echo "FAIL: no thumbnail generated for cube.3mf at expected path $cube_thumb — see /tmp/makimiru-deb-nautilus.log" >&2
    find "$HOME/.cache/thumbnails" -type f >&2 2>/dev/null || true
    exit 1
}

leaked_after="$(ls -d /tmp/gnome-desktop-thumbnailer-* 2>/dev/null | wc -l)"
[ "$leaked_after" -le "$leaked_before" ] || {
    echo "FAIL: thumbnailing leaked $((leaked_after - leaked_before)) /tmp/gnome-desktop-thumbnailer-* dir(s):" >&2
    ls -la /tmp/gnome-desktop-thumbnailer-* >&2
    exit 1
}
echo "ok: no gnome-desktop thumbnailer temp dirs leaked"

# Validate it's a real render, not a blank/degenerate capture (same
# check test-thumbnailer-cli.sh uses for direct CLI invocation).
python3 "$DIR/check-thumbnail-png.py" "$cube_thumb" 256 || {
    echo "FAIL: cube.3mf thumbnail exists but failed content validation" >&2
    exit 1
}
echo "ok: real grid thumbnail generated and validated for cube.3mf (no f3d competitor for 3MF — proves MakiMiru's own thumbnailer ran)"

sphere_count="$(find "$HOME/.cache/thumbnails/large" -type f 2>/dev/null | wc -l)"
echo "ok: $sphere_count total thumbnail(s) in ~/.cache/thumbnails/large (includes sphere.stl, which f3d could also handle — cube.3mf above is the load-bearing proof)"

echo "PASS: test-deb-install"
