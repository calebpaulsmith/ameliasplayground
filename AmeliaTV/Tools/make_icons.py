#!/usr/bin/env python3
"""Generate placeholder app icons for the iOS (AmeliaPad) and tvOS (AmeliaTV)
targets.

These are friendly *placeholders* (a cozy yellow bus under a sunny sky) so the
TestFlight pipeline validates and uploads — real art is decision D-ART-1 and is
swapped in behind the same asset-catalog names later. Re-run after changing the
art:

    python3 AmeliaTV/Tools/make_icons.py

It writes two asset catalogs (binary PNGs + Contents.json), regenerated wholly
from this script so the commit stays reviewable:

  AmeliaTV/Resources/iOS/Assets.xcassets   — AppIcon.appiconset (1024²)
  AmeliaTV/Resources/tvOS/Assets.xcassets  — App Icon & Top Shelf Image brandassets

Requires Pillow (pip install Pillow).
"""
import json
import os
import shutil

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IOS_XCASSETS = os.path.join(ROOT, "Resources", "iOS", "Assets.xcassets")
TVOS_XCASSETS = os.path.join(ROOT, "Resources", "tvOS", "Assets.xcassets")

SKY_TOP = (126, 200, 255)      # #7EC8FF
SKY_BOTTOM = (201, 238, 255)   # #C9EEFF
SUN = (255, 224, 120)          # #FFE680
BUS_BODY = (255, 194, 60)      # #FFC23C
BUS_DARK = (224, 150, 30)
WINDOW = (200, 235, 255)
WHEEL = (60, 60, 70)
HUBCAP = (200, 200, 210)


def _gradient(w, h):
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    for y in range(h):
        t = y / max(1, h - 1)
        r = int(SKY_TOP[0] + (SKY_BOTTOM[0] - SKY_TOP[0]) * t)
        g = int(SKY_TOP[1] + (SKY_BOTTOM[1] - SKY_TOP[1]) * t)
        b = int(SKY_TOP[2] + (SKY_BOTTOM[2] - SKY_TOP[2]) * t)
        for x in range(w):
            px[x, y] = (r, g, b, 255)
    return img


def _draw_sun(draw, w, h):
    r = int(min(w, h) * 0.16)
    cx, cy = int(w * 0.16), int(h * 0.2)
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=SUN)


