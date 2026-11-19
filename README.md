<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/makimiru_workmark_dark.png" width="480">
    <img src="docs/images/makimiru_workmark_light.png" alt="MakiMiru" width="480">
  </picture>
</p>

# MakiMiru

**3D model previews and thumbnails for GNOME Files.**

MakiMiru lets you see STL, 3MF and OBJ files in GNOME Files (Nautilus) without opening a slicer or CAD tool:

- **Spacebar preview:** select a model and press <kbd>Space</kbd> to open an interactive 3D view, with the model's size in millimetres and its triangle count in the corner. Drag to rotate, scroll to zoom, right-drag to pan.
- **Grid thumbnails:** model files show a rendered thumbnail in icon view instead of a generic icon.
- **Thumbnails ahead of time:** right-click a folder and choose **Generate 3D Thumbnails**, or run `makimiru-pregen`, so big folders open with every thumbnail already there.

It's built for people with folders full of 3D-printing files who want to find the right one at a glance. The name joins two Japanese words: *maki* (巻, "roll", as in *makizushi*, rolled sushi) and *miru* (見る, "to see"). Roll the model around and take a look. It's also a nod to the project it's built on, [GNOME Sushi](#built-on-gnome-sushi).

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
sudo apt install ./deb-build/makimiru_<version>_amd64.deb
```

- **Thumbnails** work straight away for every user.
- **Spacebar preview** turns on automatically the next time each user logs in. To turn it on in the session you're already in, run:

  ```sh
  systemctl --user start makimiru-activate.service
  ```

The system's own `gnome-sushi` package is left installed and untouched. MakiMiru installs alongside it under `/opt/makimiru`.

## Using it

### Preview keys

In the spacebar preview:

| Key | Does |
|---|---|
| <kbd>1</kbd> / <kbd>2</kbd> / <kbd>3</kbd> | Front / side / top view |
| <kbd>0</kbd> or <kbd>R</kbd> | Back to the starting view |
| <kbd>W</kbd> | Wireframe on/off |
| <kbd>I</kbd> | Size and triangle count on/off |
| <kbd>H</kbd> | Show these keys |

Sushi's own keys still work: <kbd>Space</kbd> or <kbd>Esc</kbd> closes, <kbd>F</kbd> goes full screen, and the arrow keys move to the next file.

Models are shown standing on the print bed, the way slicers show them: STL and 3MF files are treated as Z-up, OBJ files as Y-up. Sizes assume the file is in millimetres, which is the convention for 3D-printing files (STL and OBJ files don't record a unit).

### Making thumbnails ahead of time

Files makes thumbnails the first time you open a folder, about half a second each. For a big collection, make them in advance instead:

- **From Files:** right-click a folder (or empty space inside one) and choose **Generate 3D Thumbnails**. A notification appears when it's done. This needs the `python3-nautilus` package, which is installed alongside MakiMiru unless you skip recommended packages.
- **From a terminal:**

  ```sh
  makimiru-pregen ~/Documents/3D
  ```

Subfolders are included and hidden folders are skipped. Files that already have a thumbnail are skipped, so it's quick to run again after adding models. Thumbnails go straight into GNOME's thumbnail cache, the same place Files uses. Files uses the `large` size by default; if you've zoomed the grid view right in or use a HiDPI screen, also run it with `--size x-large`.

All the files are rendered in one process, which is several times faster than letting Files do them one by one.

## Uninstall

```sh
sudo apt remove makimiru
```

This removes the thumbnailer and the previewer, and it switches every local user back to the stock Sushi previewer, including users who aren't logged in. Thumbnails already cached in `~/.cache/thumbnails/` stay until GNOME clears them.

## How it works

MakiMiru has two parts:

| Part | What it does | Installed to |
|---|---|---|
| Previewer | A fork of Sushi 46 with an added 3D viewer (three.js in a WebKitGTK view). Files that aren't 3D models still preview exactly as they do in stock Sushi. | `/opt/makimiru/previewer` |
| Thumbnailer | A standalone renderer that GNOME's thumbnail service runs for each model file. It brings its own private, headless X server, because GNOME runs thumbnailers with no display. Its batch mode renders whole folders for `makimiru-pregen`. | `/usr/libexec/makimiru-thumbnailer` |
| Pre-generation | `makimiru-pregen`, plus a small Files extension that adds **Generate 3D Thumbnails** to folder menus. | `/usr/bin/makimiru-pregen`, `/usr/share/nautilus-python/extensions/` |

A note on how the preview is switched on: GNOME Files asks D-Bus for "the previewer". MakiMiru takes that role for each user by writing one small file, `~/.local/share/dbus-1/services/org.gnome.NautilusPreviewer.service`. A systemd user service writes it at login. The file is marked as MakiMiru's, so uninstalling only ever removes MakiMiru's own file. Remove that file and the stock Sushi takes over again. `debian/README` explains why the install is laid out this way.

**Limits:** files over 100 MB or over 5 million triangles aren't rendered. Previews show an error message instead, and thumbnails keep the generic icon.

## Built on GNOME Sushi

MakiMiru is a fork of **[Sushi](https://gitlab.gnome.org/GNOME/sushi)**, the GNOME quick previewer by Cosimo Cecchi and the GNOME contributors. Sushi supplies everything except the 3D work: the previewer window, the D-Bus service, and the viewers for images, PDFs, text, audio, video and fonts.

**What MakiMiru adds**
- `src/viewers/model.js`: the 3D viewer module.
- `web/`: the WebGL page it hosts (three.js), plus vendored libraries.
- `src/makimiru-thumbnailer.in`: the thumbnailer, and its batch mode behind `makimiru-pregen`.
- `data/makimiru-nautilus.py.in`: the Files extension for **Generate 3D Thumbnails**.
- `debian/` and `scripts/`: packaging that installs alongside the system Sushi.
- `tests/`: the test suite.

**What MakiMiru changes in Sushi's own code** is kept deliberately small:
- `src/ui/mimeHandler.js`: routes STL, 3MF and OBJ files to the new viewer.
- `src/ui/mainWindow.js`: a one-line change.
- The build files, needed to ship the new pieces.

**Tracking upstream:** this repository keeps Sushi's full history. MakiMiru's work sits on top of the `Release 46.0` tag, so `git diff 46.0` shows everything MakiMiru changed. To pull in later Sushi fixes:

```sh
git remote add upstream https://gitlab.gnome.org/GNOME/sushi.git   # once
git fetch upstream
git merge upstream/gnome-46
```

MakiMiru is not an official GNOME project. Please don't report MakiMiru problems to GNOME (see [Reporting issues](#reporting-issues)).

To run the previewer directly on a file (handy for debugging):

```sh
/opt/makimiru/previewer/bin/sushi path/to/model.stl
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

