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

--- The canvas the options ask for, before any target sprite has a say.
local function requestedCanvas(cfg, survey)
  if cfg.canvasMode == "custom" then
    return math.max(1, math.floor(cfg.canvasWidth or 1)),
           math.max(1, math.floor(cfg.canvasHeight or 1))
  elseif cfg.canvasMode == "first" and survey.first then
    return survey.first.width, survey.first.height
  end
  return survey.width, survey.height
end
M.requestedCanvas = requestedCanvas

--- Resize `sprite` to w x h, putting what is already there where `align` says.
--
-- CanvasSize takes the padding to add on each side -- negative to take it away
-- again -- and moves the existing cels along with it. That is the whole reason
-- to use it over assigning sprite.width, which would leave the art in the
-- corner of whatever the new canvas turned out to be.
local function resizeCanvas(sprite, w, h, align)
  local dw, dh = w - sprite.width, h - sprite.height
  if dw == 0 and dh == 0 then return false end

  -- offsetFor answers width and height independently, so handing it the
  -- smaller of each pair gives the edge to add on the left and top -- or, when
  -- shrinking, the edge to take off them.
  local ox, oy = offsetFor(align,
    math.max(w, sprite.width), math.max(h, sprite.height),
    math.min(w, sprite.width), math.min(h, sprite.height))
  local left = (dw >= 0) and ox or -ox
  local top  = (dh >= 0) and oy or -oy

  app.sprite = sprite
  app.command.CanvasSize {
    ui = false, left = left, top = top, right = dw - left, bottom = dh - top,
  }
  return true
end
M.resizeCanvas = resizeCanvas

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

--- Why `target` cannot take these groups, or nil when it can.
-- A sprite that is also a source would be read and written in the same pass,
-- feeding its own half-finished frames back into itself.
function M.targetConflict(groups, target)
  for _, group in ipairs(groups) do
    for _, ref in ipairs(group.refs) do
      -- Image-backed refs hold no document, so they can never be the target.
      if ref.sprite and ref.sprite.id == target.id then
        local name = (target.filename ~= "" and app.fs.fileTitle(target.filename)) or "the target sprite"
        return ("%s is one of the frames being added to it; pick a different sprite under \"Build into\"")
          :format(name)
      end
    end
  end
  return nil
end

local function layerNamed(sprite, name)
  for _, l in ipairs(sprite.layers) do
    if l.name == name then return l end
  end
end

local function tagNamed(sprite, name)
  for _, t in ipairs(sprite.tags) do
    if t.name == name then return t end
  end
end

