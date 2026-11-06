# The itch page's background image, set to repeat: an Aseprite timeline seen
# from far away, rows of frame cells with a tag bar over some of the runs, in
# the cover's dark and the extension's own tag colours sunk into it. Drawn on
# a small grid and scaled up with hard edges, as pixel art is; the tile wraps
# both ways, so it repeats without seams. The same method as Sublime Itch's
# page backgrounds (design/itch-page/make_backgrounds.py there).
#
# It sits behind the page's column, so it is kept quiet on purpose: nothing
# in it is much lighter than the background, and the colours are a third of
# their strength. Run from the repo root:
#
#   python3 store/make_background.py
import random
from PIL import Image, ImageDraw

OUT = 'store/background.png'
S = 3                                   # screen pixels per pixel
W, H = 160, 120                         # the tile, before scaling: 480x360
ROW = 12                                # one timeline row: a tag bar and cells
CELL, GAP = 6, 2                        # a frame cell and the space after it
BG = (23, 19, 30)                       # the cover's #17131E
CELL_EDGE = (36, 30, 46)                # an empty cel's outline
CELL_FULL = (44, 37, 56)                # a cel with something in it

# config.lua's TAG_COLORS, the ones the extension paints tags with.
TAGS = [(131, 71, 173), (60, 180, 229), (229, 129, 60),
        (92, 184, 112), (214, 90, 122), (214, 196, 84)]

def sink(colour, amount=0.32):
    return tuple(round(b + (c - b) * amount) for c, b in zip(colour, BG))

def tile():
    t = Image.new('RGB', (W, H), BG)
    d = ImageDraw.Draw(t)
    rnd = random.Random(11)
    step = CELL + GAP
    cells = W // step                   # W is a whole number of cells, so rows wrap
    assert cells * step == W
    for y in range(0, H, ROW):
        # Split the row into runs of cells, each an animation; most get a tag
        # bar, a few are left untagged, as loose frames would be.
        col = rnd.randrange(cells)      # where the row's first run starts
        left = cells
        while left > 0:
            n = min(left, rnd.randint(3, 9))
            tagged = rnd.random() < 0.75
            colour = sink(rnd.choice(TAGS))
            for i in range(n):
                x = ((col + i) % cells) * step
                if tagged and i < n - 1:
                    d.rectangle((x, y + 1, x + step - 1, y + 2), fill=colour)
                elif tagged:
                    d.rectangle((x, y + 1, x + CELL - 1, y + 2), fill=colour)
                fill = CELL_FULL if rnd.random() < 0.6 else None
                d.rectangle((x, y + 4, x + CELL - 1, y + 4 + CELL - 1),
                            outline=CELL_EDGE, fill=fill)
            col += n
            left -= n
    return t

small = tile()
small.resize((W * S, H * S), Image.NEAREST).save(OUT, optimize=True)
print(f'{OUT}: {W * S}x{H * S}')
