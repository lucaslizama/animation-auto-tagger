--- The Animation Auto-Tagger dialog.
--
-- Every option the plugin has is exposed here rather than baked into the code,
-- and the frame list re-groups live as the options change, so you can see what
-- the tags will be before anything is built.

local naming  = require("naming")
local config  = require("config")
local collect = require("collect")
local sources = require("sources")
local builder = require("builder")

local M = {}

local PREVIEW_ROWS = 14

-- { label shown in the combobox, value stored in the config }
local ANIM_MODES = {
  { "first token is the character",  "middle" },
  { "animation is the last token",   "last" },
  { "whole name is the animation",   "whole" },
}
local GROUP_ORDERS = {
  { "alphabetical", "alphabetical" },
  { "file order",   "first-seen" },
}
local CANVAS_MODES = {
  { "largest source frame", "max" },
  { "first source frame",   "first" },
  { "custom",               "custom" },
}

local function labelsOf(pairsList)
  local out = {}
  for i, p in ipairs(pairsList) do out[i] = p[1] end
  return out
end

local function labelFor(pairsList, value)
  for _, p in ipairs(pairsList) do
    if p[2] == value then return p[1] end
  end
  return pairsList[1][1]
end

local function valueFor(pairsList, label)
  for _, p in ipairs(pairsList) do
    if p[1] == label then return p[2] end
  end
  return pairsList[1][2]
end

local function plural(n, word)
  return ("%d %s%s"):format(n, word, n == 1 and "" or "s")
end

local function indexRange(items)
  local first, last
  for _, it in ipairs(items) do
    local t = it.parsed and it.parsed.indexText
    if t then
      first = first or t
      last = t
    end
  end
  if first then return (" [%s..%s]"):format(first, last) end
  return ""
end

--- Frames a group will really contribute. An open sprite that Aseprite loaded
-- as a numbered sequence is one entry but many frames, and the preview would
-- lie if it counted files.
local function groupFrames(group, cfg)
  local n = 0
  for _, item in ipairs(group.items) do
    n = n + sources.frameCountOf(item, cfg)
  end
  return n
end

