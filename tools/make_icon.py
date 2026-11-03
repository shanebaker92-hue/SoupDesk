"""Trace the Portra 400 canister sprite (Pixel.swift FilmSprite) into Icon Composer layers.

    python3 tools/make_icon.py Design/SoupDesk.icon/Assets

Each layer is one flat colour, pixel-edged outline paths (no per-pixel rects, so glass
edges have no seams), no baked shading: Liquid Glass supplies the light.
"""
import sys, os

OUT = sys.argv[1]
P = 22                       # one sprite pixel in icon points
OX = OY = 512 - 15 * P       # content box x 2..28, y 0..30 centred on 1024

def rect(x0, y0, x1, y1):
    return {(x, y) for x in range(x0, x1 + 1) for y in range(y0, y1 + 1)}

GLYPH = {"4": [0x18, 0x14, 0x12, 0x7f, 0x10], "0": [0x3e, 0x51, 0x49, 0x45, 0x3e]}
def text(s, cx, y):
    cells, x = set(), cx - (len(s) * 6 - 1) // 2
    for ch in s:
        for col, bits in enumerate(GLYPH[ch]):
            cells |= {(x + col, y + r) for r in range(7) if bits >> r & 1}
        x += 6
    return cells

leader = rect(22, 9, 27, 24) - {(26, y) for y in range(10, 24, 3)}
spool = rect(9, 0, 15, 2)
caps = rect(3, 3, 21, 5) | rect(3, 27, 21, 29)
body = rect(2, 6, 22, 26)
band = rect(2, 8, 22, 12) | rect(2, 24, 22, 24)
label = text("400", 12, 16)

def outline(cells):
    """Boundary loops, clockwise outside / anticlockwise holes (y down), collinear points merged."""
    edges = {}
    for x, y in cells:
        for (a, b, n) in [((x, y), (x + 1, y), (x, y - 1)), ((x + 1, y), (x + 1, y + 1), (x + 1, y)),
                          ((x + 1, y + 1), (x, y + 1), (x, y + 1)), ((x, y + 1), (x, y), (x - 1, y))]:
            if n not in cells:
                edges.setdefault(a, []).append(b)
    loops = []
    while edges:
        start = next(iter(edges)); pts = [start]; cur = start; prev_dir = None
        while True:
            outs = edges[cur]
            if len(outs) > 1 and prev_dir:   # pinch point: take the right-hand turn
                outs.sort(key=lambda b: ((b[0] - cur[0], b[1] - cur[1]) != (-prev_dir[1], prev_dir[0])))
            nxt = outs.pop(0)
            if not outs: del edges[cur]
            prev_dir = (nxt[0] - cur[0], nxt[1] - cur[1]); cur = nxt
            if cur == start: break
            pts.append(cur)
        keep = [p for i, p in enumerate(pts)
                if (pts[i - 1][0] == p[0]) != (p[0] == pts[(i + 1) % len(pts)][0])]
        loops.append(keep)
    return loops

def path_d(cells):
    return " ".join("M" + " L".join(f"{OX + x * P} {OY + y * P}" for x, y in loop) + " Z" for loop in outline(cells))

def svg(name, fill, cells=None, full=False):
    shape = (f'<rect width="1024" height="1024" fill="{fill}"/>' if full
             else f'<path fill="{fill}" d="{path_d(cells)}"/>')
    with open(os.path.join(OUT, name), "w") as f:
        f.write(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">\n{shape}\n</svg>\n')

os.makedirs(OUT, exist_ok=True)
# Shapes only: icon.json sets each layer's fill per appearance and the background.
svg("00-leader.svg", "#9A5E2C", leader)
svg("01-caps.svg", "#9A9088", spool | caps)
svg("02-body.svg", "#F2E6D0", body)
svg("03-band.svg", "#F5B021", band)
svg("04-label.svg", "#2A1E14", label)
print("wrote", sorted(os.listdir(OUT)))
