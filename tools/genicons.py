#!/usr/bin/env python3
"""Generate PWA icons (rocket on the app's space gradient) with no external deps."""
import zlib, struct, math, os

OUT = os.path.join(os.path.dirname(__file__), "..", "icons")
os.makedirs(OUT, exist_ok=True)

def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))

def bg_color(x, y, S):
    # radial gradient matching the app: #3a1f6e -> #1a1147 -> #0d0826
    cx, cy = S * 0.5, S * 0.32
    d = math.hypot(x - cx, y - cy) / (S * 0.75)
    d = max(0.0, min(1.0, d))
    if d < 0.55:
        return lerp((58, 31, 110), (26, 17, 71), d / 0.55)
    return lerp((26, 17, 71), (13, 8, 38), (d - 0.55) / 0.45)

def tri(px, py, a, b, c):
    def sign(p, q, r):
        return (p[0]-r[0])*(q[1]-r[1]) - (q[0]-r[0])*(p[1]-r[1])
    d1 = sign((px, py), a, b)
    d2 = sign((px, py), b, c)
    d3 = sign((px, py), c, a)
    neg = (d1 < 0) or (d2 < 0) or (d3 < 0)
    pos = (d1 > 0) or (d2 > 0) or (d3 > 0)
    return not (neg and pos)

def rrect(px, py, x0, y0, x1, y1, r):
    qx = min(max(px, x0 + r), x1 - r)
    qy = min(max(py, y0 + r), y1 - r)
    return math.hypot(px - qx, py - qy) <= r

def rocket_color(px, py, S, scale):
    cx = S * 0.5
    cy = S * 0.5
    # scale shapes about centre (scale<1 -> smaller rocket, more padding)
    x = cx + (px - cx) / scale
    y = cy + (py - cy) / scale
    rw = S * 0.135
    bx0, bx1 = cx - rw, cx + rw
    by0, by1 = S * 0.25, S * 0.66
    # flame
    if tri(x, y, (cx - S*0.075, by1 - S*0.01), (cx + S*0.075, by1 - S*0.01), (cx, S*0.82)):
        if tri(x, y, (cx - S*0.04, by1), (cx + S*0.04, by1), (cx, S*0.74)):
            return (255, 210, 63)
        return (255, 126, 95)
    # fins
    finL = ((bx0, S*0.52), (bx0 - S*0.10, S*0.71), (bx0 + S*0.01, S*0.70))
    finR = ((bx1, S*0.52), (bx1 + S*0.10, S*0.71), (bx1 - S*0.01, S*0.70))
    if tri(x, y, *finL) or tri(x, y, *finR):
        return (255, 93, 162)
    # body
    if rrect(x, y, bx0, by0, bx1, by1, rw):
        # window
        wd = math.hypot(x - cx, y - S*0.40)
        if wd <= S*0.072:
            return (46, 230, 214)
        if wd <= S*0.086:
            return (26, 17, 71)
        return (255, 248, 240)
    return None

STARS = [(0.14,0.18,1.0),(0.82,0.15,1.3),(0.20,0.78,0.9),(0.86,0.70,1.1),
         (0.12,0.50,0.7),(0.90,0.42,0.8),(0.30,0.10,0.7),(0.70,0.86,0.9)]

def star_alpha(px, py, S):
    a = 0.0
    for sx, sy, sr in STARS:
        d = math.hypot(px - sx*S, py - sy*S)
        r = sr * S * 0.012
        if d < r:
            a = max(a, 1.0 - d / r)
    return a

def make(S, scale, fname, ss=3):
    buf = bytearray()
    sub = [(i + 0.5) / ss for i in range(ss)]
    for py in range(S):
        buf.append(0)  # filter byte
        for px in range(S):
            r = g = b = 0
            for dy in sub:
                for dx in sub:
                    sxp, syp = px + dx, py + dy
                    base = bg_color(sxp, syp, S)
                    sa = star_alpha(sxp, syp, S)
                    if sa > 0:
                        base = lerp(base, (255, 255, 255), sa)
                    rc = rocket_color(sxp, syp, S, scale)
                    col = rc if rc else base
                    r += col[0]; g += col[1]; b += col[2]
            n = ss * ss
            buf += bytes((r // n, g // n, b // n, 255))
    raw = bytes(buf)
    def chunk(typ, data):
        c = struct.pack(">I", len(data)) + typ + data
        return c + struct.pack(">I", zlib.crc32(typ + data) & 0xffffffff)
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", S, S, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    path = os.path.join(OUT, fname)
    with open(path, "wb") as f:
        f.write(png)
    print("wrote", path, S, "x", S)

make(512, 0.82, "icon-512.png")
make(512, 0.64, "icon-512-maskable.png")
make(192, 0.82, "icon-192.png")
make(180, 0.82, "apple-touch-icon.png")
make(32, 0.86, "favicon-32.png")
