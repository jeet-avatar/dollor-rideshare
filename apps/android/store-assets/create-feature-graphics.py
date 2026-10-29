#!/usr/bin/env python3
"""Build the Play feature graphics (1024x500) for the Dollor rider and driver apps.

Colours come from the shared design tokens (shared/.../ui/Lx.kt). Text is limited to
statements the apps support (see customer/listing.md and driver/listing.md).
Run from this folder:  python3 create-feature-graphics.py
"""
import os
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
BG = (0x0B, 0x0B, 0x0D)
SURFACE = (0x17, 0x17, 0x1A)
HAIRLINE = (0x2A, 0x2A, 0x2E)
ORANGE = (0xFF, 0x7A, 0x1A)
WHITE = (255, 255, 255)
SECONDARY = (0xA1, 0xA1, 0xAA)
BOLD = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
REGULAR = "/System/Library/Fonts/Supplemental/Arial.ttf"

APPS = {
    "customer": {
        "icon": "customer/app-icon-512x512.png",
        "title": ["Bid on", "your ride"],
        "sub": ["Request a ride, compare", "driver bids, pick your fare."],
        "shot": "customer/screenshots/03-matched.png",
        "crop": (0, 1100, 1080, 2324),
    },
    "driver": {
        "icon": "driver/app-icon-512x512.png",
        "title": ["Bid on", "ride requests"],
        "sub": ["Set your own price and see", "what you earn before you bid."],
        "shot": "driver/screenshots/02-submit-bid.png",
        "crop": (0, 900, 1080, 2124),
    },
}


def font(path, size):
    return ImageFont.truetype(path, size)


def build(name, cfg):
    img = Image.new("RGB", (1024, 500), BG)
    draw = ImageDraw.Draw(img)
    for x in range(1024):  # soft orange glow on the right edge
        t = max(0.0, (x - 560) / 464)
        draw.line([(x, 0), (x, 500)], fill=tuple(int(BG[i] + (c - BG[i]) * 0.10 * t) for i, c in enumerate(ORANGE)))
    icon = Image.open(os.path.join(HERE, cfg["icon"])).convert("RGB").resize((72, 72))
    mask = Image.new("L", (72, 72), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, 71, 71), 16, fill=255)
    img.paste(icon, (56, 56), mask)
    draw.text((142, 70), "Dollor", font=font(BOLD, 40), fill=WHITE)
    y = 160
    for line in cfg["title"]:
        draw.text((56, y), line, font=font(BOLD, 60), fill=WHITE if line is cfg["title"][0] else ORANGE)
        y += 76
    y += 14
    for line in cfg["sub"]:
        draw.text((56, y), line, font=font(REGULAR, 26), fill=SECONDARY)
        y += 36
    shot = Image.open(os.path.join(HERE, cfg["shot"])).convert("RGB").crop(cfg["crop"])
    w = 330
    shot = shot.resize((w, int(shot.height * w / shot.width)))
    frame = Image.new("RGB", (w + 16, 390), SURFACE)
    frame.paste(shot, (8, 8))
    fmask = Image.new("L", frame.size, 0)
    ImageDraw.Draw(fmask).rounded_rectangle((0, 0, frame.width - 1, frame.height + 60), 38, fill=255)
    img.paste(frame, (640, 110), fmask.crop((0, 0, frame.width, frame.height)))
    ImageDraw.Draw(img).rounded_rectangle((640, 110, 640 + frame.width, 110 + 600), 38, outline=HAIRLINE, width=3)
    # re-clip anything the outline drew below the canvas
    out = os.path.join(HERE, name, "feature-graphic-1024x500.png")
    img.save(out, "PNG")
    print(out, img.size, img.mode)


for n, c in APPS.items():
    build(n, c)
