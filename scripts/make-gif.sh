#!/usr/bin/env sh
# Turns a screen recording into a GIF small enough to put on a store page.
#
#   scripts/make-gif.sh recording.webm
#   scripts/make-gif.sh recording.webm store/demo.gif --width 720 --fps 12
#   scripts/make-gif.sh recording.webm --start 2 --duration 18 --speed 1.5
#
# Two passes rather than one: ffmpeg builds a palette from the whole clip first,
# then maps the frames to it. A single pass picks a palette from the first frame
# and everything after it turns to mud.
set -e
cd "$(dirname "$0")/.."

IN=""
OUT=""
WIDTH=720
FPS=12
SPEED=1
START=""
DURATION=""

while [ $# -gt 0 ]; do
  case "$1" in
    --width)    shift; WIDTH="$1" ;;
    --fps)      shift; FPS="$1" ;;
    --speed)    shift; SPEED="$1" ;;
    --start)    shift; START="$1" ;;
    --duration) shift; DURATION="$1" ;;
    -*) echo "unknown option: $1" >&2; exit 1 ;;
    *)  if [ -z "$IN" ]; then IN="$1"; elif [ -z "$OUT" ]; then OUT="$1";
        else echo "too many file arguments" >&2; exit 1; fi ;;
  esac
  shift
done

[ -n "$IN" ] || { echo "usage: scripts/make-gif.sh <recording> [out.gif] [options]" >&2; exit 1; }
[ -f "$IN" ] || { echo "no such file: $IN" >&2; exit 1; }
command -v ffmpeg >/dev/null 2>&1 || { echo "ffmpeg is needed" >&2; exit 1; }

[ -n "$OUT" ] || OUT="store/demo.gif"
PALETTE="$(mktemp -t aat-palette-XXXXXX.png)"
trap 'rm -f "$PALETTE"' EXIT

TRIM=""
[ -n "$START" ] && TRIM="$TRIM -ss $START"
[ -n "$DURATION" ] && TRIM="$TRIM -t $DURATION"

# setpts before fps, so speeding up drops frames rather than duplicating them.
# flags=neighbor keeps pixel art crisp; anything smoother turns it to porridge.
CHAIN="setpts=PTS/$SPEED,fps=$FPS,scale=$WIDTH:-1:flags=neighbor"

echo "make-gif: reading $IN"
# shellcheck disable=SC2086
ffmpeg -hide_banner -loglevel error $TRIM -i "$IN" \
  -vf "$CHAIN,palettegen=stats_mode=diff:max_colors=128" -y "$PALETTE"

# bayer dithering costs a little quality and saves a lot of bytes on the flat
# colour that screen recordings of a pixel-art editor are mostly made of.
# shellcheck disable=SC2086
ffmpeg -hide_banner -loglevel error $TRIM -i "$IN" -i "$PALETTE" \
  -lavfi "$CHAIN [x]; [x][1:v] paletteuse=dither=bayer:bayer_scale=3:diff_mode=rectangle" \
  -loop 0 -y "$OUT"

BYTES="$(wc -c < "$OUT")"
MB="$(awk -v b="$BYTES" 'BEGIN { printf "%.1f", b / 1048576 }')"
DIMS="$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 "$OUT" 2>/dev/null || echo "?")"

echo "make-gif: wrote $OUT  ${MB}MB  ${DIMS}  ${FPS}fps"

if [ "$BYTES" -gt 5242880 ]; then
  echo "make-gif: over 5MB, which is a slow load on a store page." >&2
  echo "make-gif: try --width 600, or --fps 10, or a shorter --duration." >&2
fi
