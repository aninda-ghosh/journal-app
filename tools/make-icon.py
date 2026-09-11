#!/usr/bin/env python3
"""
Draw the Journal app icon and package it as build/icon.icns + build/icon.png.

The icon is a warm rounded square — the ground — holding a single photo card
with a small landscape on it: a page with a picture, which is what the app is.
Kept deliberately simple so it still reads at 16 pixels in the Dock.
"""

import math
import os
import struct
from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), '..', 'build')
S = 1024  # master size; everything below is expressed as a fraction of it

PAPER      = (250, 246, 240)
PAPER_EDGE = (233, 224, 212)
CLAY_TOP   = (206, 122,  84)
CLAY_BOT   = (158,  84,  57)
SKY_TOP    = (247, 214, 186)
SKY_BOT    = (240, 186, 152)
HILL_FAR   = (176, 116,  92)
HILL_NEAR  = (122,  70,  55)
SUN        = (255, 240, 214)


def squircle(size, radius_ratio=0.2237):
    """An Apple-ish rounded square mask (Big Sur icons use ~22.37% corners)."""
    mask = Image.new('L', (size * 4, size * 4), 0)
    d = ImageDraw.Draw(mask)
    r = int(size * 4 * radius_ratio)
    d.rounded_rectangle([0, 0, size * 4 - 1, size * 4 - 1], radius=r, fill=255)
    return mask.resize((size, size), Image.LANCZOS)


def vertical_gradient(size, top, bottom):
    grad = Image.new('RGB', (1, size))
    for y in range(size):
        t = y / max(1, size - 1)
        grad.putpixel((0, y), tuple(
            round(top[i] + (bottom[i] - top[i]) * t) for i in range(3)
        ))
    return grad.resize((size, size), Image.BICUBIC)


def rounded_mask(w, h, r):
    m = Image.new('L', (w * 4, h * 4), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, w * 4 - 1, h * 4 - 1], radius=r * 4, fill=255)
    return m.resize((w, h), Image.LANCZOS)


def draw_photo_card():
    """The photo card: a small landscape, matted like a print."""
    cw, ch = int(S * 0.60), int(S * 0.60)
    card = Image.new('RGB', (cw, ch), PAPER)

    # the image area inside the mat
    mat = int(cw * 0.085)
    iw, ih = cw - mat * 2, int(ch * 0.66)
    img = vertical_gradient(max(iw, ih), SKY_TOP, SKY_BOT).crop((0, 0, iw, ih))
    d = ImageDraw.Draw(img)

    # sun
    sr = int(iw * 0.105)
    scx, scy = int(iw * 0.71), int(ih * 0.33)
    d.ellipse([scx - sr, scy - sr, scx + sr, scy + sr], fill=SUN)

    # far hill
    far = [(0, ih)]
    for x in range(iw + 1):
        t = x / iw
        y = ih * (0.70 - 0.20 * math.sin(math.pi * (t * 0.85 + 0.08)))
        far.append((x, y))
    far.append((iw, ih))
    d.polygon(far, fill=HILL_FAR)

    # near hill
    near = [(0, ih)]
    for x in range(iw + 1):
        t = x / iw
        y = ih * (0.90 - 0.26 * math.sin(math.pi * (t * 0.7 + 0.45)))
        near.append((x, y))
    near.append((iw, ih))
    d.polygon(near, fill=HILL_NEAR)

    img.putalpha(rounded_mask(iw, ih, int(iw * 0.035)))
    card.paste(img, (mat, mat), img)

    # a hairline so the card reads as an object, not a hole
    ImageDraw.Draw(card).rounded_rectangle(
        [0, 0, cw - 1, ch - 1], radius=int(cw * 0.06), outline=PAPER_EDGE, width=max(2, cw // 220)
    )

    card = card.convert('RGBA')
    card.putalpha(rounded_mask(cw, ch, int(cw * 0.06)))
    return card


def build_master():
    base = Image.new('RGBA', (S, S), (0, 0, 0, 0))

    ground = vertical_gradient(S, CLAY_TOP, CLAY_BOT).convert('RGBA')
    ground.putalpha(squircle(S))
    base.alpha_composite(ground)

    card = draw_photo_card()
    cw, ch = card.size
    cx, cy = (S - cw) // 2, int(S * 0.20)

    # a soft drop shadow so the card sits above the ground
    shadow = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    sh = Image.new('RGBA', (cw, ch), (60, 28, 16, 105))
    sh.putalpha(Image.eval(rounded_mask(cw, ch, int(cw * 0.06)), lambda v: int(v * 0.41)))
    shadow.alpha_composite(sh, (cx, cy + int(S * 0.028)))
    shadow = shadow.filter(ImageFilter.GaussianBlur(S * 0.028))
    shadow.putalpha(Image.composite(shadow.getchannel('A'),
                                    Image.new('L', (S, S), 0), squircle(S)))
    base.alpha_composite(shadow)
    base.alpha_composite(card, (cx, cy))

    # two ruled lines below the card — the "journal" half of photo journal
    d = ImageDraw.Draw(base)
    lw = max(3, int(S * 0.019))
    for i, (frac, width) in enumerate([(0.845, 0.44), (0.905, 0.28)]):
        y = int(S * frac)
        half = int(S * width / 2)
        d.rounded_rectangle(
            [S // 2 - half, y - lw // 2, S // 2 + half, y + lw // 2],
            radius=lw, fill=(255, 244, 232, 214 if i == 0 else 150)
        )

    return base


# ---------------------------------------------------------------- packaging

# Modern .icns entries are just PNGs under a four-character type.
ICNS_TYPES = [
    (b'icp4', 16), (b'icp5', 32), (b'icp6', 64),
    (b'ic07', 128), (b'ic08', 256), (b'ic09', 512), (b'ic10', 1024),
    (b'ic11', 32), (b'ic12', 64), (b'ic13', 256), (b'ic14', 512),
]


def write_icns(master, path):
    chunks = []
    for type_code, size in ICNS_TYPES:
        import io
        buf = io.BytesIO()
        master.resize((size, size), Image.LANCZOS).save(buf, format='PNG', optimize=True)
        data = buf.getvalue()
        chunks.append(type_code + struct.pack('>I', len(data) + 8) + data)

    body = b''.join(chunks)
    with open(path, 'wb') as f:
        f.write(b'icns' + struct.pack('>I', len(body) + 8) + body)
    return len(body) + 8


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    master = build_master()

    png_path = os.path.join(OUT, 'icon.png')
    master.save(png_path, format='PNG', optimize=True)

    icns_path = os.path.join(OUT, 'icon.icns')
    total = write_icns(master, icns_path)

    print(f'icon.png   {os.path.getsize(png_path):>9,} bytes  (1024x1024)')
    print(f'icon.icns  {total:>9,} bytes  ({len(ICNS_TYPES)} representations)')
