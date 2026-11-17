#!/usr/bin/env python3
"""Validate a thumbnailer PNG output beyond "exists and is non-empty"
(external review, Low: the original check only asserted non-empty,
which a blank/corrupt/non-PNG file would satisfy).

Checks: real PNG signature + IHDR-declared dimensions match the
requested size, and the image isn't just a uniform background color
(catches an offscreen-capture regression that produces a blank/solid
frame instead of an actual render).

Usage: check-thumbnail-png.py PATH EXPECTED_SIZE
Exit 0 if valid, prints a reason and exits 1 otherwise.
"""
import struct
import sys


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    path, expected_size = sys.argv[1], int(sys.argv[2])

    try:
        with open(path, 'rb') as f:
            data = f.read()
    except OSError as e:
        print(f"FAIL: cannot read {path}: {e}")
        return 1

    if data[:8] != b'\x89PNG\r\n\x1a\n':
        print(f"FAIL: {path} does not start with a PNG signature")
        return 1

    # IHDR is always the first chunk, immediately after the signature:
    # 4-byte length, 4-byte type 'IHDR', then width/height as two
    # big-endian uint32s.
    if data[12:16] != b'IHDR':
        print(f"FAIL: {path} has no IHDR chunk where expected")
        return 1
    width, height = struct.unpack('>II', data[16:24])
    if width != expected_size or height != expected_size:
        print(f"FAIL: {path} is {width}x{height}, expected {expected_size}x{expected_size}")
        return 1

    try:
        from PIL import Image
    except ImportError:
        print(f"ok (signature+dimensions only, PIL unavailable): {path} {width}x{height}")
        return 0

    img = Image.open(path).convert('RGB')
    pixels = img.getdata()
    distinct = set()
    for p in pixels:
        distinct.add(p)
        if len(distinct) > 1:
            break
    if len(distinct) <= 1:
        print(f"FAIL: {path} is a single uniform color {distinct} — looks like a blank capture, not a render")
        return 1

    print(f"ok: {path} {width}x{height}, {len(distinct)}+ distinct colors sampled")
    return 0


if __name__ == '__main__':
    sys.exit(main())
