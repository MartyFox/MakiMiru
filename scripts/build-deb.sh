#!/bin/sh
# SPEC-011: build a real, installable .deb — prebuilt binaries, no
# podman/build toolchain needed on the end user's machine.
#
# Two meson passes from the same source tree, not one — discovered via
# a real `dpkg -i` collision test, not assumed up front:
#
#   Pass 1 (--prefix=/usr): the thumbnailer binary, the shared web/
#   assets (needed under /usr specifically — SPEC-010's bwrap-sandbox
#   finding: GNOME's thumbnail factory can only see /usr), and the MIME
#   override. None of these collide with the system gnome-sushi
#   package — their names/paths are unique to this fork.
#
#   Pass 2 (--prefix=/opt/makimiru/previewer): the previewer binary and
#   everything private to it (libsushi, its typelib/gir, both
#   gresources, the gtksourceview style, the appdata.xml). These *do*
#   collide with the real gnome-sushi package byte-for-byte at the same
#   paths under /usr — confirmed with `comm -12` against
#   `dpkg -L gnome-sushi` after a first `--prefix=/usr` attempt hit
#   `dpkg: error ... trying to overwrite '/usr/bin/sushi'`. Installing
#   under a private, package-owned prefix instead avoids the collision
#   entirely and needs no Conflicts:/Replaces: against gnome-sushi
#   (which would violate Part I's "don't modify/replace system Sushi"
#   goal). No per-user copy of this (comparatively large, many-locale-
#   file) tree is needed — it's read-only shared code, not user data;
#   only the small D-Bus service file that points at it needs to be
#   per-user (see below).
#
# Activation model (SPEC-011 decision, approved): almost everything is
# genuinely system-wide with no per-user step at all — including the
# thumbnailer's `.thumbnailer` registration, whose filename is unique
# to this fork and was *not* actually forced to be per-user (an earlier
# version of this script moved it into the per-user path unnecessarily,
# out of surface-level consistency with the D-Bus file rather than a
# real constraint — simplified back out once that became clear). The
# ONLY thing that must stay per-user is the D-Bus service file itself,
# because a system-wide one would collide with gnome-sushi's own file
# of the same name. `makimiru-activate.service` (a systemd --user
# unit, auto-enabled via a `graphical-session.target.wants` symlink —
# the same convention `update-notifier` uses on the reference machine)
# runs `makimiru-activate-user` on every graphical login to reconcile
# that one file against a template.
set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE=makimiru-build
VERSION="${MAKIMIRU_DEB_VERSION:-1.0.0-1}"
PKGROOT="$REPO/deb-build/pkgroot"
PREVIEWER_PREFIX=/opt/makimiru/previewer

podman build -q -t "$IMAGE" -f "$REPO/scripts/Containerfile.build" "$REPO/scripts"

rm -rf "$REPO/deb-build"
mkdir -p "$PKGROOT" "$REPO/deb-build/sys-stage" "$REPO/deb-build/previewer-stage"

podman run --rm --userns=keep-id -v "$REPO:/src:rw" \
    "$IMAGE" sh -c '
    set -eu
    meson setup deb-build/sys-build --prefix=/usr --libexecdir libexec --reconfigure >/dev/null
    meson compile -C deb-build/sys-build
    meson install -C deb-build/sys-build --destdir /src/deb-build/sys-stage >/dev/null

    meson setup deb-build/previewer-build --prefix="'"$PREVIEWER_PREFIX"'" --libexecdir libexec --reconfigure >/dev/null
    meson compile -C deb-build/previewer-build
    meson install -C deb-build/previewer-build --destdir /src/deb-build/previewer-stage >/dev/null
'

SYS="$REPO/deb-build/sys-stage"
PREV="$REPO/deb-build/previewer-stage"

