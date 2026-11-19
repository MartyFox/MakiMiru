#!/bin/sh
# makimiru-pregen (thumbnailer --pregen): batch pre-generation into GNOME's
# thumbnail cache. Checks, against an isolated XDG_CACHE_HOME:
#  - good STL/3MF/OBJ (incl. in a subfolder) land at the exact path Files
#    looks up (<size>/md5(uri).png), with matching Thumb::URI, and render
#  - hidden folders are skipped; broken and oversized files are recorded
#    in fail/gnome-thumbnail-factory/ so Files won't retry them
#  - a second run renders nothing; --size x-large writes 512 px PNGs
#  - a timeout is not recorded as failed, so the next run retries it
#  - a symlinked folder given as the argument is walked
#  - bad arguments exit 2; no X server socket/lock leaks into /tmp
#  - batching is actually faster than one thumbnailer process per file
# Needs the .deb installed (deb mode), or MAKIMIRU_TEST_PREGEN /
# MAKIMIRU_TEST_THUMBNAILER pointing at a staged build.
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"
PREGEN="${MAKIMIRU_TEST_PREGEN:-/usr/bin/makimiru-pregen}"
THUMB="${MAKIMIRU_TEST_THUMBNAILER:-/usr/libexec/makimiru-thumbnailer}"
[ -x "$PREGEN" ] || { echo "SKIP: $PREGEN not installed (deb mode only)"; exit 0; }

W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
M="$W/models"
mkdir -p "$M/sub" "$M/.hidden" "$W/cache" "$W/bad"
python3 "$DIR/make-stl.py" 2000 "$M/sphere.stl" >/dev/null
python3 "$DIR/make-3mf.py" "$M/sub/cube.3mf" >/dev/null
python3 "$DIR/make-obj.py" "$M/sub/cube.obj" >/dev/null
python3 "$DIR/make-stl.py" 500 "$M/.hidden/skipped.stl" >/dev/null
python3 "$DIR/make-bad-fixtures.py" "$W/bad" >/dev/null
cp "$W/bad/truncated.stl" "$M/broken.stl"
cp --sparse=always "$W/bad/big.stl" "$M/huge.stl"
export XDG_CACHE_HOME="$W/cache"
export DISPLAY="${DISPLAY:-:0}"

x11_before="$(ls /tmp/.X11-unix 2>/dev/null | sort; ls /tmp/.X*-lock 2>/dev/null)"

cache_path() { # file size -> expected thumbnail path
    python3 -c 'import hashlib,sys,pathlib; print(hashlib.md5(pathlib.Path(sys.argv[1]).absolute().as_uri().encode()).hexdigest())' "$1" |
        sed "s#^#$W/cache/thumbnails/$2/#; s#\$#.png#"
}
thumb_uri() { # png -> Thumb::URI tEXt chunk (stdlib only, no PIL)
    python3 - "$1" <<'EOF'
import struct, sys
data = open(sys.argv[1], 'rb').read()
pos = 8
while pos < len(data):
    length, kind = struct.unpack('>I4s', data[pos:pos + 8])
    body = data[pos + 8:pos + 8 + length]
    if kind == b'tEXt' and body.startswith(b'Thumb::URI\0'):
        print(body.split(b'\0', 1)[1].decode('latin-1'))
        break
    pos += 12 + length
EOF
}

out="$("$PREGEN" "$M")"
echo "$out"
echo "$out" | grep -q 'makimiru-pregen: 3 new, 0 already done, 2 failed' ||
    { echo "FAIL: unexpected first-run summary" >&2; exit 1; }

for f in sphere.stl sub/cube.3mf sub/cube.obj; do
    png="$(cache_path "$M/$f" large)"
    [ -f "$png" ] || { echo "FAIL: no large thumbnail for $f at $png" >&2; exit 1; }
    python3 "$DIR/check-thumbnail-png.py" "$png" 256
    [ "$(thumb_uri "$png")" = "file://$M/$f" ] || { echo "FAIL: wrong Thumb::URI for $f" >&2; exit 1; }
done
for f in broken.stl huge.stl; do
    [ -f "$(cache_path "$M/$f" fail/gnome-thumbnail-factory)" ] ||
        { echo "FAIL: $f not recorded as failed" >&2; exit 1; }
done
[ ! -f "$(cache_path "$M/.hidden/skipped.stl" large)" ] || { echo "FAIL: hidden folder was processed" >&2; exit 1; }
echo "ok: thumbnails and failures in GNOME's cache layout; hidden folder skipped"

"$PREGEN" "$M" | grep -q '0 new, 5 already done, 0 failed' || { echo "FAIL: second run re-rendered" >&2; exit 1; }
echo "ok: second run renders nothing"

"$PREGEN" --size x-large "$M/sphere.stl" >/dev/null
python3 "$DIR/check-thumbnail-png.py" "$(cache_path "$M/sphere.stl" x-large)" 512
echo "ok: --size x-large writes 512 px thumbnails"

mkdir "$M/slow"
cp "$M/sphere.stl" "$M/slow/a.stl"
MAKIMIRU_THUMBNAIL_TIMEOUT_MS=1 "$PREGEN" "$M/slow" | grep -q '0 new, 0 already done, 1 failed' ||
    { echo "FAIL: forced timeout not reported as failed" >&2; exit 1; }
[ ! -f "$(cache_path "$M/slow/a.stl" fail/gnome-thumbnail-factory)" ] ||
    { echo "FAIL: timeout recorded as a permanent failure" >&2; exit 1; }
"$PREGEN" "$M/slow" | grep -q '1 new, 0 already done, 0 failed' ||
    { echo "FAIL: timed-out file not retried on the next run" >&2; exit 1; }
echo "ok: timeouts are retried, not recorded as failed"

ln -s "$M/sub" "$W/linked"
"$PREGEN" "$W/linked" | grep -q '2 new, 0 already done, 0 failed' ||
    { echo "FAIL: symlinked folder argument not walked" >&2; exit 1; }
echo "ok: symlinked folder argument is walked"

rc=0; "$PREGEN" --bogus "$M" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || { echo "FAIL: bad option exited $rc, want 2" >&2; exit 1; }
rc=0; "$PREGEN" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || { echo "FAIL: no folder exited $rc, want 2" >&2; exit 1; }
echo "ok: bad arguments exit 2"

# Batch vs one process per file, same 6 files at the same size.
mkdir "$M/speed"
for i in 1 2 3 4 5 6; do cp "$M/sphere.stl" "$M/speed/s$i.stl"; done
t0="$(date +%s%N)"
for i in 1 2 3 4 5 6; do "$THUMB" "$M/speed/s$i.stl" "$W/single$i.png" 256 2>/dev/null; done
t1="$(date +%s%N)"
"$PREGEN" "$M/speed" >/dev/null
t2="$(date +%s%N)"
single_ms=$(( (t1 - t0) / 1000000 )); batch_ms=$(( (t2 - t1) / 1000000 ))
echo "timing: 6 files one-by-one ${single_ms} ms, batched ${batch_ms} ms"
[ $(( batch_ms * 2 )) -lt "$single_ms" ] || { echo "FAIL: batch is not at least 2x faster" >&2; exit 1; }

x11_after="$(ls /tmp/.X11-unix 2>/dev/null | sort; ls /tmp/.X*-lock 2>/dev/null)"
[ "$x11_before" = "$x11_after" ] || { echo "FAIL: X server socket/lock leaked into /tmp" >&2; exit 1; }
echo "PASS: test-pregen"
