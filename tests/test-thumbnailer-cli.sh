#!/bin/sh
# SPEC-010 test 1: the CLI, invoked directly (not via D-Bus, not via
# GNOME's own thumbnail factory — GNOME's factory only runs
# thumbnailers from /usr, so it can't be exercised from a per-user install), against every existing
# good/bad/bomb fixture from SPEC-004-009. Good fixtures produce a valid
# PNG within the timeout; bad ones exit non-zero, write no PNG, and never
# hang.
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$DIR/.." && pwd)"
. "$DIR/thumbnailer-lib.sh"
assert_thumbnailer_fresh "$REPO"
BIN="${MAKIMIRU_TEST_BIN:-$HOME/.local/libexec/makimiru-thumbnailer}"

export DISPLAY="${DISPLAY:-:0}"

STL="${TMPDIR:-/tmp}/makimiru-stl"
OBJ3MF="${TMPDIR:-/tmp}/makimiru-3mf-obj"
BAD="${TMPDIR:-/tmp}/makimiru-bad"
BOMBS="${TMPDIR:-/tmp}/makimiru-bombs"
mkdir -p "$STL" "$OBJ3MF" "$BAD" "$BOMBS"
[ -f "$STL/sphere-20k.stl" ] || python3 "$DIR/make-stl.py" 20000 "$STL/sphere-20k.stl"
[ -f "$OBJ3MF/cube.3mf" ] || python3 "$DIR/make-3mf.py" "$OBJ3MF/cube.3mf"
[ -f "$OBJ3MF/cube.obj" ] || python3 "$DIR/make-obj.py" "$OBJ3MF/cube.obj"
[ -f "$BAD/big.stl" ] || python3 "$DIR/make-bad-fixtures.py" "$BAD"
[ -f "$BOMBS/zipbomb.3mf" ] || python3 "$DIR/make-bomb-fixtures.py" "$BOMBS"

OUTDIR="${TMPDIR:-/tmp}/makimiru-thumb-cli-test"
mkdir -p "$OUTDIR"
rm -f "$OUTDIR"/*.png

check_good() { # path label
    path="$1"; label="$2"
    out="$OUTDIR/$label.png"
    rm -f "$out"
    if ! timeout 15 "$BIN" "$path" "$out" 256 >"$OUTDIR/$label.err" 2>&1; then
        echo "FAIL: $label expected success, got non-zero exit; log:" >&2
        cat "$OUTDIR/$label.err" >&2
        exit 1
    fi
    [ -s "$out" ] || { echo "FAIL: $label exited 0 but wrote no/empty PNG" >&2; exit 1; }
    # External review, Low: non-empty alone doesn't prove it's a real
    # render — check PNG signature, dimensions, and that it isn't a
    # single uniform color (a blank offscreen-capture regression).
    python3 "$DIR/check-thumbnail-png.py" "$out" 256 || exit 1
    echo "ok (good): $label -> $(wc -c < "$out") bytes"
}

check_bad() { # path label
    path="$1"; label="$2"
    out="$OUTDIR/$label.png"
    rm -f "$out"
    # Must be an if/else, not a bare statement followed by `code=$?` —
    # under `set -e`, a bare command's non-zero exit aborts the script
    # immediately (before `code=$?` ever runs), and this command is
    # *expected* to fail. if/while/until conditions are the POSIX-defined
    # exemption from errexit. (Bare-statement version caught by this
    # test's own dry run — script silently exited right here instead of
    # continuing through the rest of the fixtures.)
    if timeout 15 "$BIN" "$path" "$out" 256 >"$OUTDIR/$label.err" 2>&1; then
        code=0
    else
        code=$?
    fi
    if [ "$code" -eq 0 ]; then
        echo "FAIL: $label expected non-zero exit, got success" >&2
        exit 1
    fi
    if [ "$code" -eq 124 ]; then
        echo "FAIL: $label hung past the outer 15s ceiling" >&2
        exit 1
    fi
    [ -f "$out" ] && { echo "FAIL: $label failed but left a PNG at $out" >&2; exit 1; }
    echo "ok (bad): $label -> exit $code, no PNG"
}

check_good "$STL/sphere-20k.stl" stl
check_good "$OBJ3MF/cube.3mf" 3mf
check_good "$OBJ3MF/cube.obj" obj

check_bad "$BAD/truncated.stl" truncated
check_bad "$BAD/garbage.stl" garbage
check_bad "$BAD/empty.stl" empty
check_bad "$BAD/notreally.3mf" notreally3mf
check_bad "$BAD/big.stl" big
check_bad "$BOMBS/lied-facecount.stl" liedfacecount
check_bad "$BOMBS/zipbomb.3mf" zipbomb

echo "PASS: test-thumbnailer-cli"
