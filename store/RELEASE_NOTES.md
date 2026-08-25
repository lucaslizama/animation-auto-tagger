# Animation Auto-Tagger 1.2

Release notes and a full account of what the extension does.

Pixel art tends to arrive as a pile of files: `hero_idle_00.png`, `hero_idle_01.png`,
`hero_run_00.png`, and so on down the folder. Game engines want the opposite of that, one sprite
whose timeline holds every frame in order with a tag per animation, because that is what an
importer reads to make animation clips. Doing the conversion by hand is a long afternoon of
importing, reordering and tagging. This extension does it in one step.

## Requirements

Aseprite 1.3.15 or newer. Tested against 1.3.18.2. The package is plain text (a manifest and a
handful of Lua files), so a package built on one platform installs on any of them: Windows, macOS
and Linux all work from the same file.

## Installing

Open **Edit ▸ Preferences ▸ Extensions ▸ Add Extension**, pick the `.aseprite-extension` file, and
restart Aseprite. On Windows and macOS, double-clicking the file works too. Afterwards the commands
live under **File ▸ Scripts**.

## Three ways to start

**From a folder.** Point it at any folder and it scans for image files, groups them by name and
shows what it found before anything is built.

**From sprites you already have open.** Everything currently open is read as source frames, which
suits the case where the art came from somewhere else and is already on screen.

**By dragging files in.** Drop frames onto Aseprite and a small prompt appears offering to build
them. It waits until the batch stops arriving rather than reacting to the first file, and it sits
alongside Aseprite's own windows rather than stacking a modal dialog on top of them. Build straight
away, open the full options, or ignore it.

## Reading the names

The default convention is `base_animation_index`, so `hero_run_03.png` means character `hero`,
animation `run`, frame 3. Almost every part of that is adjustable.

The separator is whatever character the files use. The animation name can be taken as the middle
token, as the last token, or the whole name can be treated as the animation when there is no
character prefix. Numbers glued straight onto the name (`run01`, no separator) are accepted on
request, and files with no number at all can be treated as one-frame animations instead of being
ignored. Tags can carry the base name as a prefix when a sprite holds more than one character.

For anything the built-in rules miss, a custom Lua pattern with capture groups for animation and
index takes over completely.

Tags come out in alphabetical order by default, or in the order the files were read.

## Filling in the gaps

Aseprite's drag and drop quietly drops files past roughly the tenth one, which means a drop of
twenty frames can deliver nine. Rather than build a broken animation from what survived, the
extension reads the rest back from the folder the files came from. It can pull in everything it
finds there, or only the frames belonging to animations that did arrive, or nothing at all.

One consequence worth knowing: dragging a single frame in is enough. The folder completion turns it
back into the whole character. That is the workflow to recommend to anyone who finds long drops
unreliable.

## Choosing what gets built

Every animation it detects gets a checkbox, on the drop prompt and in the full dialog both. Untick
one and it is left out of the build entirely, which is what you want when a folder holds a whole
character but only the walk cycle changed.

The ticks follow the animation rather than the row it happens to sit in, so changing the naming
options mid-session will not silently exclude something different from what was excluded before.
Ticks made on the drop prompt carry across if the full options are opened from it. The summary
counts what is actually ticked, and the build button greys out when nothing is.

## Putting the animations in order

Tags come out alphabetically by default, or in the order the files were read.

Rearranging them afterwards is a separate command rather than part of building,
since the two are separate decisions: what to bring in, and what order it should
end up in. It works on any sprite with more than one tag and is also on the
right-click menu of a tag in the timeline. Rows are dragged by a handle on the
left, reordering as the pointer passes so that what is under the cursor is
always what applying would produce, and a Sort button takes the whole list at
once: by name either way, longest or shortest animation first, or back to
the order the timeline has now. On applying, it rearranges the timeline so the
frames really move: every layer, every cel
position, every frame duration travels with its own tag, and the tags keep their
names, directions and colours. Aseprite has no command for moving frames, so
this works by lifting the cels off the timeline and writing them back in the new
order, all inside one undo step.

Two cases are refused rather than guessed at. Tags that share frames have no
order to be put in, so that is explained instead of attempted. Frames belonging
to no tag are moved to the end and keep their own relative order, since once the
blocks around them have moved there is nowhere else for them to be.

One side effect worth knowing: cels that Aseprite had linked, meaning several
frames sharing one image, become separate copies when they move. It looks
identical and takes a little more room. The result says so when it happens.

## Where the frames go

The result can be a new sprite, which is the ordinary case, or it can be added to a sprite that is
already open. The target is picked from a list of open sprites by name, not taken to be whichever
tab happens to be active, because after dropping files the active tab is one of the dropped frames
rather than the sprite meant to receive them.

Adding to an existing sprite puts the frames at the end of its timeline on a layer of their own, so
whatever art was already there is untouched. Tags are offset to match, and the whole thing is a
single undo step.