# --- Pass 1 (/usr) contributions: thumbnailer, web/ assets, MIME
# override. Deliberately NOT taking this pass's copy of the previewer
# binary/libs/resources or /usr/bin/sushi (the sushi.in CLI wrapper) —
# those collide with gnome-sushi and pass 2 supplies non-colliding
# versions of the ones that are actually needed (the previewer itself).
mkdir -p "$PKGROOT/usr"
cp -a "$SYS/usr/libexec" "$PKGROOT/usr/"
rm -f "$PKGROOT/usr/libexec/org.gnome.NautilusPreviewer"
cp -a "$SYS/usr/share" "$PKGROOT/usr/"
rm -rf "$PKGROOT/usr/share/sushi/gir-1.0" \
       "$PKGROOT/usr/share/sushi/gtksourceview-4" \
       "$PKGROOT/usr/share/sushi/org.gnome.NautilusPreviewer.data.gresource" \
       "$PKGROOT/usr/share/sushi/org.gnome.NautilusPreviewer.src.gresource" \
       "$PKGROOT/usr/share/metainfo" \
       "$PKGROOT/usr/share/dbus-1"
rm -rf "$PKGROOT/usr/lib"
[ -d "$SYS/usr/bin" ] && [ "$(ls -A "$SYS/usr/bin" 2>/dev/null | grep -v '^sushi$')" ] && {
    echo "unexpected extra files under pass 1's /usr/bin — check what changed" >&2
    exit 1
}

# --- Pass 2 (/opt/makimiru/previewer) contributions: the entire
# previewer payload, at its own private, non-colliding prefix. ---
mkdir -p "$(dirname "$PKGROOT$PREVIEWER_PREFIX")"
cp -a "$PREV$PREVIEWER_PREFIX" "$PKGROOT$PREVIEWER_PREFIX"

# The D-Bus service file this pass generated already has the correct,
# final Exec= (pointing at $PREVIEWER_PREFIX/libexec/... — a stable
# system path, not something that needs per-user resolution) — pull
# it out as the per-user activation template.
DBUS_SVC="$PKGROOT$PREVIEWER_PREFIX/share/dbus-1/services/org.gnome.NautilusPreviewer.service"
[ -f "$DBUS_SVC" ] || { echo "expected $DBUS_SVC from the previewer pass, not found" >&2; exit 1; }
mkdir -p "$PKGROOT/usr/share/makimiru/activation-templates"
mv "$DBUS_SVC" "$PKGROOT/usr/share/makimiru/activation-templates/"
rmdir --ignore-fail-on-non-empty \
    "$PKGROOT$PREVIEWER_PREFIX/share/dbus-1/services" \
    "$PKGROOT$PREVIEWER_PREFIX/share/dbus-1" 2>/dev/null || true

# --- systemd --user unit + auto-enable .wants symlink (same convention
# real packages on this reference machine use, e.g. update-notifier's
# graphical-session.target.wants entries) ---
mkdir -p "$PKGROOT/usr/lib/systemd/user/graphical-session.target.wants"
install -m 644 "$REPO/debian/makimiru-activate.service" \
    "$PKGROOT/usr/lib/systemd/user/makimiru-activate.service"
ln -s ../makimiru-activate.service \
    "$PKGROOT/usr/lib/systemd/user/graphical-session.target.wants/makimiru-activate.service"

mkdir -p "$PKGROOT/usr/libexec"
install -m 755 "$REPO/debian/makimiru-activate-user" \
    "$PKGROOT/usr/libexec/makimiru-activate-user"

# --- DEBIAN control files ---
mkdir -p "$PKGROOT/DEBIAN"
sed "s/@VERSION@/$VERSION/" "$REPO/debian/control.in" > "$PKGROOT/DEBIAN/control"
install -m 755 "$REPO/debian/postinst" "$PKGROOT/DEBIAN/postinst"
install -m 755 "$REPO/debian/prerm" "$PKGROOT/DEBIAN/prerm"

# --- Build ---
OUT="$REPO/deb-build/makimiru_${VERSION}_amd64.deb"
dpkg-deb --build --root-owner-group "$PKGROOT" "$OUT"

echo "Built: $OUT"
