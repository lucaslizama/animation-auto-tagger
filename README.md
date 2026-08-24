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

Run `./build.sh` to produce `dist/animation-auto-tagger.aseprite-extension`,
then in Aseprite go to **Edit ▸ Preferences ▸ Extensions ▸ Add Extension** and
pick that file. Restart Aseprite.

While working on the extension, `./install.sh` copies it straight into
`~/.config/aseprite/extensions/animation-auto-tagger/`, skipping the packaging
step. Run it again after an edit and restart Aseprite.

It has to be a copy, not a symlink: **Aseprite does not follow a symlink when it
scans for extensions**, and it says nothing when it skips one — the plugin just
never appears. That path is the same for a Steam install, since Aseprite is not
sandboxed and keeps its user data in `~/.config/aseprite/`. Uninstall by
deleting the directory.

Either way the commands land under **File ▸ Scripts ▸ Animation Auto-Tagger**.
Tested against Aseprite 1.3.18.2; it needs 1.3.15 or newer for `app.tip` and
the menu-checkbox support.

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
One file in, twenty frames and five tags out. `run-tests.sh` checks that too.

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

Files the plugin opens itself are therefore loaded one frame at a time, which
settles the folder path completely.

Sprites that were *already* open are a different matter, and it cuts the other
way: drag twenty frames in and Aseprite hands you five sprites, each holding a
whole run, not twenty sprites holding one frame each. Those frames are real, so
they are all kept — and any sibling file whose frames a sequence has already
swallowed is skipped instead of being counted twice. Both routes end at the same
20-frame, 5-tag sprite; `run-tests.sh` checks that they agree.

That is also why the dialog counts frames rather than files: one entry can be
six frames.

The two behaviours compose, which is the point: a drop that lost eleven of its
twenty files, where the nine survivors each dragged part of their run along with
them, still comes out as one 20-frame sprite with five correct tags. There is an
end-to-end test for exactly that.

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
| Frame duration | Milliseconds per frame (default 100) |
| Keep source durations | For multi-frame sources, copy their timing instead |
| Canvas size | Largest source frame, or the first one |
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
./run-tests.sh
```

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

| File | |
| --- | --- |
| `main.lua` | Plugin entry point, menu commands, settings dialog |
| `naming.lua` | Filename parsing and grouping (pure Lua, no Aseprite) |
| `collect.lua` | Gathering candidate frames from a folder or from open sprites |
| `sources.lua` | Opening, colour-converting and closing source sprites |
| `builder.lua` | Assembling the tagged sprite |
| `ui.lua` | The main dialog |
| `watcher.lua` | Timer-based drop detection |
| `config.lua` | Defaults and preference persistence |
| `e2e_aseprite.lua` | End-to-end check run through a real Aseprite in batch mode |
| `e2e_dragpath.lua` | The same, but over files Aseprite opened itself — the drag case |
| `install.sh` / `build.sh` | Copy into Aseprite for development / pack a distributable extension |
