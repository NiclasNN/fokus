#!/usr/bin/env python3
"""Fokus app-ikoner — ren stdlib, inga beroenden.

Märket: en bock i en öppen ring. Bocken säger uppgift, ringen är samma
ratt som appens timer och sluter sig inte — ett pass som pågår.
Allt ritas som signerade avstånd och antialiasas med supersampling.
"""
import math, struct, zlib, os

OUT = os.path.join(os.path.dirname(__file__), '..', 'icons')

def png(path, w, h, rgba):
    raw = b''.join(b'\x00' + bytes(rgba[y*w*4:(y+1)*w*4]) for y in range(h))
    def chunk(t, d):
        c = t + d
        return struct.pack('>I', len(d)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)
    data = (b'\x89PNG\r\n\x1a\n'
            + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(raw, 9))
            + chunk(b'IEND', b''))
    open(path, 'wb').write(data)

def lerp(a, b, t): return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))
def smooth(e0, e1, x):
    if e1 == e0: return 0.0 if x < e0 else 1.0
    t = min(1.0, max(0.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)
def seg_dist(px, py, ax, ay, bx, by):
    """Avstånd till ett linjesegment — bockens streck har runda ändar."""
    vx, vy = bx - ax, by - ay
    wx, wy = px - ax, py - ay
    L = vx*vx + vy*vy
    t = 0.0 if L == 0 else min(1.0, max(0.0, (wx*vx + wy*vy) / L))
    return math.hypot(wx - vx*t, wy - vy*t)

# Himmelsblått uppe till vänster, djupt blått nere till höger.
TOP, BOT = (96, 158, 255), (26, 88, 221)
WHITE = (255, 255, 255)

# Normaliserade mått (andel av sidan). Ändra här, inte i sample().
RING_R, RING_W = 0.360, 0.030
GAP0, GAP1 = 292.0, 360.0          # ringens öppning, grader från kl 12
CHK = ((0.262, 0.502), (0.432, 0.668), (0.748, 0.322))
CHK_W = 0.097
RADIUS = 0.215                      # hörnradie när brickan bakas in

def sample(x, y, S, scale, rounded, flat):
    """Returnerar (färg, alfa) för en punkt i pixelkoordinater."""
    u, v = x / S, y / S
    cx = cy = 0.5

    if flat:                                    # badge: bara bocken, vit på intet
        col, a = WHITE, 0.0
    else:
        col = lerp(TOP, BOT, (u + v) * 0.5)
        # mjukt ljus uppe till vänster — brickan ska se välvd ut, inte tryckt
        g = max(0.0, 1.0 - math.hypot(u - 0.26, v - 0.20) / 0.92) ** 2.6
        col = tuple(min(255, col[i] + (255 - col[i]) * 0.22 * g) for i in range(3))
        a = 1.0
        if rounded:                             # rundad kvadrat, inte full utfyllnad
            r = RADIUS
            qx, qy = abs(u - .5) - (.5 - r), abs(v - .5) - (.5 - r)
            d = math.hypot(max(qx, 0.0), max(qy, 0.0)) + min(max(qx, qy), 0.0) - r
            a = 1.0 - smooth(-1.1/S, 1.1/S, d)
            if a <= 0: return col, 0.0

    aa = 1.3 / S                                # kantmjukhet i normaliserade enheter

    # ringen: tyst, och öppen uppåt höger så den aldrig sluter sig
    if not flat:
        dx, dy = u - cx, v - cy
        ang = (math.degrees(math.atan2(dy, dx)) + 90.0) % 360.0
        rr = RING_R * scale
        if GAP0 <= ang <= GAP1:
            k0, k1 = math.radians(GAP0 - 90.0), math.radians(GAP1 - 90.0)
            dring = min(math.hypot(dx - rr*math.cos(k0), dy - rr*math.sin(k0)),
                        math.hypot(dx - rr*math.cos(k1), dy - rr*math.sin(k1)))
        else:
            dring = abs(math.hypot(dx, dy) - rr)
        ring = 1.0 - smooth(RING_W*scale*0.5 - aa, RING_W*scale*0.5 + aa, dring)
        if ring > 0:
            col = lerp(col, WHITE, ring * 0.30)

    # bocken
    p = [(cx + (ax - .5) * scale, cy + (ay - .5) * scale) for ax, ay in CHK]
    dchk = min(seg_dist(u, v, *p[0], *p[1]), seg_dist(u, v, *p[1], *p[2]))
    chk = 1.0 - smooth(CHK_W*scale*0.5 - aa, CHK_W*scale*0.5 + aa, dchk)
    if chk > 0:
        col = lerp(col, WHITE, chk)
        a = max(a, chk)
    return col, a

def render(path, S, scale=1.0, rounded=True, flat=False, ss=3):
    buf = bytearray(S * S * 4)
    inv = 1.0 / (ss * ss)
    for y in range(S):
        for x in range(S):
            r = g = b = a = 0.0
            for sy in range(ss):
                for sx in range(ss):
                    c, al = sample(x + (sx + .5)/ss, y + (sy + .5)/ss, S, scale, rounded, flat)
                    r += c[0]*al; g += c[1]*al; b += c[2]*al; a += al
            i = (y * S + x) * 4
            if a > 0:
                buf[i]   = int(min(255, r / a))
                buf[i+1] = int(min(255, g / a))
                buf[i+2] = int(min(255, b / a))
            buf[i+3] = int(min(255, a * inv * 255))
    png(path, S, S, buf)
    print('->', os.path.relpath(path))

os.makedirs(OUT, exist_ok=True)
# iOS maskar apple-touch-icon själv — bakar vi in hörnen får vi dubbla rundningar
render(os.path.join(OUT, 'apple-touch-icon.png'), 180, rounded=False)
render(os.path.join(OUT, 'icon-192.png'),         192)
render(os.path.join(OUT, 'icon-512.png'),         512)
# maskable: Android klipper själv, märket måste hålla sig inom 60 % säker zon
render(os.path.join(OUT, 'maskable-512.png'),     512, scale=0.72, rounded=False)
render(os.path.join(OUT, 'badge.png'),             96, scale=1.18, flat=True)

open(os.path.join(OUT, 'favicon.svg'), 'w').write('''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
<stop offset="0" stop-color="#609EFF"/><stop offset="1" stop-color="#1A58DD"/></linearGradient></defs>
<rect width="64" height="64" rx="13.8" fill="url(#g)"/>
<circle cx="32" cy="32" r="23" fill="none" stroke="#fff" stroke-opacity=".3" stroke-width="1.9"
        stroke-linecap="round" stroke-dasharray="117 28" transform="rotate(-90 32 32)"/>
<path d="M16.8 32.1 27.6 42.8 47.9 20.6" fill="none" stroke="#fff" stroke-width="6.2"
      stroke-linecap="round" stroke-linejoin="round"/></svg>''')
print('-> icons/favicon.svg')
