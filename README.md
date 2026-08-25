# Animation Auto-Tagger

An Aseprite extension that takes a pile of separate frame files named
`hero_run_00.png`, `hero_run_01.png`, `hero_idle_00.png`, … and builds a single
sprite whose timeline holds every frame in order, with one tag per animation.

That tagged sprite is what engine-side importers want: Godot importer plugins
read Aseprite tags and turn each one into its own animation clip.

```
hero_idle_00.png  ┐
hero_idle_01.png  ├─►  hero.aseprite   frames 1-2   tag "idle"
hero_run_00.png   │                    frames 3-5   tag "run"
hero_run_01.png   │
hero_run_02.png   ┘
```

## Install

### From the packaged extension

```sh
scripts/build.sh    # writes dist/animation-auto-tagger.aseprite-extension
```

`dist/` is git-ignored, so a fresh clone has to build it first. Then in Aseprite
open **Edit ▸ Preferences ▸ Extensions ▸ Add Extension** and pick that file, and
restart. On Windows and macOS double-clicking the file works too.

The package is a renamed zip holding `package.json` and eight `.lua` files —
plain text, no compiled anything, and every path it touches goes through
`app.fs`. **A package built on one platform installs on any of them.**

### By hand

Copy `package.json` and the `.lua` files from `src/` (the list both scripts
both read is in `plugin-files.txt`) into a folder inside Aseprite's extensions
directory:

| | |
| --- | --- |
| Linux | `~/.config/aseprite/extensions/animation-auto-tagger/` |
| Windows | `%AppData%\Aseprite\extensions\animation-auto-tagger\` |
| macOS | `~/Library/Application Support/Aseprite/extensions/animation-auto-tagger/` |

`README.md` and `LICENSE` are along for the ride and can be left out. On Linux
`scripts/install.sh` does all of this; run it again after an edit and restart
Aseprite. It keeps the plugin's saved settings across a reinstall.

It has to be a real folder, **not a symlink**: Aseprite does not follow one when
it scans for extensions, and it says nothing when it skips one — the plugin just
never appears. Uninstall by deleting the folder.

Not sure where the directory is on a given machine? Ask Aseprite:

```sh
aseprite --batch --script <(echo 'print(app.fs.userConfigPath)')
```

### Check it loaded

Restart, then look for **File ▸ Scripts ▸ Animation Auto-Tagger**. Without the
GUI:

```sh
aseprite --batch --script <(echo 'for k in pairs(package.loaded) do
  if tostring(k):find("animation%-auto%-tagger") then print(k) end end')
```

That should list eight modules. It is `package.loaded`, not the `_LOADED`
global older Lua snippets reach for — Aseprite runs Lua 5.4, which keeps that
table in the registry instead. Tested against Aseprite 1.3.18.2; it needs
1.3.15 or newer for `app.tip` and the menu-checkbox support.

## About dragging files in

This is the part worth being straight about: **Aseprite's scripting API has no
drag-and-drop event.** `app.events` exposes only `sitechange`,
`beforesitechange`, `fgcolorchange`, `bgcolorchange`, `beforecommand` and
`aftercommand`, and dropping files onto the editor is handled inside Aseprite's
C++ without going through a named command a script can hook. There is no way to
intercept the drop itself, and no way to stop Aseprite opening each dropped
file in its own tab.

So the extension approaches it from the other side. Enable **Watch for Dropped
Frames** and it polls the open-sprite list on a `Timer`. When a burst of new
file-backed sprites appears and then stops growing, it groups their names and
offers to build the tagged sprite from them. In practice that means: drag your
frames in, Aseprite opens them as tabs, and a moment later you get a prompt.

The polling is cheap (a loop over `app.sprites` a few times a second) and the
debounce is what stops a twelve-file drag from asking twelve times.

There is a second problem with dropping files, and this one is a bug rather than
a missing feature. **Aseprite's X11 drop handler concatenates the dropped paths
into a single string without reading it in chunks**, so once the list passes
roughly 867 characters it is cut mid-path. Drag twenty frames on Linux and about
half of them never arrive; you get an error naming a truncated path instead. It
is a known, unfixed Aseprite issue, and no script can reach the drop to correct
it.

What the plugin does instead is refuse to care. Everything that *did* arrive
came from one folder, so it reads the rest off disk and builds the whole
character anyway. **Fill in from folder** controls this, both in the settings
and live in the main dialog: `folder` (default) takes every matching file in
that folder, `gaps` fills in only the animations that arrived, `off` uses
exactly what was dropped. The summary line says how many were recovered.

Aseprite's error window is still on screen while this happens, so the watcher's
prompt is a non-modal dialog rather than an alert — it waits alongside instead
of stacking a second modal on top. Dismiss Aseprite's error whenever; the prompt
does not mind. The error itself cannot be suppressed: it comes from Aseprite,
before any script runs.

Which suggests the better move — **drag one frame, not twenty.** A single path is
nowhere near the character limit, so nothing is truncated and no error appears at
all; the folder completion turns that one file back into the whole character.
One file in, twenty frames and five tags out. The test suite checks that too.

Watching is still off by default; the two menu commands below need none of this
machinery.

## Using it

**File ▸ Scripts ▸ Animation Auto-Tagger ▸ Tag Open Sprites…**
Reads every open sprite that came from a file, then fills in the rest of the
folder. This is the one to use right after dragging frames in — and dragging a
single frame is enough.

**… ▸ Tag Frames in a Folder…**
Pick any file in a folder and it scans the whole folder. Nothing has to be open
first.

**… ▸ Watch for Dropped Frames**
Toggles the polling watcher described above. **… ▸ Auto-Tagger Settings…** has
its poll interval, how long it waits for a drag to settle, how many matching
frames are needed before it speaks up, how much of a truncated drop to recover
from the folder, and whether it builds straight away instead of asking.

Either command opens the same dialog, which lists the animations it found and
the frame count for each before you commit to anything. Change a naming option
and the list re-groups immediately.

## One thing Aseprite does that gets in the way

Opening `hero_run_00.png` makes Aseprite look for `hero_run_01.png`,
`hero_run_02.png` and so on, and load the whole run as frames of one sprite.
That is a nice feature in general and a menace here, since the numbered-suffix
naming is the very thing this plugin keys on — six files would each contribute
all six frames and you would end up with 21 frames instead of 6.

Files the plugin reads itself sidestep this entirely: a still frame is read as
an `Image`, not opened as a `Sprite`. An image is one frame by definition, so
there is no sequence to detect — and no tab, either. Build from a folder of
eighty frames and no document appears but the one you asked for.

Only files that genuinely hold an animation — `.gif`, `.aseprite`, `.webp`,
`.flc` — still need opening, and those are one file per animation rather than
one per frame.

Sprites that were *already* open are a different matter, and it cuts the other
way: drag twenty frames in and Aseprite hands you five sprites, each holding a
whole run, not twenty sprites holding one frame each. Those frames are real, so
they are all kept — and any sibling file whose frames a sequence has already
swallowed is skipped instead of being counted twice. Both routes end at the same
20-frame, 5-tag sprite; the test suite checks that they agree.

That is also why the dialog counts frames rather than files: one entry can be
six frames.

The two behaviours compose, which is the point: a drop that lost eleven of its
twenty files, where the nine survivors each dragged part of their run along with
them, still comes out as one 20-frame sprite with five correct tags. There is an
end-to-end test for exactly that.

### What this does not fix

Aseprite adds an entry to its recent-files list for every file it loads, and it
does so inside its own loader — `Image{fromFile}` and `Sprite{fromFile}` are
recorded alike. There is no `app.recentFiles` to read or prune, and
`general.recent_items = 0` does not suppress the recording. So importing a
folder of frames still fills that list, and with a default cap of 16 entries it
will push out whatever was there before. The only lever Aseprite offers is
`ClearRecentFiles`, which empties the list entirely, your own history included —
too blunt to do to someone without asking, so the plugin does not.

## The naming convention

The default is `base_animation_index`:

| file | base | animation | index |
| --- | --- | --- | --- |
| `hero_run_00.png` | `hero` | `run` | 0 |
| `hero_attack_heavy_00.png` | `hero` | `attack_heavy` | 0 |
| `run_00.png` | — | `run` | 0 |
| `hero_run2_05.png` | `hero` | `run2` | 5 |

The trailing number is always the frame index; digits inside the name stay put.
Frames sort numerically, so `_2` comes before `_10` — the thing plain
alphabetical sorting gets wrong.

What counts as the animation name is a setting, because `hero_attack_heavy_00`
is genuinely ambiguous:

- **first token is the character** (default) — base `hero`, animation `attack_heavy`
- **animation is the last token** — base `hero_attack`, animation `heavy`
- **whole name is the animation** — no base, animation `hero_attack_heavy`

Also configurable: the separator (`-`, `.`, anything), whether `run01` counts as
a frame index without a separator, whether a file with no number at all becomes a
one-frame animation, and a **custom Lua pattern** if none of that fits. The
pattern needs either two captures `(animation)(index)` or three
`(base)(animation)(index)`, e.g. `^(%w+)@(%w+)@(%d+)$`.

## Result options

| Option | What it does |
| --- | --- |
| Build into | A new sprite, or one already open — see below |
| Existing tags | When building into an open sprite: add alongside, or replace matching |
| Frame duration | Milliseconds per frame (default 100) |
| Keep source durations | For multi-frame sources, copy their timing instead |
| Canvas size | Largest source frame, the first one, or a size you type |
| Tag order | Alphabetical, the order files were read, or arranged by hand |
| Align smaller frames | center, top-left, top-center, bottom-left, bottom-center — bottom-center is usually right for characters standing on a ground line |
| Color mode | rgb (default), gray, indexed, or match the first source |
| Tag direction | forward, reverse, ping-pong, ping-pong-reverse |
| Layer name | Blank uses the base name |
| Expand multi-frame files | A `.gif` or `.aseprite` holding a whole animation contributes all of its frames |
| One sprite per base name | Drag two characters in at once and get two sprites |
| Name the sprite after the base | The new sprite gets `hero.aseprite` as its filename, unsaved |
| Give each tag a color | Makes a long tag list readable on the timeline |
| Close the source tabs | Tidies up after a drag; never closes a tab with unsaved changes |

A note on colour: sources are composited in RGB and converted at the end, except
when every source is indexed against one identical palette — then it composites
directly in indexed so the palette indices survive untouched. Mixed palettes get
requantized, which is unavoidable.

### Appending to a sprite you already have

**Build into ▸ an open sprite** adds the frames to the end of that sprite's
timeline instead of making a new one, on a layer of its own, in one undo step.
The second dropdown picks which open sprite; it is numbered because two tabs can
share a name and an unsaved one has none.

The sprite being appended to keeps its colour mode and its filename, so
**Color mode** and **Name the sprite after the base** stop applying. **One
sprite per base name** cannot apply either: it asks for several sprites and
there is only one.

Its canvas, though, will change. Frames wider or taller than it are not cropped
— the canvas is enlarged to hold them and the art already on it moves to
wherever **Align smaller frames** says, all inside the same undo step.

`largest source frame` and `first source frame` can only ever grow it, since
they are read off the incoming frames rather than asked for. A **custom** size
is different: it is a number you typed, so it is honoured even when it is
smaller than the sprite — but because that crops art which was there first, it
asks before doing it, and cancelling builds nothing.

### Replacing what is already there

**Existing tags ▸ replace matching** treats the import as an update rather than
an addition. An animation whose name matches a tag already on the sprite is
written over the frames that tag spans, and the tag is resized to fit: import
six `run` frames over a tag holding three and it grows to six, with every tag
after it sliding down to make room. Anything with no matching tag is added at
the end as usual.

The tag itself is left alone — its name, direction and colour are yours; only
the frames beneath it change. A layer of the same name is reused too, so
re-importing a character refreshes one layer instead of stacking up a new one
each time.

One thing to be careful of: when the import has **fewer** frames than the tag
held, the surplus frames are deleted outright, and deleting a frame takes every
layer's cel on it, not just the imported one. That is reported in the result,
and one undo takes it all back.

### Ordering the animations

**Tag order** can be alphabetical, the order the files were read, or *as
arranged below*, which turns on the Up and Dn buttons beside each animation.
The tags are laid down the timeline in whatever order the list ends up in.

For a sprite that already exists there is **File ▸ Scripts ▸ Reorder Tags**. It
lists the tags with the same arrows and, on Apply, rearranges the timeline so
the frames actually move to match: every layer, every cel position, every frame
duration travels with its own tag, and the tags keep their names, directions and
colours. Aseprite has no command for moving frames, so this works by lifting the
cels off the timeline and writing them back in the new order, all inside one
undo step.

Two things it will not do. Tags that share frames have no order to be put in, so
that is refused with an explanation rather than guessed at. And frames belonging
to no tag are moved to the end, keeping their own relative order, since there is
nowhere else for them to go once the blocks around them have moved.

Cels that Aseprite had linked (several frames sharing one image) become separate
copies when they move. It looks identical and takes a little more room; the
result says so when it happens.

### Choosing what gets imported

Each detected animation gets a checkbox. Unticking one leaves it out of the
build entirely — useful when a folder holds a whole character but only the walk
cycle changed. The summary counts what is actually ticked, and Build greys out
when nothing is.

They appear in both places you can build from: the prompt that comes up after a
drop, and the full dialog behind **Options**. Ticks made on the prompt are
carried across if you open Options from it, so nothing quietly resets.

The prompt is built fresh for each drop and has exactly one row per animation.
The full dialog cannot grow after it opens — Aseprite has no way to add a widget
to a dialog already on screen — so its rows are sized with headroom when it
opens. In the unlikely event that changing the naming options produces more
animations than there are rows, the surplus is listed as included rather than
being dropped quietly.

### Other things worth knowing

A sprite cannot be appended to itself — if the
target is also one of the frames going in, the build is refused rather than
reading half-written frames back into itself. And appending into an **indexed**
sprite can shift colours: each source is quantized against a palette of its own,
not against the target's, so the indices mean something else once they land.

## Getting it into Godot

Save the result as `.aseprite` and let your importer handle it, or use
**File ▸ Export Sprite Sheet** with JSON data — the tags come out under
`meta.frameTags`, which is what sheet-based importers read. Aseprite Wizard is a
commonly used Godot plugin for this. Check what your importer expects; this
extension's job ends at producing a correctly tagged sprite.

## Sample frames

`samples/hero/` holds 20 frames to try it on:

| tag | frames | size |
| --- | --- | --- |
| `idle` | 4 | 32x32 |
| `run` | 6 | 32x32 |
| `attack` | 5 | 40x32 |
| `jump` | 3 | 32x32 |
| `hurt` | 2 | 32x32 |

Each one draws its animation letter and its frame index, so the built timeline
is easy to check by eye. The attack frames are deliberately wider, which is what
exercises the canvas-size and alignment options.

Regenerate them, or make a second character to try **one sprite per base name**,
with:

```sh
python3 samples/make_samples.py samples/orc orc
```

## Tests

```sh
scripts/run-tests.sh     # Linux, macOS
```

```powershell
.\scripts\run-tests.ps1  # Windows
```

Aseprite exits 0 no matter what a script decides — its Lua has no `os.exit` —
so the end-to-end suites print `e2e-result: ok` or `e2e-result: FAIL` and both
runners read the verdict from that. Without it a failing end-to-end run scrolls
past and the runner still reports success.

`naming.lua` is dependency-free, and the builder, watcher and collector suites
run against `tests/fake_aseprite.lua`, a stand-in covering the API surface those
modules touch — so most of it needs no Aseprite at all.

If a real Aseprite is on the machine (it looks on `PATH` and in the usual Steam
locations, or set `ASEPRITE=`), the runner also executes `e2e_aseprite.lua`
through it in batch mode: build the sample folder, check the frame count, tag
ranges, canvas size and cel placement, then save, reopen and confirm the tags
survived. A second pass, `e2e_dragpath.lua`, runs the same checks over sprites
Aseprite opened itself, which is the closest a script can get to reproducing a
drag. Those are the suites that caught the sequence-loading behaviour above,
which no stand-in would have predicted.

## Layout

The sources live in `src/`, but Aseprite resolves an extension's `require`
calls from the extension root, so the packaged and installed extension is flat:
`src/naming.lua` lands as `naming.lua` beside the rest. Both scripts do that
flattening, and it is the only place the two layouts differ.

| Where | |
| --- | --- |
| `src/main.lua` | Plugin entry point, menu commands, settings dialog |
| `src/naming.lua` | Filename parsing and grouping (pure Lua, no Aseprite) |
| `src/collect.lua` | Gathering candidate frames from a folder or from open sprites |
| `src/sources.lua` | Reading source frames — as images where possible, sprites where not |
| `src/builder.lua` | Assembling the tagged sprite |
| `src/reorder.lua` | Rearranging the tag blocks on a sprite that already exists |
| `src/ui.lua` | The main dialog |
| `src/watcher.lua` | Timer-based drop detection |
| `src/config.lua` | Defaults and preference persistence |
| `tests/e2e_aseprite.lua` | End-to-end check run through a real Aseprite in batch mode |
| `tests/e2e_dragpath.lua` | The same, but over files Aseprite opened itself — the drag case |
| `scripts/` | `install.sh` copies into Aseprite for development, `build.sh` packs a distributable extension, `run-tests.sh` and `run-tests.ps1` run the suites |
| `samples/` | Twenty sample frames across five animations, used by the end-to-end suites |
| `store/` | Release notes, the itch.io page copy and its cover art. Nothing here ships in the extension |