- **Preview:** on a desktop with an AMD Radeon GPU, a small STL (about 100 KB) opens in about 130 ms. In a VM with software rendering, an 8 MB STL took about 750 ms the first time and about 250 ms after that. Large models on a real GPU haven't been timed yet.
- **Thumbnails:** about 0.6 seconds per file on the same desktop (about 1 second in the VM). A large folder fills in gradually the first time it's opened; after that, GNOME shows the cached thumbnails instantly.
- **Pre-generation:** batching avoids starting a renderer per file. In the VM, 6 thumbnails took 6.6 s one by one and 2.0 s batched.
- **Memory:** a large 3MF can briefly use up to about 500 MB while three.js unpacks it. This happens in the library itself; see `web/vendor/README`.

## Reporting issues

Report problems with 3D previews, thumbnails or packaging on [MakiMiru's issue tracker](https://github.com/MartyFox/makimiru/issues).

If something unrelated to 3D models breaks, such as a PDF or image preview, check whether it also happens with stock Sushi. Run `sudo apt remove makimiru` and try again. Only report it to [GNOME Sushi](https://gitlab.gnome.org/GNOME/sushi/-/issues) if it does.

## License

- MakiMiru, like Sushi, is licensed under the **GNU General Public License v2.0 or later**. See `COPYING`.
- The bundled third-party libraries are MIT-licensed:
  - [three.js](https://threejs.org/) 0.185.1
  - [fflate](https://github.com/101arrowz/fflate)
  - Their licence texts are in `web/vendor/`.
