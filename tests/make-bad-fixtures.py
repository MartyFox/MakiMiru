#!/usr/bin/env python3
"""Generate corrupt/edge-case 3D-model fixtures for SPEC-006 error-path tests.

Usage: make-bad-fixtures.py OUTDIR

Writes: truncated.stl, garbage.stl, empty.stl, notreally.3mf, big.stl
"""
import os
import struct
import sys
import zipfile

# Valid package structure (matches make-3mf.py) but 3D/3dmodel.model holds
# plain text instead of XML — DOMParser produces a <parsererror> document,
# 3MFLoader's querySelector('model') returns null, and reading
# modelNode.attributes throws — a reliable, deterministic parse failure
# (unlike an incomplete/missing zip entry, whose failure point depends on
# unaudited internal loader logic).
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


def write_truncated_stl(path):
    # Valid 80-byte header + triangle count claiming 1000, but only 2
    # triangles' worth of bytes actually follow (each triangle = 50 bytes)
    # -> STLLoader's DataView reads run off the end of the buffer.
    with open(path, 'wb') as f:
        f.write(b'\x00' * 80)
        f.write(struct.pack('<I', 1000))
        f.write(b'\x00' * 100)


def write_garbage_stl(path):
    with open(path, 'wb') as f:
        f.write(os.urandom(2048))


def write_empty_stl(path):
    open(path, 'wb').close()


def write_notreally_3mf(path):
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as zf:
        zf.writestr('[Content_Types].xml', CONTENT_TYPES)
        zf.writestr('_rels/.rels', RELS)
        zf.writestr('3D/3dmodel.model', 'not a 3d model')


def write_big_stl(path, size_mb=101):
    with open(path, 'wb') as f:
        f.write(b'\x00' * 80)
        f.write(struct.pack('<I', 0))
        f.truncate(size_mb * 1024 * 1024)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    outdir = sys.argv[1]
    os.makedirs(outdir, exist_ok=True)

    write_truncated_stl(os.path.join(outdir, 'truncated.stl'))
    write_garbage_stl(os.path.join(outdir, 'garbage.stl'))
    write_empty_stl(os.path.join(outdir, 'empty.stl'))
    write_notreally_3mf(os.path.join(outdir, 'notreally.3mf'))
    write_big_stl(os.path.join(outdir, 'big.stl'))

    for name in ('truncated.stl', 'garbage.stl', 'empty.stl', 'notreally.3mf', 'big.stl'):
        p = os.path.join(outdir, name)
        print(f'{p}: {os.path.getsize(p)} bytes')


if __name__ == '__main__':
    main()
