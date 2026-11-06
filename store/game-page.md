[Turn a folder of numbered frames into one Aseprite sprite with a tag per animation, and update it in place when the art changes.]{125%}

:::center
![A frame dragged onto Aseprite, the prompt listing the animations it found, and the finished sprite with its coloured tags](media/animation-auto-tagger-demo.gif)
:::

Engines want one sprite with a tagged timeline, because that is what an importer turns into animation clips. Building it by hand is an afternoon of importing, dragging frames into order and typing tag names. This does it in one step:

```
hero_idle_00.png  ┐
hero_idle_01.png  ├──►  hero.aseprite   frames 1-2   tag "idle"
hero_run_00.png   │                     frames 3-5   tag "run"
hero_run_01.png   │
hero_run_02.png   ┘
```

## What it does

- **[Re-import in place.]{#A76BD1}** When an animation is redrawn, importing it again writes over the frames its tag spans. The tag grows or shrinks to fit and every tag after it slides along. Names, directions and colours stay as you left them, and it is one undo step.
- **[Import only what changed.]{#56C4EF}** Every animation it finds gets a checkbox, so a redrawn walk cycle can go in without touching the rest.
- **[Reorder tags.]{#E5813C}** Drag the tags into the order you want and the frames move with them: every layer, cel and frame duration. Aseprite has no way to do this short of dragging frame ranges by hand.
- **[Three ways in.]{#5CB870}** Point it at a folder, read the sprites already open, or just drag frames onto Aseprite. Aseprite drops files past roughly the tenth in a drag, so the missing ones are read back from their folder. One frame is enough to rebuild a whole character.
- **[Ready for an engine.]{#D65A7A}** Godot importer plugins turn each tag into its own clip. Sprite sheet exports carry the tags in their JSON as `frameTags`.
- **[Opens no tabs.]{#C9B33F}** Still frames are read directly, so a folder of eighty builds without eighty tabs.

:::collapse Every option
Names are read as `base_animation_index` by default. The separator, which token is the animation, numbers glued onto the name, files with no number at all, and a custom Lua pattern can all be set.

Canvas size follows the largest frame, the first frame, or a size you type, with smaller frames placed by an alignment setting (bottom-centre suits characters on a ground line). Frame duration is set in milliseconds or taken from sources that carry their own. Tags can run forward, reverse, ping-pong or ping-pong reverse, and can be coloured to make a long list readable. A folder holding two characters makes two sprites in one pass, and indexed art keeps its palette indices when every source shares one palette.
:::

:::collapse What it can't do
Aseprite adds every file it loads to its recent files list, and no script can stop it, read it or prune it. Importing a folder of frames will push older entries out. The only option Aseprite offers is clearing the list outright, which would take real history with it, so the extension leaves that to you.

The scripting API has no drag and drop event either, which is why Aseprite still opens each dropped file in a tab before the extension sees it.
:::

## Install

Needs **Aseprite 1.3.15 or newer** (tested on 1.3.18.2). One file installs on Windows, macOS and Linux.

1. Remove any older copy first, so no old files are left behind.
2. **Edit ▸ Preferences ▸ Extensions ▸ Add Extension**, pick the file, and restart Aseprite. On Windows and macOS, double-clicking the file works too.
3. The commands are under **File ▸ Scripts ▸ Animation Auto-Tagger**. Building also sits in the File menu beside Import, and reordering on a tag's right-click menu.

:::box purple
**Bind a key** for anything you use daily: **Edit ▸ Keyboard Shortcuts**, then search for the command. Extensions can't ship a default shortcut, so this one is up to you.
:::

:::frame #8347AD
MIT licensed. The source is [on GitHub](https://github.com/lucaslizama/animation-auto-tagger), and bug reports in the comments below are the reason it ships.
:::

:::center
[![Made with Sublime Itch](media/6c6ff198538f.gif)](https://generic-cat.itch.io/sublime-itch)
:::