--- Build one sprite from a list of groups.
--
-- `groups` must already carry `refs` (see sources.expand). Returns a report:
--   { sprite, frames, tags = {{name, from, to}}, warnings = {} }
--
-- `opts.target` appends to that sprite instead of creating one. Appending
-- borrows the target's canvas and colour mode wholesale rather than deriving
-- them from the sources: both already belong to art the user made, and
-- resizing or requantizing to suit incoming frames would rewrite it.
function M.build(groups, cfg, opts)
  opts = opts or {}
  assert(#groups > 0, "nothing to build")
  local pool = opts.pool or sources.newPool()
  local target = opts.target

  local warnings = {}
  local survey = sources.survey(groups)

  if target then
    local err = M.targetConflict(groups, target)
    if err then return nil, err end
  end

  local canvasW, canvasH = requestedCanvas(cfg, survey)
  if target then
    local smaller = canvasW < target.width or canvasH < target.height
    if cfg.canvasMode ~= "custom" then
      -- max and first are read off the sources, so they are a floor rather
      -- than a request: a target bigger than they ask for simply stays put.
      canvasW = math.max(canvasW, target.width)
      canvasH = math.max(canvasH, target.height)
    elseif smaller and not opts.allowShrink then
      -- A typed size is an instruction, but one that crops art the user
      -- already had needs asking about first -- which is the caller's job
      -- (see ui.run), because only it can put a question on screen.
      warnings[#warnings + 1] = ("a %dx%d canvas would crop the sprite being appended to; kept %dx%d")
        :format(canvasW, canvasH, math.max(canvasW, target.width),
                math.max(canvasH, target.height))
      canvasW = math.max(canvasW, target.width)
      canvasH = math.max(canvasH, target.height)
    end
  end
  if canvasW < 1 or canvasH < 1 then
    return nil, "source frames have no size"
  end

  local targetMode, buildMode, keepIndices
  if target then
    targetMode = sources.modeName(target.colorMode)
    if not COLOR_MODE_ENUM[targetMode] then
      return nil, ("the sprite being appended to is in %s mode, which takes no frames")
        :format(targetMode)
    end
    buildMode, keepIndices = targetMode, false
    if targetMode == "indexed" then
      -- Each source is quantized against a palette of its own (see
      -- sources.asColorMode), so the indices it produces mean something else
      -- once they land under the target's palette.
      warnings[#warnings + 1] =
        "the sprite being appended to is indexed; incoming colours are matched per source, not to its palette, so they can shift"
    end
  else
    targetMode, buildMode, keepIndices = resolveModes(cfg, survey)
  end
  local buildEnum = COLOR_MODE_ENUM[buildMode]()

  -- Convert sprite sources up front so drawSprite never has to cross color
  -- modes. Image sources are left alone: drawImage converts as it draws, which
  -- is the whole reason a still frame needs no document of its own.
  for _, group in ipairs(groups) do
    for _, ref in ipairs(group.refs) do
      if not ref.image then
        local converted, err = sources.asColorMode(pool, ref.sprite, buildMode)
        if converted then
          ref.sprite = converted
        else
          warnings[#warnings + 1] = err
        end
      end
    end
  end

  -- `frameBase` is how many frames were already there: 0 for a new sprite, so
  -- the append and build paths share every index below.
  local layerName = (cfg.layerName ~= "" and cfg.layerName)
                 or (opts.baseName ~= "" and opts.baseName)
                 or "Animation"

  -- Replacing reuses a layer of that name when the sprite already has one, so
  -- importing the same character a second time refreshes it rather than
  -- stacking another copy on top.
  local replacing = target ~= nil and cfg.existingTags == "replace"

  local dest, frameBase, layer
  if target then
    dest, frameBase = target, #target.frames
    if replacing then layer = layerNamed(dest, layerName) end
    -- Never dest.layers[1] by default -- that one holds the user's own art.
    layer = layer or dest:newLayer()
  else
    dest, frameBase = Sprite(canvasW, canvasH, buildEnum), 0
    if keepIndices and survey.palette then
      dest:setPalette(survey.palette)
      if survey.first then dest.transparentColor = survey.first.transparentColor end
    end
    layer = dest.layers[1]
  end
  layer.name = layerName

  local total, tags, replacedCount = 0, {}, 0
  for _, group in ipairs(groups) do total = total + #group.refs end

  local aniDir = (ANI_DIRS[cfg.aniDir] or ANI_DIRS["forward"])()
  local duration = math.max(1, cfg.frameDurationMs) / 1000.0

  -- Aseprite lets two tags share a name, and the second one is then all but
  -- impossible to tell apart on the timeline. Worth saying so.
  local taken = {}
  if target and not replacing then
    for _, t in ipairs(target.tags) do taken[t.name] = true end
  end

  local resized, wasW, wasH = false, target and target.width, target and target.height

  --- Draw one source frame onto `layer` at `frameNumber`.
  local function placeRef(frameNumber, ref)
    local src = ref.image or ref.sprite
    local img = Image(src.width, src.height, buildEnum)
    if ref.image then
      -- Always into a fresh image, never the cached one: the same file can
      -- appear in two groups, and a cel must not share pixels with another.
      img:drawImage(ref.image, Point(0, 0))
    else
      img:drawSprite(src, ref.frame)
    end

    local dx, dy = offsetFor(cfg.align, canvasW, canvasH, src.width, src.height)
    if src.width > canvasW or src.height > canvasH then
      warnings[#warnings + 1] = ("%s is %dx%d, larger than the %dx%d canvas; it will be cropped")
        :format(ref.item.title, src.width, src.height, canvasW, canvasH)
    end

    local existing = layer:cel(frameNumber)
    if existing then dest:deleteCel(existing) end
    dest:newCel(layer, frameNumber, img, Point(dx, dy))

    local frame = dest.frames[frameNumber]
    if cfg.keepSourceDurations and ref.sprite then
      frame.duration = src.frames[ref.frame].duration
    else
      -- A still frame carries no timing of its own to keep.
      frame.duration = duration
    end
  end

  --- Tag ranges as they stand, and putting them back afterwards.
  --
  -- Inserting a frame just past a tag's last frame makes that tag swallow it,
  -- so a sprite tagged 1-3 would come to own everything appended below. Frames
  -- added at the very end must move no existing tag at all.
  local function heldRanges()
    local held = {}
    for _, t in ipairs(dest.tags) do
      held[#held + 1] = { tag = t, from = t.fromFrame.frameNumber, to = t.toFrame.frameNumber }
    end
    return held
  end
  local function restoreRanges(held)
    for _, h in ipairs(held) do
      h.tag.fromFrame = dest.frames[h.from]
      h.tag.toFrame   = dest.frames[h.to]
    end
  end

  --- Put a group at the end of the timeline under a tag of its own.
  local function appendGroup(group)
    local start = #dest.frames + 1
    local held = heldRanges()
    for _ = 1, #group.refs do dest:newEmptyFrame(#dest.frames + 1) end
    restoreRanges(held)

    for i, ref in ipairs(group.refs) do placeRef(start + i - 1, ref) end

    if taken[group.name] then
      warnings[#warnings + 1] =
        ("the target sprite already has a tag named %s; there are now two")
          :format(group.name)
    end

    local tag = dest:newTag(start, start + #group.refs - 1)
    tag.name = group.name
    tag.aniDir = aniDir
    if cfg.colorizeTags then
      local c = config.TAG_COLORS[((#tags) % #config.TAG_COLORS) + 1]
      tag.color = Color { r = c[1], g = c[2], b = c[3] }
    end
    tags[#tags + 1] = { name = group.name, from = start,
                        to = start + #group.refs - 1, count = #group.refs }
  end

  --- Refresh the frames an existing tag already spans.
  --
  -- The tag itself is left alone -- its name, direction and colour are the
  -- user's -- and only the frames under it change. Aseprite moves every tag
  -- after this one as frames are inserted or deleted, so nothing downstream
  -- has to be fixed up by hand.
  local function replaceGroup(group, tag)
    local from = tag.fromFrame.frameNumber
    local have = tag.toFrame.frameNumber - from + 1
    local want = #group.refs

    for _ = 1, want - have do
      dest:newEmptyFrame(tag.toFrame.frameNumber + 1)
    end
    for _ = 1, have - want do
      dest:deleteFrame(tag.toFrame.frameNumber)
    end
    if want < have then
      warnings[#warnings + 1] =
        ("%s went from %d frames to %d; the %d removed took any other layer's cels with them")
          :format(group.name, have, want, have - want)
    end

    for i, ref in ipairs(group.refs) do placeRef(from + i - 1, ref) end

    replacedCount = replacedCount + 1
    tags[#tags + 1] = { name = group.name, from = from, to = from + want - 1,
                        count = want, replaced = true }
  end

  app.transaction(target and "Append tagged animation" or "Build tagged animation", function()
    if target then
      -- Before any cel is placed, so offsetFor works against the final size.
      if resizeCanvas(dest, canvasW, canvasH, cfg.align) then
        resized = true
      end

      for _, group in ipairs(groups) do
        local tag = replacing and tagNamed(dest, group.name) or nil
        if tag then replaceGroup(group, tag) else appendGroup(group) end
      end
      return
    end

    for i = 2, total do dest:newEmptyFrame(i) end

    local frameIndex = 0
    for _, group in ipairs(groups) do
      local from = frameIndex + 1
      for _, ref in ipairs(group.refs) do
        frameIndex = frameIndex + 1
        placeRef(frameIndex, ref)
      end

      local tag = dest:newTag(from, frameIndex)
      tag.name = group.name
      tag.aniDir = aniDir
      if cfg.colorizeTags then
        local c = config.TAG_COLORS[((#tags) % #config.TAG_COLORS) + 1]
        tag.color = Color { r = c[1], g = c[2], b = c[3] }
      end
      tags[#tags + 1] = { name = group.name, from = from, to = frameIndex,
                          count = #group.refs }
    end
  end)

  if resized then
    if canvasW >= wasW and canvasH >= wasH then
      warnings[#warnings + 1] = ("the canvas grew from %dx%d to %dx%d to fit the new frames")
        :format(wasW, wasH, canvasW, canvasH)
    else
      warnings[#warnings + 1] = ("the canvas went from %dx%d to %dx%d; anything outside it was cropped")
        :format(wasW, wasH, canvasW, canvasH)
    end
  end

  -- Both of these rewrite the sprite as a whole, which is fine for one this
  -- function just made and never acceptable for one the user already had.
  if not target and targetMode ~= buildMode then
    app.sprite = dest
    local ok, err = pcall(function()
      app.command.ChangePixelFormat { ui = false, format = targetMode }
    end)
    if not ok then
      warnings[#warnings + 1] = ("could not convert the result to %s (%s)")
        :format(targetMode, tostring(err))
    end
  end

  if not target and cfg.nameSpriteAfterBase and opts.baseName and opts.baseName ~= "" then
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
    appended = target ~= nil,
    replaced = replacedCount,
    firstFrame = frameBase + 1,
  }
end

--- Build one or more sprites from a grouping result, honouring splitByBase.
-- Returns the reports, a list of error strings, and a list of informational
-- notes (see sources.expand).
--
-- `opts.target` appends everything to that one sprite, which is what makes
-- splitByBase meaningless here: it asks for N sprites and there is only one.
function M.buildAll(grouped, cfg, opts)
  opts = opts or {}
  local pool = opts.pool or sources.newPool()
  local reports, errors = {}, {}

  local groups, expandErrors, notes = sources.expand(pool, grouped.groups, cfg)
  for _, e in ipairs(expandErrors) do errors[#errors + 1] = e end
  if #groups == 0 then
    return reports, errors, notes
  end

  local target = opts.target
  local buckets
  if cfg.splitByBase and not target then
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
      target = target,
      allowShrink = opts.allowShrink,
    })
    if report then
      reports[#reports + 1] = report
    else
      errors[#errors + 1] = tostring(err)
    end
  end

  if cfg.splitByBase and target and reports[1] then
    table.insert(reports[1].warnings, 1,
      "one sprite per base name cannot apply when appending; everything went into the one sprite")
  end

  return reports, errors, notes
end

return M
