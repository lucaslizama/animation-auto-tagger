# Blurs the character in store/demo.gif, so the GIF shows the extension at
# work without showing off art that isn't the point of it. The sprite is on
# the canvas in two of the three shots; while the prompt is up it is behind
# the dialog, and the timeline never shows it.
#
# ffmpeg does the work, the way scripts/make-gif.sh made the GIF: the frames
# keep their own timings, and they go back onto the GIF's own palette with no
# dithering, so every pixel outside the boxes comes out as it went in and the
# file stays about the size it was. It blurs whatever it is given, so run it
# on a GIF fresh from make-gif.sh, not on one already blurred:
#
#   python3 store/blur_sprite.py store/demo.gif store/demo.gif
#
# A new recording frames the sprite differently, and the boxes below need
# measuring again: frames are first and last inclusive, boxes are left, top,
# right, bottom in the GIF's pixels.
import os, shutil, subprocess, sys, tempfile
from PIL import Image

BOXES = [
    ((18, 28), (378, 186, 404, 222)),           # just dropped, middle of the canvas
    ((99, 103), (780, 71, 833, 123)),           # built, before the view settles
    ((104, 154), (774, 52, 823, 103)),          # built, the timeline below it
]
PAD = 4                                         # past the cel's edge, so no outline survives
SIGMA = 5
MARGIN = SIGMA * 2                              # blurred around the box too, so its edge blends in

src, dst = sys.argv[1], sys.argv[2]

with tempfile.TemporaryDirectory() as tmp:
    # The GIF's palette as the 16x16 image paletteuse takes.
    flat = Image.open(src).getpalette()
    flat += flat[-3:] * (256 - len(flat) // 3)
    palette = Image.new('RGB', (16, 16))
    palette.putdata([tuple(flat[i:i + 3]) for i in range(0, 768, 3)])
    palette_png = os.path.join(tmp, 'palette.png')
    palette.save(palette_png)

    graph = [f'[0:v]format=gbrp,split={len(BOXES) + 1}[v0]' + ''.join(f'[s{k}]' for k in range(len(BOXES)))]
    for k, ((first, last), (l, t, r, b)) in enumerate(BOXES):
        l, t, r, b = l - PAD, t - PAD, r + PAD, b + PAD
        graph.append(
            f'[s{k}]crop={r - l + 2 * MARGIN}:{b - t + 2 * MARGIN}:{l - MARGIN}:{t - MARGIN},'
            f'gblur=sigma={SIGMA},crop={r - l}:{b - t}:{MARGIN}:{MARGIN}[b{k}];'
            f"[v{k}][b{k}]overlay={l}:{t}:format=gbrp:enable='between(n,{first},{last})'[v{k + 1}]")
    graph.append(f'[v{len(BOXES)}][1:v]paletteuse=dither=none:diff_mode=rectangle')

    out = os.path.join(tmp, 'out.gif')
    subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-i', src, '-i', palette_png,
                    '-filter_complex', ';'.join(graph), '-fps_mode', 'passthrough',
                    '-loop', '0', '-y', out], check=True)
    shutil.move(out, dst)            # tmp may be on another filesystem

print(f'{dst}: {os.path.getsize(dst) / 1048576:.2f} MB')
