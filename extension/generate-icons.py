#!/usr/bin/env python3
"""Generate simple blue circle icon PNGs for the extension."""
import struct, zlib, os, math

OUT = os.path.join(os.path.dirname(__file__), 'icons')

def make_chunk(typ, data):
    c = typ + data
    return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)

def create_png(w, h, pixels):
    raw = b''
    for y in range(h):
        raw += b'\x00'
        for x in range(w):
            i = (y * w + x) * 4
            raw += bytes(pixels[i:i+4])
    ihdr = make_chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0))
    idat = make_chunk(b'IDAT', zlib.compress(raw))
    iend = make_chunk(b'IEND', b'')
    return b'\x89PNG\r\n\x1a\n' + ihdr + idat + iend

def icon_pixels(sz):
    cx = cy = sz // 2
    r = sz * 0.42
    out = []
    for y in range(sz):
        for x in range(sz):
            d = math.hypot(x - cx, y - cy)
            if d <= r:
                # Blue circle with slight gradient
                b = int(200 + 55 * (1 - d / r))
                out += [56, 189, int(b), 255]
            else:
                out += [0, 0, 0, 0]
    return out

os.makedirs(OUT, exist_ok=True)
for sz in (16, 48, 128):
    data = create_png(sz, sz, icon_pixels(sz))
    with open(os.path.join(OUT, f'icon{sz}.png'), 'wb') as f:
        f.write(data)
    print(f'Created icon{sz}.png ({sz}x{sz})')
