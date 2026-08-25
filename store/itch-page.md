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

### The problem

Pixel art comes out of a folder looking like this:

    hero_idle_00.png   hero_run_00.png   hero_attack_00.png
    hero_idle_01.png   hero_run_01.png   hero_attack_01.png
    hero_idle_02.png   hero_run_02.png   hero_attack_02.png

Engines want the opposite: one sprite whose timeline holds every frame in order,
with a tag per animation, because that is what an importer reads to make
animation clips. Building it by hand is an afternoon of importing, dragging
frames into order, and typing tag names.

Animation Auto-Tagger does it in one step.

    hero_idle_00.png  ┐
    hero_idle_01.png  ├──►  hero.aseprite   frames 1-2   tag "idle"
    hero_run_00.png   │                     frames 3-5   tag "run"
    hero_run_01.png   │
    hero_run_02.png   ┘

### The part that matters after the first day

Building the sprite once is the easy half. The real work is what happens when
the animation gets redrawn, and that is what this is built for.

Set **Existing tags** to *replace matching* and an import becomes an update. An
animation whose name matches a tag already on the sprite is written over the
frames that tag spans, and the tag is resized to fit. Import six `run` frames
over a tag holding three and it grows to six, with every tag after it sliding
down to make room. Anything with no matching tag goes on the end.

The tag itself is left alone. Its name, direction and colour stay as they were,
because they belong to whoever made them; only the frames beneath change. A
layer of the same name is reused rather than duplicated, so re-importing the same
character refreshes one layer instead of stacking up a new one every time.

All of it is a single undo step.

### Import only what changed

Every animation it detects gets a checkbox before anything is built. When a
folder holds a whole character but only the walk cycle was redrawn, tick that one
and leave the rest alone.

### Put them in the order that makes sense

A build lays the tags down alphabetically or in the order the files were read.
Rearranging them is a separate command, on any sprite with more than one tag. It lists the tags with Up and Down
buttons and, on applying, rearranges the timeline so the frames actually move: every layer, every cel position, every frame duration travels with its own
tag, and the tags keep their names, directions and colours. Aseprite offers no
way to do this short of dragging frame ranges around by hand. Tags that share
frames are refused rather than guessed at, and it is one undo step like
everything else.

### Three ways in

Point it at a folder. Or read the sprites already open. Or just drag frames onto
Aseprite: a small prompt appears offering to build them, waits until the batch
stops arriving rather than reacting to the first file, and sits alongside
Aseprite's own windows instead of stacking a dialog on top of them.

Aseprite's drag and drop quietly loses files past roughly the tenth one, so a
drop of twenty frames can arrive as nine. Rather than build a broken animation
out of the survivors, the missing frames are read back from the folder they came
from. Dragging a single frame in is enough to rebuild the whole character.

### Everything else it does

Names are read as `base_animation_index` by default, and nearly every part of
that is adjustable: the separator, whether the animation is the middle token or
the last one or the whole name, numbers glued straight onto the name, files with
no number at all, and a custom Lua pattern for anything the built-in rules miss.

Canvas size follows the largest frame, the first frame, or a size typed in
directly. Smaller frames are placed by an alignment setting, and bottom-centre is
usually right for characters standing on a ground line. Frame duration is set in
milliseconds, or taken from sources that carry timing of their own. Tags can run
forward, reverse, ping-pong or ping-pong reverse, and can be given colours that
make a long tag list readable on the timeline. A folder holding two characters
can produce two sprites in one pass. Indexed art keeps its palette indices
untouched when every source shares one palette.

Still frames are read directly rather than opened, so building from a folder of
eighty frames opens no tabs at all.

### Getting it into an engine

Save as `.aseprite` and let an importer handle it. Godot importer plugins read
the tags and turn each one into its own animation clip, which is the whole reason
for building a tagged timeline instead of a folder of loose frames. Failing that,
**File ▸ Export Sprite Sheet** with JSON data writes the tags into the metadata
under `frameTags`.

### What it will not do

Aseprite records an entry in its recent files list for every file it loads, deep
enough inside the program that no script can prevent it. Importing a folder of
frames will fill that list, and since it holds sixteen entries by default,
whatever was there before gets pushed out. There is no way to read the list,
prune it, or suppress the recording. Aseprite offers only clearing it outright,
which would take genuine history with it, so this extension does not do that on
anyone's behalf.

The scripting interface has no drag and drop event either. That is why drops are
detected by watching the open sprite list rather than handled directly, and why
Aseprite still opens each dropped file in its own tab before the extension ever
sees it.

### Requirements

Aseprite 1.3.15 or newer, tested against 1.3.18.2. The package is plain text, a
manifest and a handful of Lua files, so the same file installs on Windows, macOS
and Linux.

Install through **Edit ▸ Preferences ▸ Extensions ▸ Add Extension**, then
restart. If an older copy is already installed, remove it first: installing on
top of it can leave old files behind. On Windows and macOS, double-clicking the file works too. The commands
appear under **File ▸ Scripts**.

### Source

MIT licensed. The source is at
https://github.com/lucaslizama/animation-auto-tagger, and bug reports and pull
requests are welcome.

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
shown as one wide take.

Remade from a recording with:

    scripts/make-gif.sh recording.webm store/demo.gif --width 900 --fps 12

**Three or four screenshots.** The drop prompt with its checkboxes. The full
options dialog. A finished timeline with coloured tags. A before and after of
replace mode, ideally the same sprite with a tag grown from three frames to six.

## Before publishing

Version 1.1 has not been run on Windows or macOS yet. The 1.0 build was tested on
Windows and worked, and the automated suites can be run on another machine with
`scripts/run-tests.ps1`, but the dialogs need someone to click them. Worth doing before
the page goes live, since the platform claim on the upload is a promise.
