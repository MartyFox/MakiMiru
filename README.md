# Kaiten

**3D model previews and thumbnails for GNOME Files.**

Kaiten lets you see STL, 3MF and OBJ files in GNOME Files (Nautilus) without opening a slicer or CAD tool:

- **Spacebar preview:** select a model and press <kbd>Space</kbd> to open an interactive 3D view. Drag to rotate, scroll to zoom, right-drag to pan.
- **Grid thumbnails:** model files show a rendered thumbnail in icon view instead of a generic icon.

It's built for people with folders full of 3D-printing files who want to find the right one at a glance. The name *kaiten* (回転) means "rotation", as in *kaiten-zushi*, the conveyor-belt sushi bar. It's a nod to the spinnable preview and to the project it's built on, [GNOME Sushi](#built-on-gnome-sushi).

## Requirements

- Ubuntu 24.04 LTS or a derivative (for example Zorin OS 18), on amd64
- GNOME 46, with GNOME Files (Nautilus) 46

Other GNOME versions aren't supported. The previewer is a fork of Sushi 46, and it needs to match the Nautilus it runs alongside.

## Install

Build the package (this needs [podman](https://podman.io/); nothing is installed on your machine while building):

```sh
scripts/build-deb.sh
```

Then install it:

```sh
sudo apt install ./deb-build/kaiten_<version>_amd64.deb
```

- **Thumbnails** work straight away for every user.
- **Spacebar preview** turns on automatically the next time each user logs in. To turn it on in the session you're already in, run:

  ```sh
  systemctl --user start kaiten-activate.service
  ```

The system's own `gnome-sushi` package is left installed and untouched. Kaiten installs alongside it under `/opt/kaiten`.

## Uninstall

```sh
sudo apt remove kaiten
```

This removes the thumbnailer and the previewer, and it switches every local user back to the stock Sushi previewer, including users who aren't logged in. Thumbnails already cached in `~/.cache/thumbnails/` stay until GNOME clears them.

## How it works

Kaiten has two parts:

| Part | What it does | Installed to |
|---|---|---|
| Previewer | A fork of Sushi 46 with an added 3D viewer (three.js in a WebKitGTK view). Files that aren't 3D models still preview exactly as they do in stock Sushi. | `/opt/kaiten/previewer` |
| Thumbnailer | A standalone renderer that GNOME's thumbnail service runs for each model file. It brings its own private, headless X server, because GNOME runs thumbnailers with no display. | `/usr/libexec/kaiten-thumbnailer` |

A note on how the preview is switched on: GNOME Files asks D-Bus for "the previewer". Kaiten takes that role for each user by writing one small file, `~/.local/share/dbus-1/services/org.gnome.NautilusPreviewer.service`. A systemd user service writes it at login. The file is marked as Kaiten's, so uninstalling only ever removes Kaiten's own file. Remove that file and the stock Sushi takes over again. `debian/README` explains why the install is laid out this way.

**Limits:** files over 100 MB or over 5 million triangles aren't rendered. Previews show an error message instead, and thumbnails keep the generic icon.

## Built on GNOME Sushi

Kaiten is a fork of **[Sushi](https://gitlab.gnome.org/GNOME/sushi)**, the GNOME quick previewer by Cosimo Cecchi and the GNOME contributors. Sushi supplies everything except the 3D work: the previewer window, the D-Bus service, and the viewers for images, PDFs, text, audio, video and fonts.

**What Kaiten adds**
- `src/viewers/model.js`: the 3D viewer module.
- `web/`: the WebGL page it hosts (three.js), plus vendored libraries.
- `src/kaiten-thumbnailer.in`: the thumbnailer.
- `debian/` and `scripts/`: packaging that installs alongside the system Sushi.
- `tests/`: the test suite.

**What Kaiten changes in Sushi's own code** is kept deliberately small:
- `src/ui/mimeHandler.js`: routes STL, 3MF and OBJ files to the new viewer.
- `src/ui/mainWindow.js`: a one-line change.
- The build files, needed to ship the new pieces.

**Tracking upstream:** this repository keeps Sushi's full history. Kaiten's work sits on top of the `Release 46.0` tag, so `git diff 46.0` shows everything Kaiten changed. To pull in later Sushi fixes:

```sh
git remote add upstream https://gitlab.gnome.org/GNOME/sushi.git   # once
git fetch upstream
git merge upstream/gnome-46
```

Kaiten is not an official GNOME project. Please don't report Kaiten problems to GNOME (see [Reporting issues](#reporting-issues)).

To run the previewer directly on a file (handy for debugging):

```sh
/opt/kaiten/previewer/bin/sushi path/to/model.stl
```

## Development

The quickest way to try code changes, without building a `.deb`:

```sh
scripts/container-build.sh   # build inside podman; nothing installed on the host
scripts/install-user.sh      # install to ~/.local for your user only
scripts/uninstall-user.sh    # undo
```

### Testing

```sh
tests/run-all.sh deb   # test the built .deb (install, preview, thumbnails, removal)
tests/run-all.sh dev   # test the ~/.local developer install
```

The suite needs a logged-in GNOME session, and it installs and removes packages. **Run it in a disposable VM, not on your everyday machine.** `tests/test-deb-clean-install.sh` also installs the package into a bare Ubuntu 24.04 container, to check that the package's dependency list is complete.

## Performance

- **Preview:** about 750 ms to open an 8 MB STL the first time, and about 250 ms after that. These figures were measured in a VM with software rendering, so a real GPU should be faster. Real-GPU figures haven't been measured yet.
- **Thumbnails:** about 1 second per file the first time a folder is opened (also measured in a VM), so large folders fill in gradually. After that, GNOME shows cached thumbnails instantly.
- **Memory:** a large 3MF can briefly use up to about 500 MB while three.js unpacks it. This happens in the library itself; see `web/vendor/README`.

## Reporting issues

Report problems with 3D previews, thumbnails or packaging on [Kaiten's issue tracker](https://github.com/MartyFox/kaiten/issues).

If something unrelated to 3D models breaks, such as a PDF or image preview, check whether it also happens with stock Sushi. Run `sudo apt remove kaiten` and try again. Only report it to [GNOME Sushi](https://gitlab.gnome.org/GNOME/sushi/-/issues) if it does.

## License

- Kaiten, like Sushi, is licensed under the **GNU General Public License v2.0 or later**. See `COPYING`.
- The bundled third-party libraries are MIT-licensed:
  - [three.js](https://threejs.org/) 0.185.1
  - [fflate](https://github.com/101arrowz/fflate)
  - Their licence texts are in `web/vendor/`.
