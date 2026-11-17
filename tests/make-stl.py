#!/usr/bin/env python3
"""Generate STL fixtures (binary by default, --ascii for text variant).

Usage: make-stl.py TRIANGLES OUT.stl [--ascii] [--scale S] [--offset X,Y,Z]

Produces a UV sphere with approximately TRIANGLES triangles.
Binary size = 84 + 50 * triangles bytes.
"""
import math
import struct
import sys


def sphere_triangles(n_target, scale=1.0, offset=(0.0, 0.0, 0.0)):
    n = max(int(math.sqrt(n_target / 2)), 2)
    rows, cols = n, n

    def vert(r, c):
        theta = math.pi * r / rows
        phi = 2 * math.pi * c / cols
        x = math.sin(theta) * math.cos(phi) * scale + offset[0]
        y = math.sin(theta) * math.sin(phi) * scale + offset[1]
        z = math.cos(theta) * scale + offset[2]
        return (x, y, z)

    tris = []
    for r in range(rows):
        for c in range(cols):
            a, b = vert(r, c), vert(r + 1, c)
            d, e = vert(r, c + 1), vert(r + 1, c + 1)
            tris.append((a, b, d))
            tris.append((d, b, e))
    return tris


def normal(tri):
    (ax, ay, az), (bx, by, bz), (cx, cy, cz) = tri
    ux, uy, uz = bx - ax, by - ay, bz - az
    vx, vy, vz = cx - ax, cy - ay, cz - az
    nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
    length = math.sqrt(nx * nx + ny * ny + nz * nz) or 1.0
    return (nx / length, ny / length, nz / length)


def write_binary(tris, path):
    with open(path, 'wb') as f:
        f.write(b'kaiten fixture'.ljust(80, b'\0'))
        f.write(struct.pack('<I', len(tris)))
        for tri in tris:
            f.write(struct.pack('<3f', *normal(tri)))
            for v in tri:
                f.write(struct.pack('<3f', *v))
            f.write(struct.pack('<H', 0))


def write_ascii(tris, path):
    with open(path, 'w') as f:
        f.write('solid kaiten\n')
        for tri in tris:
            f.write('facet normal %g %g %g\n' % normal(tri))
            f.write(' outer loop\n')
            for v in tri:
                f.write('  vertex %g %g %g\n' % v)
            f.write(' endloop\nendfacet\n')
        f.write('endsolid kaiten\n')


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    opts = [a for a in sys.argv[1:] if a.startswith('--')]
    if len(args) != 2:
        sys.exit(__doc__)
    n, out = int(args[0]), args[1]

    scale = 1.0
    offset = (0.0, 0.0, 0.0)
    for o in opts:
        if o.startswith('--scale'):
            scale = float(o.split('=', 1)[1])
        elif o.startswith('--offset'):
            offset = tuple(float(x) for x in o.split('=', 1)[1].split(','))

    tris = sphere_triangles(n, scale, offset)
    if '--ascii' in opts:
        write_ascii(tris, out)
    else:
        write_binary(tris, out)
    print(f'{out}: {len(tris)} triangles')


if __name__ == '__main__':
    main()
