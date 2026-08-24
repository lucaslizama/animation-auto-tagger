#!/usr/bin/env python3
"""Generates sample frames for testing the Animation Auto-Tagger.

The names are the point; the pictures only have to be distinguishable. Each
frame draws its animation letter and its frame index, so a glance at the built
timeline tells you whether the ordering and tagging came out right.

    python3 samples/make_samples.py [output-dir] [base-name]
"""

import sys
from pathlib import Path

from PIL import Image, ImageDraw

# 3x5 glyphs, scaled up when drawn. Avoids depending on a font being installed.
GLYPHS = {
    "0": ["111", "101", "101", "101", "111"],
    "1": ["010", "110", "010", "010", "111"],
    "2": ["111", "001", "111", "100", "111"],
    "3": ["111", "001", "111", "001", "111"],
    "4": ["101", "101", "111", "001", "001"],
    "5": ["111", "100", "111", "001", "111"],
    "6": ["111", "100", "111", "101", "111"],
    "7": ["111", "001", "001", "001", "001"],
    "8": ["111", "101", "111", "101", "111"],
    "9": ["111", "101", "111", "001", "111"],
    "I": ["111", "010", "010", "010", "111"],
    "R": ["110", "101", "110", "101", "101"],
    "A": ["010", "101", "111", "101", "101"],
    "J": ["001", "001", "001", "101", "010"],
    "H": ["101", "101", "111", "101", "101"],
}

# name, letter, frame count, (r, g, b), size
ANIMATIONS = [
    ("idle",   "I", 4, (131,  71, 173), (32, 32)),
    ("run",    "R", 6, ( 60, 180, 229), (32, 32)),
    # Deliberately wider: a sword swing needs the room, and it exercises the
    # "canvas = largest source frame" and alignment options.
    ("attack", "A", 5, (229, 129,  60), (40, 32)),
    ("jump",   "J", 3, ( 92, 184, 112), (32, 32)),
    ("hurt",   "H", 2, (214,  90, 122), (32, 32)),
]

INK = (24, 20, 30, 255)


def draw_glyph(draw, char, x, y, scale, color):
    for row, bits in enumerate(GLYPHS[char]):
        for col, bit in enumerate(bits):
            if bit == "1":
                draw.rectangle(
                    [x + col * scale, y + row * scale,
                     x + (col + 1) * scale - 1, y + (row + 1) * scale - 1],
                    fill=color,
                )


def draw_text(draw, text, x, y, scale, color):
    for i, char in enumerate(text):
        draw_glyph(draw, char, x + i * (4 * scale), y, scale, color)


def make_frame(letter, index, count, color, size):
    w, h = size
    img = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # Body: a rounded-ish block in the animation's colour, with a border so the
    # frame edges are obvious once everything sits on one canvas.
    d.rectangle([2, 2, w - 3, h - 3], fill=color + (255,), outline=INK)

    draw_text(d, letter, 4, 4, 2, INK)
    draw_text(d, f"{index:02d}", 4, h - 14, 2, INK)

    # A marker that walks down the right edge, so playback order reads at a
    # glance even if the digits are too small to see.
    step = (h - 8) // max(1, count)
    top = 4 + index * step
    d.rectangle([w - 8, top, w - 5, top + step - 2], fill=INK)

    return img


def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).parent / "hero"
    base = sys.argv[2] if len(sys.argv) > 2 else "hero"
    out.mkdir(parents=True, exist_ok=True)

    written = []
    for name, letter, count, color, size in ANIMATIONS:
        for i in range(count):
            frame = make_frame(letter, i, count, color, size)
            path = out / f"{base}_{name}_{i:02d}.png"
            frame.save(path)
            written.append(path)

    print(f"wrote {len(written)} frames to {out}")
    for p in written:
        print(" ", p.name)


if __name__ == "__main__":
    main()
