#!/usr/bin/env python3
"""Generate allocation/decompression-bomb fixtures for SPEC-008 tests.

Both fixtures are small on disk (well under SPEC-006's 100 MB threshold,
so that check alone would let them through) but claim/produce far more
than they should once parsed — the preflight caps in web/main.js are
what's actually under test here.

Usage: make-bomb-fixtures.py OUTDIR

Writes: lied-facecount.stl, zipbomb.3mf
"""
import os
import struct
import sys
import zipfile

CONTENT_TYPES = '''<?xml version="1.0" encoding="UTF-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="model" ContentType="application/vnd.ms-package.3dmanufacturing-3dmodel+xml"/>
</Types>
'''

RELS = '''<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Target="/3D/3dmodel.model" Id="rel0" Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/>
</Relationships>
'''


def write_lied_facecount_stl(path, claimed_faces=50_000_000):
    # Valid 84-byte binary STL header claiming 50M faces (needs ~2.4 GB
    # to actually back that up) — file is 84 bytes total, no face data
    # follows at all. Distinct from the smaller truncated.stl fixture
    # (SPEC-006): that one's mismatch is small enough to just run off
    # the end of a short buffer; this one is sized to demonstrate the
    # "huge allocation from a tiny file" shape specifically.
    with open(path, 'wb') as f:
        f.write(b'\x00' * 80)
        f.write(struct.pack('<I', claimed_faces))


def write_zipbomb_3mf(path, target_uncompressed_mb=2048, chunk_mb=8):
    # Highly-compressible payload (repeated spaces) — DEFLATE collapses
    # this to a tiny on-disk size while the declared/actual decompressed
    # size stays large. Written in chunks so generating the fixture
    # itself doesn't need target_uncompressed_mb of RAM at once.
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        zf.writestr('[Content_Types].xml', CONTENT_TYPES)
        zf.writestr('_rels/.rels', RELS)
        chunk = b' ' * (chunk_mb * 1024 * 1024)
        target = target_uncompressed_mb * 1024 * 1024
        with zf.open('3D/3dmodel.model', 'w', force_zip64=True) as entry:
            written = 0
            while written < target:
                entry.write(chunk)
                written += len(chunk)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    outdir = sys.argv[1]
    os.makedirs(outdir, exist_ok=True)

    write_lied_facecount_stl(os.path.join(outdir, 'lied-facecount.stl'))
    write_zipbomb_3mf(os.path.join(outdir, 'zipbomb.3mf'))

    for name in ('lied-facecount.stl', 'zipbomb.3mf'):
        p = os.path.join(outdir, name)
        print(f'{p}: {os.path.getsize(p)} bytes')


if __name__ == '__main__':
    main()
