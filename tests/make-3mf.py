#!/usr/bin/env python3
"""Generate a minimal valid 3MF fixture (cube mesh, optionally two objects).

Usage: make-3mf.py OUT.3mf [--two-object] [--scale=S] [--offset=X,Y,Z]

Produces a zip package with [Content_Types].xml, _rels/.rels, and
3D/3dmodel.model containing one (or two) cube meshes per the core 3MF spec.
"""
import sys
import zipfile

CUBE_VERTS = [
    (-1, -1, -1), (1, -1, -1), (1, 1, -1), (-1, 1, -1),  # 0-3 back
    (-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1),       # 4-7 front
]

# 0-indexed, outward-facing winding.
CUBE_TRIS = [
    (0, 2, 1), (0, 3, 2),
    (4, 5, 6), (4, 6, 7),
    (0, 4, 7), (0, 7, 3),
    (1, 2, 6), (1, 6, 5),
    (0, 1, 5), (0, 5, 4),
    (3, 7, 6), (3, 6, 2),
]

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


def cube_mesh_xml(scale, offset):
    verts = '\n'.join(
        '<vertex x="%g" y="%g" z="%g"/>' % (
            x * scale + offset[0], y * scale + offset[1], z * scale + offset[2])
        for x, y, z in CUBE_VERTS)
    tris = '\n'.join(
        '<triangle v1="%d" v2="%d" v3="%d"/>' % t for t in CUBE_TRIS)
    return f'<mesh><vertices>\n{verts}\n</vertices><triangles>\n{tris}\n</triangles></mesh>'


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    opts = [a for a in sys.argv[1:] if a.startswith('--')]
    if len(args) != 1:
        sys.exit(__doc__)
    out = args[0]

    scale = 1.0
    offset = (0.0, 0.0, 0.0)
    two_object = '--two-object' in opts
    for o in opts:
        if o.startswith('--scale'):
            scale = float(o.split('=', 1)[1])
        elif o.startswith('--offset'):
            offset = tuple(float(x) for x in o.split('=', 1)[1].split(','))

    objects = [f'<object id="1" type="model">{cube_mesh_xml(scale, offset)}</object>']
    items = ['<item objectid="1"/>']
    if two_object:
        off2 = (offset[0] + scale * 3, offset[1], offset[2])
        objects.append(f'<object id="2" type="model">{cube_mesh_xml(scale, off2)}</object>')
        items.append('<item objectid="2"/>')

    model_xml = (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<model unit="millimeter" xmlns="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel">\n'
        '<resources>\n' + '\n'.join(objects) + '\n</resources>\n'
        '<build>\n' + '\n'.join(items) + '\n</build>\n'
        '</model>\n'
    )

    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as zf:
        zf.writestr('[Content_Types].xml', CONTENT_TYPES)
        zf.writestr('_rels/.rels', RELS)
        zf.writestr('3D/3dmodel.model', model_xml)

    print(f'{out}: 3MF ({"two-object" if two_object else "single-object"}, scale={scale}, offset={offset})')


if __name__ == '__main__':
    main()
