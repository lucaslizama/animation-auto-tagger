--- Animation Auto-Tagger - plugin entry point.
--
-- Drop a character's frames into Aseprite (hero_run_00.png, hero_run_01.png,
-- hero_idle_00.png, ...) and get one sprite whose timeline holds every frame
-- in order, with a tag per animation - which is exactly what Godot's Aseprite
-- importers turn into animation clips.

local config  = require("config")
local collect = require("collect")
local naming  = require("naming")
local ui      = require("ui")
local watcher = require("watcher")

local state = {
  plugin = nil,
  cfg    = nil,
  watch  = nil,
}

local function saveConfig(cfg)
  state.cfg = cfg
  config.save(state.plugin, cfg)
end

local function openDialog(entries, folder, title, excluded)
  ui.show {
    entries  = entries,
    folder   = folder,
    cfg      = state.cfg,
    title    = title,
    excluded = excluded,
    onApply  = saveConfig,
  }
end

--------------------------------------------------------------- watcher glue

--- Called once a batch of newly opened sprites has settled.
local function onBatch(sprites)
  local cfg = state.cfg
  local dropped = collect.fromSprites(sprites)
  if #dropped == 0 then return end

  local namingOpts = config.namingOpts(cfg)

  -- Check the drop is worth acting on before going to disk for the rest of it.
  local seen = naming.group(dropped, namingOpts)
  if #seen.groups == 0 then return end

  local entries, recovered = collect.completeFromFolder(dropped, cfg, namingOpts)
  local grouped = naming.group(entries, namingOpts)
  local frames = ui.frameTotal(grouped, cfg)
  if #grouped.groups == 0 or frames < math.max(1, cfg.watchMinFiles) then
    return
  end

  local folder = collect.commonFolder(entries)

  if cfg.watchAutoBuild then
    ui.run(entries, cfg, folder)
    return
  end

  local text = {}
  if recovered > 0 then
    text[#text + 1] = ""
    text[#text + 1] = ("%d file%s arrived in the drop; %d more came from the same")
      :format(#dropped, #dropped == 1 and "" or "s", recovered)
    text[#text + 1] = "folder (Aseprite's drag-and-drop truncates long lists)."
  end

  -- A non-modal dialog rather than app.alert: a truncated drop puts Aseprite's
  -- own error window on screen first, and stacking a second modal on top of it
  -- leaves the user with two dialogs fighting for the same click. This one just
  -- sits alongside until they are ready.
  if state.watch then state.watch:hold() end

  local prompt
  prompt = Dialog {
    title = "Animation Auto-Tagger",
    onclose = function()
      if state.watch then state.watch:release() end
    end,
  }
  -- Built fresh for every drop, so there can be exactly one checkbox per
  -- animation -- no fixed row count to run out of.
  local excluded = {}
  prompt:label { label = "", text = ui.summaryLine(grouped, cfg) .. " ready to build:" }
  prompt:newrow()
  for i, line in ipairs(ui.groupLines(grouped, cfg)) do
    local name = grouped.groups[i].name
    prompt:check {
      id = "grp" .. i, label = "", text = line, selected = true,
      onclick = function() excluded[name] = not prompt.data["grp" .. i] end,
    }
    prompt:newrow()
  end
  for _, line in ipairs(ui.noteLines(grouped)) do
    prompt:label { label = "", text = line }
    prompt:newrow()
  end
  for _, line in ipairs(text) do
    prompt:label { label = "", text = line }
    prompt:newrow()
  end
  prompt:separator {}
  -- Each action runs before the dialog closes, so the sprite it creates already
  -- exists when the watcher resyncs in onclose and is not mistaken for a drop.
  prompt:button {
    text = "Build", focus = true,
    onclick = function()
      ui.run(entries, cfg, folder, nil, excluded)
      prompt:close()
    end,
  }
  prompt:button {
    text = "Options...",
    onclick = function()
      -- Carried across so ticking here and then opening Options does not
      -- quietly put everything back.
      openDialog(entries, folder, "Build Tagged Animation", excluded)
      prompt:close()
    end,
  }
  prompt:button { text = "Ignore", onclick = function() prompt:close() end }
  prompt:show { wait = false }
end

local function startWatcher()
  if not state.watch then return false end
  state.watch:start()
  return true
end

local function stopWatcher()
  if state.watch then state.watch:stop() end
end

------------------------------------------------------------------- settings

local function showSettings()
  local cfg = state.cfg
  local dlg = Dialog { title = "Animation Auto-Tagger Settings" }

  dlg:separator { text = "Watch for dropped files" }
  dlg:label {
    label = "",
    text = "Aseprite has no drag-and-drop hook for scripts, so this polls",
  }
  dlg:newrow()
  dlg:label { label = "", text = "the open sprite list and reacts once it stops growing." }

  dlg:check {
    id = "watchEnabled", label = "Watching", text = "enabled",
    selected = cfg.watchEnabled,
  }
  dlg:check {
    id = "watchAutoBuild", label = "", text = "build immediately instead of asking",
    selected = cfg.watchAutoBuild,
  }
  dlg:number {
    id = "watchIntervalMs", label = "Poll interval (ms)",
    text = tostring(cfg.watchIntervalMs), decimals = 0,
  }
  dlg:number {
    id = "watchQuietTicks", label = "Quiet ticks before acting",
    text = tostring(cfg.watchQuietTicks), decimals = 0,
  }
  dlg:number {
    id = "watchMinFiles", label = "Minimum matching frames",
    text = tostring(cfg.watchMinFiles), decimals = 0,
  }
  dlg:combobox {
    id = "completeDrops", label = "Recover truncated drops",
    option = cfg.completeDrops, options = config.COMPLETE_DROPS,
  }
  dlg:newrow()
  dlg:label { label = "", text = "folder = whole folder, gaps = only animations that arrived" }

  dlg:separator {}
  dlg:button {
    id = "ok", text = "OK", focus = true,
    onclick = function()
      local d = dlg.data
      local updated = {}
      for k, v in pairs(cfg) do updated[k] = v end
      updated.watchEnabled    = d.watchEnabled
      updated.watchAutoBuild  = d.watchAutoBuild
      updated.watchIntervalMs = math.max(50, math.floor(tonumber(d.watchIntervalMs) or 250))
      updated.watchQuietTicks = math.max(1, math.floor(tonumber(d.watchQuietTicks) or 3))
      updated.watchMinFiles   = math.max(1, math.floor(tonumber(d.watchMinFiles) or 2))
      updated.completeDrops   = d.completeDrops
      saveConfig(updated)
      dlg:close()

      stopWatcher()
      if updated.watchEnabled and not startWatcher() then
        app.alert {
          title = "Animation Auto-Tagger",
          text = { "This Aseprite build has no Timer class,",
                   "so watching for dropped files is not available.",
                   "Use File > Scripts > Animation Auto-Tagger instead." },
        }
      end
    end,
  }
  dlg:button { id = "cancel", text = "Cancel" }
  dlg:show()
end

--------------------------------------------------------------------- plugin

function init(plugin)
  state.plugin = plugin
  state.cfg = config.load(plugin)

  if Timer ~= nil then
    state.watch = watcher.new {
      getConfig = function() return state.cfg end,
      onBatch   = onBatch,
    }
  end

  plugin:newMenuGroup {
    id = "anim_auto_tagger",
    title = "Animation Auto-Tagger",
    group = "file_scripts",
  }

  plugin:newCommand {
    id = "AnimAutoTagFromOpen",
    title = "Tag Open Sprites...",
    group = "anim_auto_tagger",
    onclick = function()
      local entries = collect.fromSprites(app.sprites)
      openDialog(entries, collect.commonFolder(entries), "Tag Open Sprites")
    end,
  }

  plugin:newCommand {
    id = "AnimAutoTagFromFolder",
    title = "Tag Frames in a Folder...",
    group = "anim_auto_tagger",
    onclick = function()
      local entries = {}
      local folder = state.cfg.lastFolder
      if folder ~= "" and app.fs.isDirectory(folder) then
        entries = collect.fromFolder(folder)
      end
      openDialog(entries, folder, "Tag Frames in a Folder")
    end,
  }

  plugin:newMenuSeparator { group = "anim_auto_tagger" }

  plugin:newCommand {
    id = "AnimAutoTagWatch",
    title = "Watch for Dropped Frames",
    group = "anim_auto_tagger",
    onenabled = function() return Timer ~= nil end,
    onchecked = function() return state.cfg.watchEnabled end,
    onclick = function()
      local updated = {}
      for k, v in pairs(state.cfg) do updated[k] = v end
      updated.watchEnabled = not updated.watchEnabled
      saveConfig(updated)
      stopWatcher()
      if updated.watchEnabled then startWatcher() end
    end,
  }

  plugin:newCommand {
    id = "AnimAutoTagSettings",
    title = "Auto-Tagger Settings...",
    group = "anim_auto_tagger",
    onclick = showSettings,
  }

  if state.cfg.watchEnabled then startWatcher() end
end

function exit(plugin)
  stopWatcher()
  if state.cfg then config.save(plugin, state.cfg) end
end