There is a second mode for a sprite that already has tags. Instead of adding alongside, an animation
whose name matches an existing tag is written over the frames that tag already spans, and the tag is
resized to fit. Import six `run` frames over a tag holding three and it grows to six, with every tag
after it sliding down to make room. Anything with no matching tag goes on the end as usual. The tag
itself is left alone, since its name, direction and colour belong to whoever made it; only the frames
beneath it change. A layer of the same name is reused rather than duplicated, so re-importing the
same character refreshes one layer instead of stacking up a new one every time.

Shrinking is the case to be careful with. When the import has fewer frames than the tag held, the
surplus frames are deleted, and deleting a frame in Aseprite takes every layer's cel on it, not just
the imported one. That is reported plainly in the result, and one undo takes it back.

A sprite is never allowed to be its own target. If the chosen sprite is also one of the frames going
in, the build stops instead of feeding half-written frames back into itself.

## Canvas size and alignment

The canvas can follow the largest source frame, follow the first one, or be a size typed in
directly. Frames smaller than the canvas are placed by an alignment setting: centred, or against any
corner or edge. Bottom-centre is usually right for characters standing on a ground line.

When adding to an existing sprite, the canvas grows if the incoming frames need the room, and the
art already on it moves to wherever the alignment says. The two ways of asking for a size are not
treated alike. Largest and first are read off the incoming frames, so they act as a floor and a
bigger sprite is simply left as it is. A typed size is an instruction, so it is honoured even when it
means shrinking the sprite, but since that crops art which was there beforehand it asks first, and
cancelling builds nothing.

## Timing

Frame duration is set in milliseconds and applies to every frame. Sources that carry timing of their
own, a GIF for instance, can keep it instead.

## Colour

The result can be RGB, grayscale, indexed, or whatever the first source happens to be. Sources are
composited in RGB and converted at the end, with one exception: when every source is indexed against
one identical palette, compositing happens directly in indexed so the palette indices survive
untouched. Mixed palettes have to be requantized, and there is no way around that.

Adding to an existing sprite keeps that sprite's colour mode rather than imposing one on it.
Appending into an indexed sprite is the weak spot: incoming colours are matched per source rather
than against the target's palette, so they can shift. The result says so when it happens.

## Tags and layers

Tag direction can be forward, reverse, ping-pong or ping-pong reverse. Each tag can be given a
colour from a rotating set, which makes a long tag list far easier to read on the timeline.

The layer takes the character's name by default, or any name typed in.

Files that genuinely hold an animation (GIF, Aseprite files, WebP, FLC) can contribute all of their
frames rather than just the first. A folder holding two characters can produce two sprites in one
pass instead of one mixed sprite, and each can be named after its character.

Source tabs opened during the build are closed afterwards, and a tab with unsaved changes in it is
never closed.

## Watching for drops

Aseprite's scripting interface has no drag and drop event, so detection works by watching the list
of open sprites and reacting once it stops growing. How often it looks, how long it waits, and how
many files a drop needs before it is worth reacting to are all adjustable. It can open the prompt or
build immediately, and it can be turned off entirely.

## Reading frames without opening them

Still frames are read directly rather than opened as sprites. Building from a folder of eighty
frames used to open eighty tabs and close them again; now it opens none, and the build is quicker
for it. Only files that really hold an animation still need opening, one per animation rather than
one per frame.

## What it will not do

Aseprite records an entry in its recent files list for every file it loads, and it does this deep
enough inside the program that no script can prevent it. Importing a folder of frames will therefore
fill that list, and since it holds sixteen entries by default, whatever was there before gets pushed
out. There is no way to read the list, prune it, or suppress the recording. The only thing Aseprite
offers is clearing the list outright, which would take genuine history with it, so the extension does
not do that on anyone's behalf.

The scripting interface has no drag and drop event either, which is why drops are detected by polling
rather than handled directly, and why Aseprite still opens each dropped file in its own tab before
the extension ever sees it.

## Getting the result into a game engine

Save as `.aseprite` and let an importer handle it. Godot importer plugins read the tags and turn each
one into its own animation clip, which is the whole reason for building a tagged timeline rather than
a folder of loose frames. Failing that, **File ▸ Export Sprite Sheet** with JSON data writes the tags
into the metadata under `frameTags`.

## Testing

The extension ships with its test suite. Most of it runs against a stand-in for Aseprite's scripting
interface, fast and offline, covering frame counts, tag ranges, cel placement and colour routing.
Two further suites run through a real Aseprite in batch mode, building from the bundled sample
frames, saving the result, reopening it and checking the tags survived the round trip. Those are the
ones that catch what a stand-in cannot: that inserting a frame just past a tag makes that tag swallow
it, for instance, or that appending to a sprite really does move its existing art the way the
alignment promises.
