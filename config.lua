--- Defaults and preference persistence for the Animation Auto-Tagger.
--
-- Every knob lives here rather than being sprinkled through the code, so the
-- dialog can render all of it and plugin.preferences can round-trip all of it.

local naming = require("naming")

local M = {}

M.ALIGNMENTS   = { "center", "top-left", "top-center", "bottom-left", "bottom-center" }
M.CANVAS_MODES = { "max", "first" }
M.COLOR_MODES  = { "rgb", "gray", "indexed", "same as first source" }
M.ANI_DIRS     = { "forward", "reverse", "ping-pong", "ping-pong-reverse" }
M.COMPLETE_DROPS = { "folder", "gaps", "off" }
M.BUILD_TARGETS  = { "new sprite", "an open sprite" }

M.defaults = {
  ---------------------------------------------------------------- naming
  separator         = naming.defaults.separator,
  animMode          = naming.defaults.animMode,
  groupOrder        = naming.defaults.groupOrder,
  allowGluedIndex   = naming.defaults.allowGluedIndex,
  allowNoIndex      = naming.defaults.allowNoIndex,
  customPattern     = naming.defaults.customPattern,
  prefixTagWithBase = naming.defaults.prefixTagWithBase,

  ----------------------------------------------------------------- build
  frameDurationMs   = 100,
  keepSourceDurations = false,
  buildTarget       = "new sprite",   -- or "an open sprite", to append instead
  canvasMode        = "max",
  align             = "center",
  colorMode         = "rgb",
  expandMultiFrame  = true,
  aniDir            = "forward",
  layerName         = "",     -- empty -> derived from the base name
  splitByBase       = false,
  closeSources      = true,
  nameSpriteAfterBase = true,
  colorizeTags      = true,

  --------------------------------------------------------------- watcher
  -- Aseprite exposes no drag-and-drop event, so the watcher polls the open
  -- sprite list on a Timer and reacts once the batch stops growing.
  watchEnabled      = false,
  watchIntervalMs   = 250,
  watchQuietTicks   = 3,
  watchMinFiles     = 2,
  watchAutoBuild    = false,  -- false -> open the dialog, true -> build straight away
  -- Aseprite's Linux drop handler truncates long file lists, so a drop of 20
  -- frames may deliver 10. Recover the rest from the folder they came from.
  completeDrops     = "folder",

  ----------------------------------------------------------------- misc
  lastFolder        = "",
}

-- Tag colours cycled through when colorizeTags is on. Aseprite shows these on
-- the timeline, which makes a long tag list far easier to scan.
M.TAG_COLORS = {
  { 131,  71, 173 },  -- purple
  {  60, 180, 229 },  -- cyan
  { 229, 129,  60 },  -- orange
  {  92, 184, 112 },  -- green
  { 214,  90, 122 },  -- pink
  { 214, 196,  84 },  -- yellow
}

function M.new()
  local cfg = {}
  for k, v in pairs(M.defaults) do cfg[k] = v end
  return cfg
end

--- Read preferences into a config table, ignoring anything stale or wrongly
-- typed (preferences survive plugin updates, defaults do not have to).
function M.load(plugin)
  local cfg = M.new()
  local prefs = plugin and plugin.preferences
  if not prefs then return cfg end
  for k, default in pairs(M.defaults) do
    local v = prefs[k]
    if v ~= nil and type(v) == type(default) then cfg[k] = v end
  end
  return cfg
end

function M.save(plugin, cfg)
  local prefs = plugin and plugin.preferences
  if not prefs then return end
  for k in pairs(M.defaults) do prefs[k] = cfg[k] end
end

--- The subset the naming module understands.
function M.namingOpts(cfg)
  return {
    separator         = cfg.separator,
    animMode          = cfg.animMode,
    groupOrder        = cfg.groupOrder,
    allowGluedIndex   = cfg.allowGluedIndex,
    allowNoIndex      = cfg.allowNoIndex,
    customPattern     = cfg.customPattern,
    prefixTagWithBase = cfg.prefixTagWithBase,
  }
end

return M
