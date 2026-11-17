#!/bin/sh
# SPEC-003 test 2: each fixture type previews (Visible true) and closes,
# guarding against crashes/hangs. Visual correctness is the manual checklist.
set -eu
. "$(dirname "$0")/lib.sh"

TMP="${TMPDIR:-/tmp}/kaiten-smoke"
mkdir -p "$TMP"

# Fixtures: generate deterministic local files, no network.
PNG="$TMP/fixture.png"
PDF="$TMP/fixture.pdf"
TXT="$TMP/fixture.txt"
[ -f "$PNG" ] || python3 - "$PNG" <<'EOF'
import struct, sys, zlib
def chunk(t, d):
    return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d))
raw = b''.join(b'\x00' + b'\x40\x80\xc0' * 16 for _ in range(16))
png = (b'\x89PNG\r\n\x1a\n'
       + chunk(b'IHDR', struct.pack('>IIBBBBB', 16, 16, 8, 2, 0, 0, 0))
       + chunk(b'IDAT', zlib.compress(raw))
       + chunk(b'IEND', b''))
open(sys.argv[1], 'wb').write(png)
EOF
[ -f "$PDF" ] || printf '%%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 200 200]>>endobj\nxref\n0 4\ntrailer<</Size 4/Root 1 0 R>>\n%%%%EOF\n' > "$PDF"
[ -f "$TXT" ] || printf 'kaiten smoke fixture\n' > "$TXT"

# MP3 needs an encoder; skip (with notice) where ffmpeg is unavailable.
MP3="$TMP/fixture.mp3"
if [ ! -f "$MP3" ] && command -v ffmpeg >/dev/null 2>&1; then
    ffmpeg -f lavfi -i 'sine=frequency=440:duration=2' -q:a 5 \
        "$MP3" -y -loglevel error
fi

for f in "$PNG" "$PDF" "$TXT"; do
    assert_visible_change true "show_v2 file://$f"
    assert_visible_change false "close_preview"
    echo "ok: $f"
done

if [ -f "$MP3" ]; then
    assert_visible_change true "show_v2 file://$MP3"
    assert_visible_change false "close_preview"
    echo "ok: $MP3"
else
    echo "skip: mp3 (no ffmpeg)"
fi
echo "PASS: test-preview-smoke"
