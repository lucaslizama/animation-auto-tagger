--- Turning grouped filenames into concrete (sprite, frame) pairs.
--
-- Two kinds of source item arrive here:
--   * { path = "/…/hero_run_00.png" }  -- from the folder picker, must be opened
--   * { sprite = <Sprite> }            -- already open, e.g. dropped into the editor
-- Sprites opened by this module are tracked so they can be closed again; the
-- user's own tabs are never closed unless they asked for it.

local M = {}

-- Formats that can genuinely hold more than one frame. Everything else is a
-- still image and must be loaded with oneFrame=true, because Aseprite otherwise
-- detects a numbered file sequence -- hero_run_00.png, _01, _02, ... -- and
-- loads the whole run as frames of a single sprite. That is exactly the naming
-- this plugin is built around, so without this the frame count multiplies.
M.ANIMATED_EXTENSIONS = {
  gif = true, aseprite = true, ase = true, webp = true,
  flc = true, fli = true, flh = true,
}

function M.holdsAnimation(path)
  if not path or path == "" then return false end
  return M.ANIMATED_EXTENSIONS[app.fs.fileExtension(path):lower()] == true
end

function M.newPool()
  return {
    byPath   = {},   -- path -> sprite
    ours     = {},   -- sprite id -> true, sprites this pool opened
    temps    = {},   -- sprites created as throwaway conversions
    converted = {},  -- "<sprite id>:<mode>" -> sprite, so one source converts once
    external = {},   -- sprite id -> sprite, sprites that were already open
    order    = {},   -- opened sprites, in open order, for deterministic cleanup
  }
end

