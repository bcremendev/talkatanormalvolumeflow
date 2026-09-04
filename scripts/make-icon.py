#!/usr/bin/env python3
# Turns Resources/AppIcon-source.png (rounded-square artwork on a black background) into Resources/AppIcon.icns
# on Apple's icon grid (artwork = 824/1024 of the canvas, transparent margin). Run: python3 scripts/make-icon.py
import os, shutil, subprocess
from PIL import Image, ImageDraw, ImageFilter

src = Image.open("Resources/AppIcon-source.png").convert("RGBA")
w, h = src.size

# Find the artwork's bounding box: everything that isn't (near) black.
px = src.load()
lum = src.convert("L").point(lambda v: 255 if v > 18 else 0)
bbox = lum.getbbox()
art = src.crop(bbox)
aw, ah = art.size
side = max(aw, ah)
art = art.resize((side, side), Image.LANCZOS)

# Apple's rounded-square mask: corner radius ≈ 22.37% of the side.
mask = Image.new("L", (side * 4, side * 4), 0)
ImageDraw.Draw(mask).rounded_rectangle((0, 0, side * 4 - 1, side * 4 - 1), radius=int(side * 4 * 0.2237), fill=255)
mask = mask.resize((side, side), Image.LANCZOS)
art.putalpha(mask)

def canvas(px_size):
    inner = round(px_size * 824 / 1024)
    im = Image.new("RGBA", (px_size, px_size), (0, 0, 0, 0))
    a = art.resize((inner, inner), Image.LANCZOS)
    off = (px_size - inner) // 2
    # Soft drop shadow like Apple's icons.
    sh = Image.new("RGBA", (px_size, px_size), (0, 0, 0, 0))
    sh.paste((0, 0, 0, 70), (off, off + max(1, px_size // 64)), a.split()[3])
    sh = sh.filter(ImageFilter.GaussianBlur(max(0.5, px_size / 100)))
    im.alpha_composite(sh)
    im.alpha_composite(a, (off, off))
    return im

out = "Resources/AppIcon.iconset"
shutil.rmtree(out, ignore_errors=True); os.makedirs(out)
for name, p in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)]:
    canvas(p).save(f"{out}/icon_{name}.png")
subprocess.run(["iconutil", "-c", "icns", out, "-o", "Resources/AppIcon.icns"], check=True)
canvas(1024).save("Resources/AppIcon-1024.png")
shutil.rmtree(out)
print("Resources/AppIcon.icns written")
