# Sushi (Kaiten fork)

This is Sushi, a quick previewer for Files (nautilus), the GNOME desktop file manager.

**This is the Kaiten fork**, adding an interactive 3D preview (STL/3MF/OBJ) viewer module and a standalone thumbnailer for GNOME Files' grid view, without modifying or replacing the system Sushi package.

## Installing Kaiten

**End users:** `sudo apt install ./kaiten_<version>_amd64.deb` (build one with `scripts/build-deb.sh`) — the only step. Previewer + thumbnailer binaries and a system-wide MIME type declaration install under `/opt/kaiten/` and `/usr`; the spacebar previewer's per-user D-Bus registration activates automatically, unprivileged, on your next graphical login (immediate for an already-open session: `systemctl --user start kaiten-activate.service`). Grid thumbnails work immediately, no login wait. `sudo apt remove kaiten` fully reverses it. See `debian/README` for exactly why the install is shaped this way (two real collisions with the system `gnome-sushi` package, found via testing, not assumed).

**Developers:** `scripts/container-build.sh` (builds via podman, no host apt changes) then `scripts/install-user.sh` (installs to `~/.local`, reversible via `scripts/uninstall-user.sh`) — the original dev-loop workflow, still the fastest way to iterate on source changes.

## Using Sushi

Sushi is a DBus-activated service. For Sushi to popup, applications will have to call the `ShowFile` method on the `org.gnome.NautilusPreviewer2` interface.

If you want to debug Sushi without a calling application, you can use the `sushi <filename>` command.

## Testing

Run the whole suite with `tests/run-all.sh deb` (against the built `.deb`) or `tests/run-all.sh dev` (against the `~/.local` dev install). It needs a logged-in GNOME session and installs/removes packages, so run it in a disposable VM, not on your daily machine.

## Performance notes

- The previewer target is roughly 750 ms cold / 250 ms warm for an 8 MB STL. Those figures were measured in a VM with software rendering (llvmpipe); real-GPU numbers are not yet measured.
- Thumbnails are generated one file at a time, and each one starts its own private Xvfb and WebKit render process, so expect roughly a second per file on first view (measured ~1 s per thumbnail in a software-rendered VM; real-GPU numbers not yet measured). A folder of hundreds of models fills in gradually the first time it is opened; after that GNOME serves the cached PNGs from `~/.cache/thumbnails/` instantly. Files over 100 MB, or over 5 million triangles, are skipped and keep the generic icon.
- A valid 3MF can make three.js's `3MFLoader` (upstream code, not ours) hold up to ~500 MB while unpacking it — see `web/vendor/README`.

## Reporting issues

Report Kaiten issues (3D preview, thumbnails, packaging) to this fork's own issue tracker, not to GNOME. Only report a non-3D Sushi bug to GNOME if it also happens with the stock `gnome-sushi` package and Kaiten removed (`sudo apt remove kaiten`).