--- Human-readable preview of what would be built.
function M.previewLines(grouped, cfg)
  local lines = {}
  for _, g in ipairs(grouped.groups) do
    lines[#lines + 1] = ("%s  -  %s%s")
      :format(g.name, plural(groupFrames(g, cfg), "frame"), indexRange(g.items))
  end
  for i, u in ipairs(grouped.unmatched) do
    if i > 4 then
      lines[#lines + 1] = ("(+%d more ignored)"):format(#grouped.unmatched - 4)
      break
    end
    lines[#lines + 1] = ("ignored: %s  -  %s"):format(u.entry.title, u.reason)
  end
  for i, w in ipairs(grouped.warnings) do
    if i > 3 then break end
    lines[#lines + 1] = "warning: " .. w
  end
  return lines
end

--- Total frames a grouping will really produce.
function M.frameTotal(grouped, cfg)
  local frames = 0
  for _, g in ipairs(grouped.groups) do frames = frames + groupFrames(g, cfg) end
  return frames
end

function M.summaryLine(grouped, cfg)
  local frames = M.frameTotal(grouped, cfg)
  local s = ("%s, %s"):format(plural(#grouped.groups, "animation"), plural(frames, "frame"))
  if #grouped.unmatched > 0 then
    s = s .. (", %s ignored"):format(plural(#grouped.unmatched, "file"))
  end
  if #grouped.bases > 1 then
    s = s .. (", %s"):format(plural(#grouped.bases, "base name"))
  end
  return s
end

--- The open sprites, as { label, sprite } pairs for the target chooser.
--
-- The index is part of the label because two tabs can carry the same name --
-- and an unsaved sprite carries none at all -- while a combobox can only hand
-- back the string the user picked.
local function openSpriteChoices()
  local choices = {}
  for i, sp in ipairs(app.sprites) do
    local name = (sp.filename ~= "" and app.fs.fileTitle(sp.filename)) or "untitled"
    choices[#choices + 1] = { label = ("%d. %s"):format(i, name), sprite = sp }
  end
  return choices
end

--- The sprite behind a chooser label, or nil.
local function spriteForLabel(choices, label)
  for _, c in ipairs(choices) do
    if c.label == label then return c.sprite end
  end
end

--- Read the dialog widgets back into a config table.
local function readConfig(dlg, base)
  local cfg = {}
  for k, v in pairs(base) do cfg[k] = v end
  local d = dlg.data

  cfg.separator         = (d.separator ~= "" and d.separator) or "_"
  cfg.animMode          = valueFor(ANIM_MODES, d.animMode)
  cfg.groupOrder        = valueFor(GROUP_ORDERS, d.groupOrder)
  cfg.allowGluedIndex   = d.allowGluedIndex
  cfg.allowNoIndex      = d.allowNoIndex
  cfg.customPattern     = d.customPattern or ""
  cfg.prefixTagWithBase = d.prefixTagWithBase
  cfg.completeDrops     = d.completeDrops

  cfg.frameDurationMs   = math.max(1, math.floor(tonumber(d.frameDurationMs) or 100))
  cfg.keepSourceDurations = d.keepSourceDurations
  cfg.buildTarget       = d.buildTarget
  cfg.targetLabel       = d.targetSprite   -- runtime only, never persisted
  cfg.canvasMode        = valueFor(CANVAS_MODES, d.canvasMode)
  cfg.canvasWidth       = math.max(1, math.floor(tonumber(d.canvasWidth) or 1))
  cfg.canvasHeight      = math.max(1, math.floor(tonumber(d.canvasHeight) or 1))
  cfg.align             = d.align
  cfg.colorMode         = d.colorMode
  cfg.aniDir            = d.aniDir
  cfg.expandMultiFrame  = d.expandMultiFrame
  cfg.layerName         = d.layerName or ""
  cfg.splitByBase       = d.splitByBase
  cfg.closeSources      = d.closeSources
  cfg.nameSpriteAfterBase = d.nameSpriteAfterBase
  cfg.colorizeTags      = d.colorizeTags

  return cfg
end

--- Do the build and report what happened.
-- Returns true when at least one sprite was produced. `target` is the sprite
-- to append to; without one, an appending build falls back to the active
-- sprite, which is all the watcher's auto-build path can know about.
function M.run(entries, cfg, folder, target)
  local grouped = naming.group(entries, config.namingOpts(cfg))
  if #grouped.groups == 0 then
    app.alert {
      title = "Animation Auto-Tagger",
      text = { "None of these files match the naming pattern.",
               "Expected something like  name" .. cfg.separator .. "animation"
                 .. cfg.separator .. "00" },
    }
    return false
  end

  -- One place decides what is being appended to, and one alert covers there
  -- being nothing to append to.
  if cfg.buildTarget == "new sprite" then
    target = nil
  else
    target = target or app.sprite
    if not target then
      app.alert {
        title = "Animation Auto-Tagger",
        text = { "There is no sprite to append to.",
                 'Open one first, or set Build into back to "new sprite".' },
      }
      return false
    end
  end

  -- Cropping art that was on the sprite before this ran is not something to
  -- report after the event, so it is asked about while it can still be
  -- refused. Only a typed size gets here; max and first never shrink anything.
  local allowShrink = false
  if target and cfg.canvasMode == "custom"
     and (cfg.canvasWidth < target.width or cfg.canvasHeight < target.height) then
    local name = (target.filename ~= "" and app.fs.fileTitle(target.filename)) or "the sprite"
    local answer = app.alert {
      title = "Animation Auto-Tagger",
      text = { ("Resizing to %dx%d will crop %s, which is %dx%d.")
                 :format(cfg.canvasWidth, cfg.canvasHeight, name, target.width, target.height),
               "Anything outside the new canvas is lost." },
      buttons = { "Resize", "Cancel" },
    }
    if answer ~= 1 then return false end
    allowShrink = true
  end

  local pool = sources.newPool()
  local reports, errors, notes = builder.buildAll(grouped, cfg,
    { pool = pool, folder = folder, target = target, allowShrink = allowShrink })
  sources.release(pool, cfg)

  if #reports == 0 then
    app.alert {
      title = "Animation Auto-Tagger",
      text = { "Nothing could be built.", table.unpack(errors) },
    }
    return false
  end

  app.sprite = reports[1].sprite
  app.refresh()

  -- Only genuine problems are worth interrupting for. Sequence skips are
  -- expected on the drag path and would otherwise fire an alert every time.
  local problems = {}
  for _, e in ipairs(errors) do problems[#problems + 1] = e end
  for _, r in ipairs(reports) do
    for _, w in ipairs(r.warnings) do problems[#problems + 1] = w end
  end

  local headline = {}
  for _, r in ipairs(reports) do
    local name = app.fs.fileTitle(r.sprite.filename)
    if name == "" then name = "sprite" end
    if r.appended then
      headline[#headline + 1] = ("%s: %s in %s appended from frame %d")
        :format(name, plural(r.frames, "frame"), plural(#r.tags, "tag"), r.firstFrame)
    else
      headline[#headline + 1] = ("%s: %s in %s")
        :format(name, plural(#r.tags, "tag"), plural(r.frames, "frame"))
    end
  end

  if #notes > 0 then
    headline[#headline + 1] =
      ("%s folded into sequences by Aseprite"):format(plural(#notes, "file"))
  end

  if #problems > 0 then
    local text = {}
    for _, h in ipairs(headline) do text[#text + 1] = h end
    text[#text + 1] = ""
    for i, n in ipairs(problems) do
      if i > 10 then
        text[#text + 1] = ("(+%d more)"):format(#problems - 10)
        break
      end
      text[#text + 1] = n
    end
    app.alert { title = "Animation Auto-Tagger", text = text }
  elseif app.tip then
    app.tip(table.concat(headline, "   "))
  end

  return true
end

--- Show the dialog. `opts` may carry:
--   entries  initial frame list
--   folder   folder those entries came from
--   cfg      starting configuration
--   onApply  called with the config the user built with (for persistence)
--   title    dialog title
function M.show(opts)
  opts = opts or {}
  local cfg = opts.cfg or config.new()
  local state = {
    raw       = opts.entries or {},
    entries   = opts.entries or {},
    recovered = 0,
    folder    = opts.folder or collect.commonFolder(opts.entries or {}),
  }

  -- Taken once, at open time: the dialog is modal, so the set of open sprites
  -- cannot change while it is up.
  local targetChoices = openSpriteChoices()
  local targetLabels = {}
  for _, c in ipairs(targetChoices) do targetLabels[#targetLabels + 1] = c.label end
  local activeLabel = targetLabels[1]
  for _, c in ipairs(targetChoices) do
    if app.sprite and c.sprite == app.sprite then activeLabel = c.label end
  end
  -- A combobox with no options at all renders as an empty box with nothing to
  -- explain it, so say what the emptiness means.
  if #targetChoices == 0 then
    targetLabels = { "(nothing open)" }
    activeLabel = targetLabels[1]
  end

  local dlg = Dialog { title = opts.title or "Build Tagged Animation" }

  local function regroup()
    local current = readConfig(dlg, cfg)
    local namingOpts = config.namingOpts(current)

    -- Recomputed every time so the recovery setting can be judged by its
    -- effect on the list rather than in the abstract.
    state.entries, state.recovered =
      collect.completeFromFolder(state.raw, current, namingOpts)

    local grouped = naming.group(state.entries, namingOpts)
    state.cfg, state.grouped = current, grouped

    local summary = M.summaryLine(grouped, current)
    if state.recovered > 0 then
      summary = summary .. (" (%d recovered from the folder)"):format(state.recovered)
    end
    dlg:modify { id = "summary", text = (#state.entries == 0)
      and "No files selected yet."
      or summary }

    local lines = M.previewLines(grouped, current)
    for i = 1, PREVIEW_ROWS do
      if i == PREVIEW_ROWS and #lines > PREVIEW_ROWS then
        dlg:modify { id = "row" .. i, text = ("(+%d more)"):format(#lines - PREVIEW_ROWS + 1),
                     visible = true }
      else
        dlg:modify { id = "row" .. i, text = lines[i] or "", visible = lines[i] ~= nil }
      end
    end

    dlg:modify { id = "build", enabled = #grouped.groups > 0 }
    dlg:modify { id = "splitByBase", enabled = #grouped.bases > 1 }
  end

  ----------------------------------------------------------------- source

  dlg:separator { text = "Frames" }

  dlg:label { id = "summary", label = "", text = "" }
  for i = 1, PREVIEW_ROWS do
    dlg:newrow()
    dlg:label { id = "row" .. i, label = "", text = "" }
  end

  dlg:newrow()
  -- A folder field built out of a file widget, because Aseprite has no folder
  -- picker: Dialog:file takes open/save only, and Dialog:folder() is still an
  -- open request (aseprite/aseprite#5399). `entry` is what makes it usable --
  -- a directory can be typed or pasted straight in, and the browse button is
  -- there for the times reaching for a file inside is easier.
  dlg:file {
    id = "pick",
    label = "Folder",
    title = "Open any file inside the folder to scan",
    open = true,
    entry = true,
    filename = state.folder,
    onchange = function()
      local chosen = dlg.data.pick
      if not chosen or chosen == "" then return end
      -- Two ways in, one target: browsing hands back a file, so fall back to
      -- its folder. The entry fires per keystroke, so a path still being typed
      -- has to be discarded rather than scanned as a half-written name.
      local folder = app.fs.isDirectory(chosen) and chosen or app.fs.filePath(chosen)
      if not app.fs.isDirectory(folder) then return end
      state.folder = folder
      state.raw = collect.fromFolder(folder)
      regroup()
    end,
  }

  dlg:newrow()
  dlg:combobox {
    id = "completeDrops", label = "Fill in from folder",
    option = cfg.completeDrops, options = config.COMPLETE_DROPS,
    onchange = regroup,
  }
  dlg:newrow()
  dlg:label {
    label = "",
    text = '"folder" adds every frame it finds; "gaps" only fills animations already here',
  }

  dlg:newrow()
  dlg:button {
    id = "useOpen",
    text = "Use open sprites",
    onclick = function()
      state.raw = collect.fromSprites(app.sprites)
      state.folder = collect.commonFolder(state.raw)
      regroup()
    end,
  }

  ----------------------------------------------------------------- naming

  dlg:separator { text = "Naming" }

  dlg:entry {
    id = "separator", label = "Separator", text = cfg.separator,
    onchange = regroup,
  }
  dlg:combobox {
    id = "animMode", label = "Animation name",
    option = labelFor(ANIM_MODES, cfg.animMode), options = labelsOf(ANIM_MODES),
    onchange = regroup,
  }
  dlg:combobox {
    id = "groupOrder", label = "Tag order",
    option = labelFor(GROUP_ORDERS, cfg.groupOrder), options = labelsOf(GROUP_ORDERS),
    onchange = regroup,
  }
  dlg:check {
    id = "allowGluedIndex", label = "Accept", text = "name01 (no separator before the number)",
    selected = cfg.allowGluedIndex, onclick = regroup,
  }
  dlg:newrow()
  dlg:check {
    id = "allowNoIndex", label = "", text = "files with no number as one-frame animations",
    selected = cfg.allowNoIndex, onclick = regroup,
  }
  dlg:newrow()
  dlg:check {
    id = "prefixTagWithBase", label = "", text = "prefix tags with the base name",
    selected = cfg.prefixTagWithBase, onclick = regroup,
  }
  dlg:entry {
    id = "customPattern", label = "Custom pattern", text = cfg.customPattern,
    onchange = regroup,
  }
  dlg:newrow()
  dlg:label {
    label = "", text = "Lua pattern with (anim)(index) or (base)(anim)(index); blank = off",
  }

  ------------------------------------------------------------------ build

  dlg:separator { text = "Result" }

  -- A stale preference naming an option that no longer exists would leave the
  -- combobox showing nothing at all.
  local startTarget = cfg.buildTarget
  if startTarget ~= "new sprite" and startTarget ~= "an open sprite" then
    startTarget = config.defaults.buildTarget
  end
  if #targetChoices == 0 then startTarget = "new sprite" end

  dlg:combobox {
    id = "buildTarget", label = "Build into",
    option = startTarget, options = config.BUILD_TARGETS,
  }
  dlg:combobox {
    id = "targetSprite", label = "",
    option = activeLabel, options = targetLabels,
    enabled = #targetChoices > 0,
  }
  dlg:newrow()
  dlg:label {
    label = "",
    text = "appending adds a layer and keeps that sprite's own canvas and color mode",
  }

  dlg:number {
    id = "frameDurationMs", label = "Frame duration (ms)",
    text = tostring(cfg.frameDurationMs), decimals = 0,
  }
  dlg:check {
    id = "keepSourceDurations", label = "", text = "keep durations from multi-frame sources",
    selected = cfg.keepSourceDurations,
  }
  dlg:combobox {
    id = "canvasMode", label = "Canvas size",
    option = labelFor(CANVAS_MODES, cfg.canvasMode), options = labelsOf(CANVAS_MODES),
    onchange = function()
      local custom = valueFor(CANVAS_MODES, dlg.data.canvasMode) == "custom"
      dlg:modify { id = "canvasWidth", enabled = custom }
      dlg:modify { id = "canvasHeight", enabled = custom }
    end,
  }
  dlg:number {
    id = "canvasWidth", label = "", text = tostring(cfg.canvasWidth), decimals = 0,
    enabled = cfg.canvasMode == "custom",
  }
  dlg:number {
    id = "canvasHeight", label = "x", text = tostring(cfg.canvasHeight), decimals = 0,
    enabled = cfg.canvasMode == "custom",
  }
  dlg:combobox {
    id = "align", label = "Align smaller frames",
    option = cfg.align, options = config.ALIGNMENTS,
  }
  dlg:combobox {
    id = "colorMode", label = "Color mode",
    option = cfg.colorMode, options = config.COLOR_MODES,
  }
  dlg:combobox {
    id = "aniDir", label = "Tag direction",
    option = cfg.aniDir, options = config.ANI_DIRS,
  }
  dlg:entry { id = "layerName", label = "Layer name", text = cfg.layerName }
  dlg:newrow()
  dlg:label { label = "", text = "blank = use the base name" }

  dlg:check {
    id = "expandMultiFrame", label = "Also", text = "expand multi-frame files into frames",
    selected = cfg.expandMultiFrame, onclick = regroup,
  }
  dlg:newrow()
  dlg:check {
    id = "splitByBase", label = "", text = "build one sprite per base name",
    selected = cfg.splitByBase,
  }
  dlg:newrow()
  dlg:check {
    id = "nameSpriteAfterBase", label = "", text = "name the new sprite after the base",
    selected = cfg.nameSpriteAfterBase,
  }
  dlg:newrow()
  dlg:check {
    id = "colorizeTags", label = "", text = "give each tag a color",
    selected = cfg.colorizeTags,
  }
  dlg:newrow()
  dlg:check {
    id = "closeSources", label = "", text = "close the source tabs afterwards",
    selected = cfg.closeSources,
  }

  ---------------------------------------------------------------- buttons

  dlg:separator {}
  dlg:button {
    id = "build", text = "Build", focus = true,
    onclick = function()
      local current = readConfig(dlg, cfg)
      if #state.entries == 0 then
        app.alert { title = "Animation Auto-Tagger", text = "Pick a folder first." }
        return
      end
      current.lastFolder = state.folder or ""
      if opts.onApply then opts.onApply(current) end
      dlg:close()
      M.run(state.entries, current, state.folder,
            spriteForLabel(targetChoices, current.targetLabel))
    end,
  }
  dlg:button { id = "cancel", text = "Cancel" }

  regroup()
  dlg:show { autoscrollbars = true }
  return dlg
end

return M