local function remember(pool, sprite, isOurs)
  if isOurs then
    pool.ours[sprite.id] = true
    pool.order[#pool.order + 1] = sprite
  else
    pool.external[sprite.id] = sprite
  end
end

--- Load (or reuse) the sprite backing an item. Returns sprite, err.
function M.spriteFor(pool, item, cfg)
  if item.sprite then
    remember(pool, item.sprite, false)
    return item.sprite
  end
  if not item.path then
    return nil, ("%s: nothing to load"):format(tostring(item.title))
  end

  local cached = pool.byPath[item.path]
  if cached then return cached end

  local multiFrame = cfg.expandMultiFrame and M.holdsAnimation(item.path)
  local ok, result = pcall(function()
    return Sprite { fromFile = item.path, oneFrame = not multiFrame }
  end)
  if not ok or not result then
    return nil, ("%s: could not be opened%s")
      :format(item.title, ok and "" or (" (" .. tostring(result) .. ")"))
  end

  pool.byPath[item.path] = result
  remember(pool, result, true)
  return result
end

local function modeName(colorMode)
  if colorMode == ColorMode.RGB then return "rgb"
  elseif colorMode == ColorMode.GRAY then return "gray"
  elseif colorMode == ColorMode.INDEXED then return "indexed"
  else return "other" end
end
M.modeName = modeName

--- Convert a source sprite to `targetMode` ("rgb"/"gray"/"indexed").
--
-- Sprites the pool opened itself are converted in place (they are discarded
-- afterwards anyway). Sprites the user already had open are duplicated first,
-- so their undo history and tab stay untouched.
function M.asColorMode(pool, sprite, targetMode)
  if modeName(sprite.colorMode) == targetMode then return sprite end

  -- A multi-frame source is referenced once per frame; without this cache each
  -- reference would duplicate and convert the same sprite all over again.
  local cacheKey = sprite.id .. ":" .. targetMode
  local cached = pool.converted[cacheKey]
  if cached then return cached end

  local target = sprite
  if not pool.ours[sprite.id] then
    local ok, dup = pcall(function() return Sprite(sprite) end)
    if not ok or not dup then
      return nil, ("%s: could not be duplicated for color conversion")
        :format(app.fs.fileTitle(sprite.filename))
    end
    target = dup
    pool.temps[#pool.temps + 1] = dup
  end

  app.sprite = target
  local ok, err = pcall(function()
    app.command.ChangePixelFormat { ui = false, format = targetMode }
  end)
  if not ok then
    return nil, ("%s: color conversion failed (%s)")
      :format(app.fs.fileTitle(sprite.filename), tostring(err))
  end
  pool.converted[cacheKey] = target
  return target
end

--- Expand groups into frame references.
--
-- Each group gains a `refs` array of { sprite = <Sprite>, frame = <number>,
-- item = <item> }. A source holding several frames contributes one ref per
-- frame when expandMultiFrame is on.
--
-- The wrinkle is Aseprite's sequence detection. Files this module opens itself
-- are loaded one frame at a time (see spriteFor), but a sprite the user already
-- had open may well be the whole run: dragging twenty frames in gives five
-- sprites, not twenty, because Aseprite folded each numbered sequence into one.
-- Those frames are real and must be kept -- so the expansion below takes them,
-- and then skips any sibling file the sequence has already swallowed.
--
-- Returns `out, errors, notes`. Errors are things that went wrong; notes are
-- expected-but-worth-knowing, like a sibling skipped because its sequence
-- already covered it. Groups with no usable frames are dropped.
function M.expand(pool, groups, cfg)
  local errors, notes = {}, {}
  local out = {}

  for _, group in ipairs(groups) do
    local refs = {}
    local coveredUpTo = nil   -- last frame index consumed by an expanded sequence

    for _, item in ipairs(group.items) do
      local sprite, err = M.spriteFor(pool, item, cfg)
      if not sprite then
        errors[#errors + 1] = err
      elseif coveredUpTo and item.index and item.index <= coveredUpTo then
        notes[#notes + 1] = ("%s was already part of a sequence Aseprite had loaded")
          :format(item.title)
      else
        local last = cfg.expandMultiFrame and #sprite.frames or 1
        for f = 1, last do
          refs[#refs + 1] = { sprite = sprite, frame = f, item = item }
        end
        if last > 1 and item.index then
          coveredUpTo = item.index + last - 1
        end
      end
    end

    if #refs > 0 then
      group.refs = refs
      out[#out + 1] = group
    else
      errors[#errors + 1] = ("tag %q has no usable frames"):format(group.name)
    end
  end

  return out, errors, notes
end

--- How many frames an entry will contribute, without opening anything.
-- Used by the dialog preview, where a sprite Aseprite loaded as a sequence
-- should be shown as its real frame count rather than as one file.
function M.frameCountOf(item, cfg)
  if item.sprite and item.sprite.isValid and cfg.expandMultiFrame then
    return #item.sprite.frames
  end
  return 1
end

local function palettesMatch(a, b)
  if a == nil or b == nil then return false end
  if #a ~= #b then return false end
  for i = 0, #a - 1 do
    if a:getColor(i).rgbaPixel ~= b:getColor(i).rgbaPixel then return false end
  end
  return true
end
M.palettesMatch = palettesMatch

--- Inspect the sprites behind a set of groups: the color modes present, the
-- largest frame size, and whether every source shares one indexed palette.
function M.survey(groups)
  local seen, modes = {}, {}
  local width, height = 0, 0
  local first, allIndexed, sharedPalette = nil, true, nil

  for _, group in ipairs(groups) do
    for _, ref in ipairs(group.refs) do
      local s = ref.sprite
      if s.width > width then width = s.width end
      if s.height > height then height = s.height end
      if not seen[s.id] then
        seen[s.id] = true
        first = first or s
        local m = modeName(s.colorMode)
        modes[m] = (modes[m] or 0) + 1
        if m ~= "indexed" then
          allIndexed = false
        elseif allIndexed then
          local pal = s.palettes[1]
          if sharedPalette == nil then
            sharedPalette = pal
          elseif not palettesMatch(sharedPalette, pal) then
            sharedPalette = false
          end
        end
      end
    end
  end

  return {
    first = first,
    modes = modes,
    width = width,
    height = height,
    uniformIndexed = allIndexed and sharedPalette ~= nil and sharedPalette ~= false,
    palette = (sharedPalette ~= false) and sharedPalette or nil,
  }
end

--- Close everything this pool is responsible for.
function M.release(pool, cfg)
  for _, s in ipairs(pool.temps) do
    pcall(function() s:close() end)
  end
  pool.temps = {}

  for _, s in ipairs(pool.order) do
    pcall(function() s:close() end)
  end
  pool.order, pool.byPath, pool.ours, pool.converted = {}, {}, {}, {}

  if cfg and cfg.closeSources then
    for _, s in pairs(pool.external) do
      -- Never close something the user has unsaved work in.
      pcall(function()
        if s.isValid and not s.isModified then s:close() end
      end)
    end
  end
  pool.external = {}
end

return M
