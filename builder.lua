--- Assembling a tagged sprite out of grouped source frames.

local config = require("config")
local sources = require("sources")

local M = {}

local ANI_DIRS = {
  ["forward"]            = function() return AniDir.FORWARD end,
  ["reverse"]            = function() return AniDir.REVERSE end,
  ["ping-pong"]          = function() return AniDir.PING_PONG end,
  ["ping-pong-reverse"]  = function() return AniDir.PING_PONG_REVERSE end,
}

local COLOR_MODE_ENUM = {
  rgb     = function() return ColorMode.RGB end,
  gray    = function() return ColorMode.GRAY end,
  indexed = function() return ColorMode.INDEXED end,
}

local function offsetFor(align, cw, ch, w, h)
  local dx, dy = 0, 0
  if align == "top-left" then
    dx, dy = 0, 0
  elseif align == "top-center" then
    dx, dy = (cw - w) // 2, 0
  elseif align == "bottom-left" then
    dx, dy = 0, ch - h
  elseif align == "bottom-center" then
    dx, dy = (cw - w) // 2, ch - h
  else -- center
    dx, dy = (cw - w) // 2, (ch - h) // 2
  end
  return dx, dy
end
M.offsetFor = offsetFor

--- Resolve the color mode the finished sprite should have.
-- Returns targetMode ("rgb"/"gray"/"indexed"), buildMode (the mode used while
-- compositing) and whether the indexed fast path applies.
local function resolveModes(cfg, survey)
  local target = cfg.colorMode
  if target == "same as first source" then
    target = survey.first and sources.modeName(survey.first.colorMode) or "rgb"
    if target == "other" then target = "rgb" end
  end

  -- When every source is indexed against one identical palette we can composite
  -- directly in indexed and keep the exact palette indices. Any other route
  -- would requantize and shuffle them.
  if target == "indexed" and survey.uniformIndexed then
    return target, "indexed", true
  end
  return target, "rgb", false
end
M.resolveModes = resolveModes

--- Build one sprite from a list of groups.
--
-- `groups` must already carry `refs` (see sources.expand). Returns a report:
--   { sprite, frames, tags = {{name, from, to}}, warnings = {} }
function M.build(groups, cfg, opts)
  opts = opts or {}
  assert(#groups > 0, "nothing to build")
  local pool = opts.pool or sources.newPool()

  local warnings = {}
  local survey = sources.survey(groups)

  local canvasW, canvasH
  if cfg.canvasMode == "first" and survey.first then
    canvasW, canvasH = survey.first.width, survey.first.height
  else
    canvasW, canvasH = survey.width, survey.height
  end
  if canvasW < 1 or canvasH < 1 then
    return nil, "source frames have no size"
  end

  local targetMode, buildMode, keepIndices = resolveModes(cfg, survey)
  local buildEnum = COLOR_MODE_ENUM[buildMode]()

  -- Convert sources up front so drawSprite never has to cross color modes.
  for _, group in ipairs(groups) do
    for _, ref in ipairs(group.refs) do
      local converted, err = sources.asColorMode(pool, ref.sprite, buildMode)
      if converted then
        ref.sprite = converted
      else
        warnings[#warnings + 1] = err
      end
    end
  end

  local dest = Sprite(canvasW, canvasH, buildEnum)
  if keepIndices and survey.palette then
    dest:setPalette(survey.palette)
    if survey.first then dest.transparentColor = survey.first.transparentColor end
  end

  local layer = dest.layers[1]
  layer.name = (cfg.layerName ~= "" and cfg.layerName)
            or (opts.baseName ~= "" and opts.baseName)
            or "Animation"

  local total, tags = 0, {}
  for _, group in ipairs(groups) do total = total + #group.refs end

  local aniDir = (ANI_DIRS[cfg.aniDir] or ANI_DIRS["forward"])()
  local duration = math.max(1, cfg.frameDurationMs) / 1000.0

  app.transaction("Build tagged animation", function()
    for i = 2, total do dest:newEmptyFrame(i) end

    local frameIndex = 0
    for _, group in ipairs(groups) do
      local from = frameIndex + 1
      for _, ref in ipairs(group.refs) do
        frameIndex = frameIndex + 1

        local src = ref.sprite
        local img = Image(src.width, src.height, buildEnum)
        img:drawSprite(src, ref.frame)

        local dx, dy = offsetFor(cfg.align, canvasW, canvasH, src.width, src.height)
        if src.width > canvasW or src.height > canvasH then
          warnings[#warnings + 1] = ("%s is %dx%d, larger than the %dx%d canvas; it will be cropped")
            :format(ref.item.title, src.width, src.height, canvasW, canvasH)
        end

        local existing = layer:cel(frameIndex)
        if existing then dest:deleteCel(existing) end
        dest:newCel(layer, frameIndex, img, Point(dx, dy))

        local frame = dest.frames[frameIndex]
        if cfg.keepSourceDurations then
          frame.duration = src.frames[ref.frame].duration
        else
          frame.duration = duration
        end
      end

      local tag = dest:newTag(from, frameIndex)
      tag.name = group.name
      tag.aniDir = aniDir
      if cfg.colorizeTags then
        local c = config.TAG_COLORS[((#tags) % #config.TAG_COLORS) + 1]
        tag.color = Color { r = c[1], g = c[2], b = c[3] }
      end
      tags[#tags + 1] = { name = group.name, from = from, to = frameIndex, count = #group.refs }
    end
  end)

  if targetMode ~= buildMode then
    app.sprite = dest
    local ok, err = pcall(function()
      app.command.ChangePixelFormat { ui = false, format = targetMode }
    end)
    if not ok then
      warnings[#warnings + 1] = ("could not convert the result to %s (%s)")
        :format(targetMode, tostring(err))
    end
  end

  if cfg.nameSpriteAfterBase and opts.baseName and opts.baseName ~= "" then
    local dir = opts.folder or ""
    local name = opts.baseName .. ".aseprite"
    dest.filename = (dir ~= "") and app.fs.joinPath(dir, name) or name
  end

  return {
    sprite   = dest,
    frames   = total,
    tags     = tags,
    warnings = warnings,
    canvas   = { width = canvasW, height = canvasH },
    colorMode = targetMode,
  }
end

--- Build one or more sprites from a grouping result, honouring splitByBase.
-- Returns the reports, a list of error strings, and a list of informational
-- notes (see sources.expand).
function M.buildAll(grouped, cfg, opts)
  opts = opts or {}
  local pool = opts.pool or sources.newPool()
  local reports, errors = {}, {}

  local groups, expandErrors, notes = sources.expand(pool, grouped.groups, cfg)
  for _, e in ipairs(expandErrors) do errors[#errors + 1] = e end
  if #groups == 0 then
    return reports, errors, notes
  end

  local buckets
  if cfg.splitByBase then
    local naming = require("naming")
    buckets = naming.splitByBase(groups)
  else
    local base = (#grouped.bases == 1) and grouped.bases[1] or ""
    buckets = { { base = base, groups = groups } }
  end

  for _, bucket in ipairs(buckets) do
    local report, err = M.build(bucket.groups, cfg, {
      pool = pool,
      baseName = bucket.base,
      folder = opts.folder,
    })
    if report then
      reports[#reports + 1] = report
    else
      errors[#errors + 1] = tostring(err)
    end
  end

  return reports, errors, notes
end

return M
