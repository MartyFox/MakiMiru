#!/usr/bin/env python3
"""Generate a triangulated cube OBJ fixture.

Usage: make-obj.py OUT.obj [--scale=S] [--offset=X,Y,Z]

Cube spans [-S, S] on each axis (default S=1), translated by offset.
Outward-facing triangle winding (right-hand rule).
"""
import sys

CUBE_VERTS = [
    (-1, -1, -1), (1, -1, -1), (1, 1, -1), (-1, 1, -1),  # 0-3 back
    (-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1),       # 4-7 front
]

# 1-indexed, outward-facing winding.
CUBE_FACES = [
    (1, 3, 2), (1, 4, 3),  # back  z=-1
    (5, 6, 7), (5, 7, 8),  # front z=+1
    (1, 5, 8), (1, 8, 4),  # left  x=-1
    (2, 3, 7), (2, 7, 6),  # right x=+1
    (1, 2, 6), (1, 6, 5),  # bottom y=-1
    (4, 8, 7), (4, 7, 3),  # top    y=+1
]


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    opts = [a for a in sys.argv[1:] if a.startswith('--')]
    if len(args) != 1:
        sys.exit(__doc__)
    out = args[0]

    scale = 1.0
    offset = (0.0, 0.0, 0.0)
    for o in opts:
        if o.startswith('--scale'):
            scale = float(o.split('=', 1)[1])
        elif o.startswith('--offset'):
            offset = tuple(float(x) for x in o.split('=', 1)[1].split(','))

    with open(out, 'w') as f:
        f.write('# kaiten cube fixture\n')
        f.write('o cube\n')
        for x, y, z in CUBE_VERTS:
            f.write('v %g %g %g\n' % (
                x * scale + offset[0],
                y * scale + offset[1],
                z * scale + offset[2]))
        for a, b, c in CUBE_FACES:
            f.write('f %d %d %d\n' % (a, b, c))
    print(f'{out}: cube (scale={scale}, offset={offset})')


if __name__ == '__main__':
    main()
