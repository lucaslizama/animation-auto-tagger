# itch.io page, ready to paste

Working copy for the store page. Not part of the extension; delete it if it gets
in the way.

## Project settings

**Title:** Animation Auto-Tagger

**Short description** (the tagline under the title, 140 characters or so):

    Turn a folder of numbered frames into one Aseprite sprite with a tagged
    timeline. Re-import in place when the art changes.

**Classification:** Tool
**Kind of project:** Downloadable
**Release status:** Released
**Pricing:** Pay what you want, suggested price $3

**Upload:** `animation-auto-tagger.aseprite-extension`, marked as running on
Windows, macOS and Linux. It is one file for all three.

**Tags:** aseprite, pixel-art, animation, sprite, tool, gamedev, godot, 2d,
workflow, extension

**Community:** comments on. Bug reports are the point of shipping this.

## Page body

The body is `store/game-page.md`, written for Sublime Itch: its coloured words,
folded sections, box and frame are Sublime Itch's Markdown, which turns into
the inline styles itch keeps. To use it, put it in the Sublime Itch library as
the project's game page, `Animation Auto-Tagger/_game-page.md`, and copy
`store/demo.gif` into the library's `_media` folder as
`animation-auto-tagger-demo.gif`. Copy HTML (or Save to itch) then uploads the
GIF and gives the HTML for the page's description.

It is about a third of the length of the first draft. The six features each
lead with one of the extension's tag colours, lightened to read on the dark
page, in the order it paints them. The full option list and the limitations
are folded away, since they matter to someone deciding whether it handles their
naming scheme rather than to everyone.

## Theme

Edit theme on the game's page, with these values:

| Setting | Value |
|---|---|
| Background | `#17131E`, the cover's own dark |
| Background image | `store/background.png`, repeat, top centre |
| Column background (BG2) | `#241D2E` |
| Text | `#F1ECF7` |
| Link | `#56C4EF` |
| Button | `#8347AD`, with white text |
| Embed background | `#241D2E` |

The background is an Aseprite timeline seen from far away: rows of frame cells
with tag bars over the runs, in the extension's tag colours sunk to a third of
their strength so it stays behind the column. It is a 480 by 360 tile that wraps
both ways. To change it, edit the script and run it again:

    python3 store/make_background.py

## Assets still to make

**Cover image, 630 by 500.** Done: `store/cover.png`, drawn from
`store/cover.svg`. It shows
the transformation itself, a column of numbered filenames becoming a timeline
with coloured tag bars, and it was checked at 315 and 200 pixels wide, where the
title and the tag bars still read and the filenames collapse into texture. To
change it, edit the SVG and re-export:

    rsvg-convert -w 630 -h 500 store/cover.svg -o store/cover.png

**A short GIF.** Done: `store/demo.gif`, 900 by 558, 12.5 seconds, under a
megabyte. Three shots cut from one recording: a frame being dragged out of a
folder of 47, the prompt listing the twelve animations it found with three of
them unticked, and the built sprite with its colour-coded timeline. The middle
shot is framed close enough to read, which is the reason it is cut rather than
shown as one wide take. The character on the canvas is blurred, so the GIF is
about the extension rather than the art it happened to be run on.

Remade from a recording with the two below. The blur's boxes are measured for
this recording, so a new one needs them measured again (see the script):

    scripts/make-gif.sh recording.webm store/demo.gif --width 900 --fps 12
    python3 store/blur_sprite.py store/demo.gif store/demo.gif

**Three or four screenshots.** The drop prompt with its checkboxes. The full
options dialog. A finished timeline with coloured tags. A before and after of
replace mode, ideally the same sprite with a tag grown from three frames to six.

## Before publishing

Version 1.1 has not been run on Windows or macOS yet. The 1.0 build was tested on
Windows and worked, and the automated suites can be run on another machine with
`scripts/run-tests.ps1`, but the dialogs need someone to click them. Worth doing before
the page goes live, since the platform claim on the upload is a promise.
