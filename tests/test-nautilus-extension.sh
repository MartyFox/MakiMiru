#!/bin/sh
# "Generate 3D Thumbnails" Files extension (data/makimiru-nautilus.py.in):
# loads the installed extension with the real Nautilus 4.0 bindings and
# checks which selections get the menu item (local folders, the folder
# background) and which don't (files, remote locations), and that the
# command it would run exists. Needs the .deb and python3-nautilus.
set -eu
EXT=/usr/share/nautilus-python/extensions/makimiru-nautilus.py
[ -f "$EXT" ] || { echo "SKIP: $EXT not installed (deb mode only)"; exit 0; }
python3 -c 'import gi; gi.require_version("Nautilus", "4.0")' 2>/dev/null ||
    { echo "SKIP: Nautilus 4.0 Python bindings not installed (python3-nautilus)"; exit 0; }

python3 - "$EXT" <<'EOF'
import importlib.util, os, sys
spec = importlib.util.spec_from_file_location('ext', sys.argv[1])
ext = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ext)

class Loc:
    def __init__(self, path): self.path = path
    def get_path(self): return self.path

class F:
    def __init__(self, path, is_dir): self.loc, self.dir = Loc(path), is_dir
    def get_location(self): return self.loc
    def is_directory(self): return self.dir

p = ext.MakiMiruPregen()
def labels(items): return [i.props.label for i in items]
cases = {
    'background': (p.get_background_items(F('/home/u/models', True)), ['Generate 3D Thumbnails']),
    'two folders': (p.get_file_items([F('/a', True), F('/b', True)]), ['Generate 3D Thumbnails']),
    'a file': (p.get_file_items([F('/a/x.stl', False)]), []),
    'folder + file': (p.get_file_items([F('/a', True), F('/a/x.stl', False)]), []),
    'remote folder': (p.get_file_items([F(None, True)]), []),
}
bad = 0
for name, (items, want) in cases.items():
    ok = labels(items) == want
    bad += not ok
    print(f"{'ok' if ok else 'FAIL'}: {name} -> {labels(items)}")
if not os.access(ext.PREGEN, os.X_OK):
    print(f'FAIL: extension runs {ext.PREGEN}, which is not executable'); bad += 1
sys.exit(1 if bad else 0)
EOF
echo "PASS: test-nautilus-extension"
