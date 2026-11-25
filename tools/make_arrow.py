# Copyright (C) 2026 Vard Ruun. Licensed under GPL-3.0-or-later; see LICENSE and NOTICE.md.
"""Draw Media/Arrow.tga: a 128x128 arrowhead pointing up,
white with a dark outline so the addon can tint it with SetVertexColor.
Usage: python3 -I tools/make_arrow.py Media/Arrow.tga
"""
import math, struct, sys

W = H = 128
SS = 4  # supersampling for anti-aliasing

# Shapes in 0..1 coordinates, y down. Each: (polygon, brightness).
# A notched arrowhead (chevron) that fills the texture, so it reads well at small sizes.
HEAD = [(0.50, 0.08), (0.90, 0.88), (0.50, 0.68), (0.10, 0.88)]
RIDGE = [(0.50, 0.08), (0.90, 0.88), (0.50, 0.68)]  # right half drawn a little darker for depth
SHAPES = [(HEAD, 1.0), (RIDGE, 0.80)]
OUTLINE = 0.028
DARK = 0.10


def inside(px, py, poly):
    c = False
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, yi = poly[i]; xj, yj = poly[j]
        if (yi > py) != (yj > py) and px < (xj - xi) * (py - yi) / (yj - yi) + xi:
            c = not c
        j = i
    return c


def edge_dist(px, py, poly):
    best = 9
    for i in range(len(poly)):
        x1, y1 = poly[i]; x2, y2 = poly[(i + 1) % len(poly)]
        dx, dy = x2 - x1, y2 - y1
        t = max(0, min(1, ((px - x1) * dx + (py - y1) * dy) / (dx * dx + dy * dy)))
        best = min(best, math.hypot(px - x1 - t * dx, py - y1 - t * dy))
    return best


def sample(px, py):
    """Return (shade, alpha) for one sub-pixel; later shapes draw over earlier ones."""
    shade, alpha = None, 0.0
    for poly, bright in SHAPES:
        if inside(px, py, poly):
            shade, alpha = (DARK if edge_dist(px, py, poly) < OUTLINE else bright), 1.0
        elif edge_dist(px, py, poly) < OUTLINE and shade is None:
            shade, alpha = DARK, 1.0
    return (shade or 0.0), alpha


pixels = []
for y in range(H - 1, -1, -1):  # TGA rows bottom-up
    for x in range(W):
        tot, a = 0.0, 0.0
        for sy in range(SS):
            for sx in range(SS):
                s, al = sample((x + (sx + 0.5) / SS) / W, (y + (sy + 0.5) / SS) / H)
                tot += s * al; a += al
        n = SS * SS
        v = tot / a if a else 0.0
        a /= n
        c = int(v * 255)
        pixels.append(bytes([c, c, c, int(a * 255)]))

header = struct.pack('<BBBHHBHHHHBB', 0, 0, 2, 0, 0, 0, 0, 0, W, H, 32, 8)
with open(sys.argv[1], 'wb') as f:
    f.write(header)
    f.write(b''.join(pixels))
print('wrote', sys.argv[1])
