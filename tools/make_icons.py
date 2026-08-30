#!/usr/bin/env python3
"""Generate the Fokus app icons — pure stdlib PNG writer, no dependencies."""
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
    t = min(1.0, max(0.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)

BG0, BG1 = (18, 22, 34), (5, 6, 10)
ACC, ACC_HI = (76, 141, 255), (150, 186, 255)
ARC_END = 300.0          # degrees of the sweep, leaves a premium gap
def sample(x, y, S, ring_r, ring_w, transparent_bg=False):
    cx = cy = S / 2.0
    dx, dy = x - cx, y - cy
    d = math.hypot(dx, dy)

    if transparent_bg:
        col, a = (255, 255, 255), 0.0
    else:
        t = (x + y) / (2.0 * S)
        col = lerp(BG0, BG1, t)
        gx, gy = 0.30 * S, 0.24 * S
        g = max(0.0, 1.0 - math.hypot(x - gx, y - gy) / (0.85 * S)) ** 2.4
        col = tuple(min(255, col[i] + (ACC[i] - col[i]) * 0.30 * g) for i in range(3))
        a = 1.0

    ang = (math.degrees(math.atan2(dy, dx)) + 90.0) % 360.0
    ka0 = math.radians(-90.0)
    ka1 = math.radians(ARC_END - 90.0)
    if 0.0 <= ang <= ARC_END:
        darc = abs(d - ring_r)
    else:
        darc = min(math.hypot(x - (cx + ring_r*math.cos(ka0)), y - (cy + ring_r*math.sin(ka0))),
                   math.hypot(x - (cx + ring_r*math.cos(ka1)), y - (cy + ring_r*math.sin(ka1))))
    ring = 1.0 - smooth(ring_w*0.5 - 1.1, ring_w*0.5 + 1.1, darc)
    rc = lerp(ACC_HI, ACC, min(1.0, ang / ARC_END))

    halo = (1.0 - smooth(0.0, ring_w*2.8, darc)) ** 1.6 * 0.26
    col = tuple(min(255, col[i] + (rc[i] - col[i]) * halo) for i in range(3))
    a = max(a, halo * 0.9)

    kd = math.hypot(x - (cx + ring_r*math.cos(ka1)), y - (cy + ring_r*math.sin(ka1)))
    knob = 1.0 - smooth(ring_w*0.70, ring_w*0.70 + 1.5, kd)

    m = max(ring, knob)
    if m > 0:
        target = (245, 249, 255) if knob > ring else rc
        col = lerp(col, target, m)
        a = max(a, m)
    return col, a

def render(path, S, ring_ratio, width_ratio, ss=3, transparent=False):
    ring_r, ring_w = S * ring_ratio, S * width_ratio
    buf = bytearray(S * S * 4)
    inv = 1.0 / (ss * ss)
    for y in range(S):
        for x in range(S):
            r = g = b = a = 0.0
            for sy in range(ss):
                for sx in range(ss):
                    c, al = sample(x + (sx + .5) / ss, y + (sy + .5) / ss, S, ring_r, ring_w, transparent)
                    r += c[0] * al; g += c[1] * al; b += c[2] * al; a += al
            i = (y * S + x) * 4
            if a > 0:
                buf[i]   = int(min(255, r / a))
                buf[i+1] = int(min(255, g / a))
                buf[i+2] = int(min(255, b / a))
            buf[i+3] = int(min(255, a * inv * 255))
    png(path, S, S, buf)
    print('->', os.path.relpath(path))

os.makedirs(OUT, exist_ok=True)
render(os.path.join(OUT, 'icon-192.png'),        192, .315, .075)
render(os.path.join(OUT, 'icon-512.png'),        512, .315, .075)
render(os.path.join(OUT, 'apple-touch-icon.png'),180, .315, .075)
render(os.path.join(OUT, 'maskable-512.png'),    512, .245, .058)
render(os.path.join(OUT, 'badge.png'),            96, .34, .10, ss=3, transparent=True)

open(os.path.join(OUT, 'favicon.svg'), 'w').write('''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
<stop offset="0" stop-color="#96BAFF"/><stop offset="1" stop-color="#4C8DFF"/></linearGradient></defs>
<rect width="64" height="64" rx="14" fill="#0A0C12"/>
<circle cx="32" cy="32" r="19" fill="none" stroke="url(#g)" stroke-width="4.6"
        stroke-linecap="round" stroke-dasharray="100 119" transform="rotate(-90 32 32)"/>
<circle cx="41.6" cy="48.5" r="3.4" fill="#F5F9FF"/></svg>''')
print('-> icons/favicon.svg')