def _draw_bus(draw, w, h):
    """Draw a centered cartoon bus scaled to the canvas."""
    bw = int(w * 0.62)
    bh = int(h * 0.40)
    # keep a friendly aspect ratio regardless of canvas shape
    bh = min(bh, int(bw * 0.5))
    bw = min(bw, int(bh * 2.4))
    x0 = (w - bw) // 2
    y0 = int(h * 0.50)
    x1, y1 = x0 + bw, y0 + bh
    rad = int(bh * 0.28)

    # body
    draw.rounded_rectangle([x0, y0, x1, y1], radius=rad, fill=BUS_BODY)
    # roof stripe
    stripe_h = max(2, int(bh * 0.12))
    draw.rounded_rectangle(
        [x0, y0, x1, y0 + stripe_h * 2], radius=rad, fill=BUS_DARK
    )
    # windows
    win_top = y0 + int(bh * 0.22)
    win_bot = y0 + int(bh * 0.55)
    margin = int(bw * 0.06)
    n = 4
    gap = int(bw * 0.03)
    total = bw - 2 * margin - (n - 1) * gap
    ww = total // n
    for i in range(n):
        wx0 = x0 + margin + i * (ww + gap)
        draw.rounded_rectangle(
            [wx0, win_top, wx0 + ww, win_bot],
            radius=max(2, int(ww * 0.15)),
            fill=WINDOW,
        )
    # headlight
    hl = max(3, int(bh * 0.10))
    draw.ellipse(
        [x1 - hl * 2, y0 + int(bh * 0.62), x1 - hl // 2, y0 + int(bh * 0.62) + hl],
        fill=(255, 245, 200),
    )
    # wheels
    wr = int(bh * 0.20)
    wy = y1 - int(wr * 0.4)
    for wx in (x0 + int(bw * 0.24), x0 + int(bw * 0.76)):
        draw.ellipse([wx - wr, wy - wr, wx + wr, wy + wr], fill=WHEEL)
        draw.ellipse(
            [wx - wr // 2, wy - wr // 2, wx + wr // 2, wy + wr // 2], fill=HUBCAP
        )


def scene(w, h, transparent_bg=False):
    """Full icon scene. transparent_bg=True draws only the bus (for the tvOS
    parallax front layer)."""
    if transparent_bg:
        img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    else:
        img = _gradient(w, h)
    draw = ImageDraw.Draw(img)
    if not transparent_bg:
        _draw_sun(draw, w, h)
    _draw_bus(draw, w, h)
    return img


def background(w, h):
    """Sky + sun only (tvOS parallax back layer)."""
    img = _gradient(w, h)
    draw = ImageDraw.Draw(img)
    _draw_sun(draw, w, h)
    return img


def write_json(path, obj):
    with open(path, "w") as f:
        json.dump(obj, f, indent=2)
        f.write("\n")


def fresh(path):
    if os.path.exists(path):
        shutil.rmtree(path)
    os.makedirs(path)


# ---------------------------------------------------------------- iOS ----------
def build_ios():
    fresh(IOS_XCASSETS)
    write_json(
        os.path.join(IOS_XCASSETS, "Contents.json"),
        {"info": {"author": "xcode", "version": 1}},
    )
    iconset = os.path.join(IOS_XCASSETS, "AppIcon.appiconset")
    os.makedirs(iconset)
    scene(1024, 1024).convert("RGB").save(os.path.join(iconset, "icon-1024.png"))
    write_json(
        os.path.join(iconset, "Contents.json"),
        {
            "images": [
                {
                    "filename": "icon-1024.png",
                    "idiom": "universal",
                    "platform": "ios",
                    "size": "1024x1024",
                }
            ],
            "info": {"author": "xcode", "version": 1},
        },
    )


# --------------------------------------------------------------- tvOS ----------
def _imageset(parent, name, images_1x_2x):
    """images_1x_2x: list of (scale, PIL image)."""
    iset = os.path.join(parent, name + ".imageset")
    os.makedirs(iset)
    images = []
    for scale, im in images_1x_2x:
        fn = f"{name.replace(' ', '_').lower()}@{scale}.png"
        im.save(os.path.join(iset, fn))
        images.append({"filename": fn, "idiom": "tv", "scale": scale})
    write_json(
        os.path.join(iset, "Contents.json"),
        {"images": images, "info": {"author": "xcode", "version": 1}},
    )


def _imagestack(parent, name, w, h, scales):
    """A single fully-opaque layer stack. tvOS requires the bottom-most layer of
    an app-icon image stack to be a fully opaque bitmap, so a transparent
    parallax foreground would fail asset validation. Placeholder icons don't need
    real parallax, so we use one opaque layer (the whole scene)."""
    stack = os.path.join(parent, name + ".imagestack")
    os.makedirs(stack)
    layers = [("Content", lambda w, h: scene(w, h))]   # one opaque layer
    layer_entries = []
    for layer_name, render in layers:
        ldir = os.path.join(stack, layer_name + ".imagestacklayer")
        os.makedirs(ldir)
        write_json(
            os.path.join(ldir, "Contents.json"),
            {"info": {"author": "xcode", "version": 1}},
        )
        content = os.path.join(ldir, "Content.imageset")
        os.makedirs(content)
        images = []
        for scale in scales:
            mult = int(scale[0])
            im = render(w * mult, h * mult)
            fn = f"{layer_name.lower()}@{scale}.png"
            im.save(os.path.join(content, fn))
            images.append({"filename": fn, "idiom": "tv", "scale": scale})
        write_json(
            os.path.join(content, "Contents.json"),
            {"images": images, "info": {"author": "xcode", "version": 1}},
        )
        layer_entries.append({"filename": layer_name + ".imagestacklayer"})
    write_json(
        os.path.join(stack, "Contents.json"),
        {"info": {"author": "xcode", "version": 1}, "layers": layer_entries},
    )


def build_tvos():
    fresh(TVOS_XCASSETS)
    write_json(
        os.path.join(TVOS_XCASSETS, "Contents.json"),
        {"info": {"author": "xcode", "version": 1}},
    )
    brand = os.path.join(TVOS_XCASSETS, "App Icon & Top Shelf Image.brandassets")
    os.makedirs(brand)

    # Home-screen icon (small, parallax, @1x+@2x) and App Store icon (large).
    _imagestack(brand, "App Icon", 400, 240, ["1x", "2x"])
    _imagestack(brand, "App Icon - App Store", 1280, 768, ["1x"])
    # Top shelf images (flat).
    _imageset(
        brand,
        "Top Shelf Image",
        [("1x", scene(1920, 720)), ("2x", scene(3840, 1440))],
    )
    _imageset(
        brand,
        "Top Shelf Image Wide",
        [("1x", scene(2320, 720)), ("2x", scene(4640, 1440))],
    )

    write_json(
        os.path.join(brand, "Contents.json"),
        {
            "assets": [
                {
                    "filename": "App Icon - App Store.imagestack",
                    "idiom": "tv",
                    "role": "primary-app-icon",
                    "size": "1280x768",
                },
                {
                    "filename": "App Icon.imagestack",
                    "idiom": "tv",
                    "role": "primary-app-icon",
                    "size": "400x240",
                },
                {
                    "filename": "Top Shelf Image Wide.imageset",
                    "idiom": "tv",
                    "role": "top-shelf-image-wide",
                    "size": "2320x720",
                },
                {
                    "filename": "Top Shelf Image.imageset",
                    "idiom": "tv",
                    "role": "top-shelf-image",
                    "size": "1920x720",
                },
            ],
            "info": {"author": "xcode", "version": 1},
        },
    )


if __name__ == "__main__":
    build_ios()
    build_tvos()
    print("✅ generated iOS + tvOS app-icon asset catalogs")
