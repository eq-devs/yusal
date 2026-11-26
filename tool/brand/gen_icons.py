#!/usr/bin/env python3
"""Regenerates the launcher icons (Android, iOS, macOS, web) from
tool/brand/svg/mark.svg and mark-small.svg, per the logo book:

  * white ground, mark height = 0.58 × icon side, centred, nudged down 1%
  * Android adaptive foreground/monochrome: mark height = 0.44 × canvas
  * sizes under 64 px use the small-size mark (wider gaps)

Needs cairosvg and Pillow.  Run from the repo root:
    python3 tool/brand/gen_icons.py
"""
import io
import json
import os
import re

import cairosvg
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..', '..'))
WHITE = '#FFFFFF'


def pieces(name):
    svg = open(os.path.join(HERE, 'svg', name)).read()
    return re.findall(r'<path d="([^"]*)" fill="([^"]*)"', svg)


MARK, SMALL = pieces('mark.svg'), pieces('mark-small.svg')


def icon_svg(size, bg=WHITE, frac=0.58, mono=None, small=False, inset=0,
             rx=0):
    parts = SMALL if small else MARK
    side = size - 2 * inset
    mh = side * frac
    s = mh / 240
    x = (size - 220 * s) / 2
    y = (size - mh) / 2 + side * 0.01
    g = ''.join(f'<path d="{d}" fill="{mono or f}"/>' for d, f in parts)
    ground = (f'<rect x="{inset}" y="{inset}" width="{side}" height="{side}" '
              f'rx="{rx}" fill="{bg}"/>') if bg else ''
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" '
            f'height="{size}" viewBox="0 0 {size} {size}">{ground}'
            f'<g transform="translate({x:.3f},{y:.3f}) scale({s:.6f})">{g}</g>'
            '</svg>')


def write(path, svg, px, rgb=False):
    png = cairosvg.svg2png(bytestring=svg.encode(), output_width=px,
                           output_height=px)
    im = Image.open(io.BytesIO(png))
    im = im.convert('RGB') if rgb else im.convert('RGBA')
    full = os.path.join(ROOT, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    im.save(full, optimize=True)


# Android
res = 'android/app/src/main/res'
for dpi, k in [('mdpi', 1), ('hdpi', 1.5), ('xhdpi', 2), ('xxhdpi', 3),
               ('xxxhdpi', 4)]:
    fg = round(108 * k)
    write(f'{res}/mipmap-{dpi}/ic_launcher_foreground.png',
          icon_svg(432, None, 0.44), fg)
    write(f'{res}/mipmap-{dpi}/ic_launcher_monochrome.png',
          icon_svg(432, None, 0.44, mono='#000000'), fg)
    legacy = round(48 * k)
    write(f'{res}/mipmap-{dpi}/ic_launcher.png',
          icon_svg(192, WHITE, 0.56, small=legacy < 64, rx=192 * 0.22),
          legacy)

# iOS: opaque squares, the system rounds the corners.
ios = 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
for img in json.load(open(os.path.join(ROOT, ios, 'Contents.json')))['images']:
    pt = float(img['size'].split('x')[0])
    px = round(pt * int(img['scale'][0]))
    write(f'{ios}/{img["filename"]}', icon_svg(1024, small=px < 64), px,
          rgb=True)

# macOS: the Big Sur grid, an 824 rounded square inside 1024.
mac = 'macos/Runner/Assets.xcassets/AppIcon.appiconset'
for px in [16, 32, 64, 128, 256, 512, 1024]:
    write(f'{mac}/app_icon_{px}.png',
          icon_svg(1024, inset=100, rx=185, small=px < 64), px)

# Web
write('web/favicon.png', icon_svg(240, None, 0.98, small=True), 32)
for px in [192, 512]:
    write(f'web/icons/Icon-{px}.png', icon_svg(1024), px, rgb=True)
    # Maskable: everything inside the 80% safe circle.
    write(f'web/icons/Icon-maskable-{px}.png', icon_svg(1024, frac=0.46), px,
          rgb=True)
print('icons written')
