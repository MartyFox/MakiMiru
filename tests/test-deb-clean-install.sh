#!/bin/sh
# Release review (2026-11-17): proves the .deb works on a machine that
# does NOT already have gnome-sushi — every earlier test machine did,
# which hid missing GI typelib dependencies. Installs the built .deb into
# a bare ubuntu:24.04 podman container with apt (so Depends: is all that
# pulls anything in), asserts gnome-sushi was not dragged in, imports
# every GI namespace the previewer and thumbnailer use, and renders a
# real thumbnail with the installed CLI (headless: it brings its own
# Xvfb).
#
# Requires: podman, network access for apt inside the container,
# deb-build/makimiru_*.deb (scripts/build-deb.sh).
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$DIR/.." && pwd)"
DEB="$(ls "$REPO"/deb-build/makimiru_*_amd64.deb 2>/dev/null | head -n1)"
[ -n "$DEB" ] || { echo "FAIL: no .deb under $REPO/deb-build — run scripts/build-deb.sh" >&2; exit 1; }
command -v podman >/dev/null || { echo "FAIL: podman not installed" >&2; exit 1; }

FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
python3 "$DIR/make-stl.py" 2000 "$FIX/sphere.stl"
python3 "$DIR/make-3mf.py" "$FIX/cube.3mf"
cp "$DIR/check-thumbnail-png.py" "$FIX/"
cp "$DEB" "$FIX/makimiru.deb"

podman run --rm -v "$FIX:/fix:Z" docker.io/library/ubuntu:24.04 sh -c '
    set -eu
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq --no-install-recommends /fix/makimiru.deb python3 python3-pil >/tmp/apt.log 2>&1 ||
        { tail -30 /tmp/apt.log; echo "FAIL: apt install of the .deb failed"; exit 1; }
    echo "ok: installed with apt on a bare ubuntu:24.04"

    if dpkg -l gnome-sushi 2>/dev/null | grep -q "^ii"; then
        echo "FAIL: gnome-sushi got installed — test would not prove anything"; exit 1
    fi
    echo "ok: gnome-sushi not present"

    gjs -c "
        imports.gi.versions.Gtk = \"3.0\";
        imports.gi.versions.WebKit2 = \"4.1\";
        imports.gi.versions.GtkSource = \"4\";
        imports.gi.versions.Soup = \"3.0\";
        imports.gi.versions.EvinceDocument = \"3.0\";
        imports.gi.versions.EvinceView = \"3.0\";
        imports.gi.versions.Gst = \"1.0\";
        imports.gi.versions.GstTag = \"1.0\";
        imports.gi.versions.GnomeDesktop = \"3.0\";
        const {Gdk, GdkPixbuf, Gio, GLib, GObject, Gst, GstTag, Gtk, GtkSource,
               Pango, Soup, WebKit2, EvinceDocument, EvinceView, GnomeDesktop} = imports.gi;
        print(\"ok: all GI namespaces import\");
    "

    for f in sphere.stl cube.3mf; do
        timeout 60 /usr/libexec/makimiru-thumbnailer /fix/$f /tmp/$f.png 256 2>/tmp/thumb.err ||
            { cat /tmp/thumb.err; echo "FAIL: thumbnailer failed on $f"; exit 1; }
        python3 /fix/check-thumbnail-png.py /tmp/$f.png 256
    done
    echo "ok: thumbnails rendered on a machine without gnome-sushi"

    mkdir -p /tmp/models && cp /fix/sphere.stl /fix/cube.3mf /tmp/models/
    XDG_CACHE_HOME=/tmp/cache timeout 120 makimiru-pregen /tmp/models 2>/tmp/pregen.err |
        grep -q "2 new, 0 already done, 0 failed" ||
        { cat /tmp/pregen.err; echo "FAIL: makimiru-pregen failed on a bare install"; exit 1; }
    echo "ok: makimiru-pregen works with only the declared dependencies"
'
echo "PASS: test-deb-clean-install"
