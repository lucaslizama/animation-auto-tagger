--- Rearranging the tag blocks on a sprite that already exists.
--
-- Aseprite has no command for moving frames, so this works by lifting every
-- cel off the timeline, then writing them all back in the order asked for and
-- re-pointing the tags at their new spans. The frames themselves are never
-- created or deleted, only their contents move, which is why tags elsewhere in
-- the sprite do not shift underneath the operation.

local M = {}

--- The tags of `sprite` as { tag, from, to }, in timeline order.
local function ranges(sprite)
  local out = {}
  for i, tag in ipairs(sprite.tags) do
    out[#out + 1] = {
      tag = tag, index = i,
      from = tag.fromFrame.frameNumber,
      to = tag.toFrame.frameNumber,
    }
  end
  table.sort(out, function(a, b) return a.from < b.from end)
  return out
end

--- Why `sprite` cannot have its tags reordered, or nil when it can.
function M.conflict(sprite)
  if #sprite.tags < 2 then
    return "there is nothing to reorder: the sprite has fewer than two tags"
  end

  -- Blocks that share frames have no order to put them in: whichever went
  -- first would carry the other's frames along with it.
  local sorted = ranges(sprite)
  for i = 2, #sorted do
    local prev, cur = sorted[i - 1], sorted[i]
    if cur.from <= prev.to then
      return ("%s and %s share frames; tags have to be separate blocks to be reordered")
        :format(prev.tag.name, cur.tag.name)
    end
  end
  return nil
end

--- The frame order that applying `order` would produce.
--
-- `order` is a list of indices into sprite.tags. Tags left out of it keep
-- their place after the ones listed, and frames belonging to no tag at all go
-- on the end, in the order they were already in.
--
-- Returns the sequence of old frame numbers, and the tag blocks it implies as
-- { tag, length }.
function M.sequence(sprite, order)
  local byIndex = {}
  for _, r in ipairs(ranges(sprite)) do byIndex[r.index] = r end

  local taken, blocks = {}, {}
  for _, index in ipairs(order or {}) do
    local r = byIndex[index]
    if r and not taken[index] then
      taken[index] = true
      blocks[#blocks + 1] = r
    end
  end
  -- Anything the caller did not mention keeps its original relative place.
  for _, r in ipairs(ranges(sprite)) do
    if not taken[r.index] then
      taken[r.index] = true
      blocks[#blocks + 1] = r
    end
  end

  local seq, claimed = {}, {}
  for _, r in ipairs(blocks) do
    for f = r.from, r.to do
      seq[#seq + 1] = f
      claimed[f] = true
    end
  end

  local loose = 0
  for f = 1, #sprite.frames do
    if not claimed[f] then
      seq[#seq + 1] = f
      loose = loose + 1
    end
  end

  return seq, blocks, loose
end

--- Lift every cel off the timeline, so the frames can be written back in any
-- order without a half-moved frame being read as a source.
local function snapshot(sprite)
  local snap = {}
  for f = 1, #sprite.frames do
    local frame = { duration = sprite.frames[f].duration, cels = {} }
    for li, layer in ipairs(sprite.layers) do
      local cel = layer:cel(f)
      if cel then
        frame.cels[li] = {
          image = Image(cel.image),
          x = cel.position.x, y = cel.position.y,
          opacity = cel.opacity, zIndex = cel.zIndex, data = cel.data,
        }
      end
    end
    snap[f] = frame
  end
  return snap
end

--- Put `sprite`'s tag blocks in `order`, an array of indices into sprite.tags.
--
-- Returns a report, or nil and a reason.
function M.apply(sprite, order)
  local err = M.conflict(sprite)
  if err then return nil, err end

  local seq, blocks, loose = M.sequence(sprite, order)

  local unchanged = true
  for newIndex, oldIndex in ipairs(seq) do
    if newIndex ~= oldIndex then unchanged = false; break end
  end
  if unchanged then
    return { moved = 0, loose = loose, warnings = {}, order = blocks }
  end

  local warnings = {}
  local linked = M.linkedCels(sprite)
  if linked > 0 then
    warnings[#warnings + 1] =
      ("%d cel%s shared an image with another frame; moving them makes each one its own copy")
        :format(linked, linked == 1 and "" or "s")
  end

  app.transaction("Reorder tags", function()
    local snap = snapshot(sprite)

    for newIndex, oldIndex in ipairs(seq) do
      sprite.frames[newIndex].duration = snap[oldIndex].duration
      for li, layer in ipairs(sprite.layers) do
        local existing = layer:cel(newIndex)
        if existing then sprite:deleteCel(existing) end
        local src = snap[oldIndex].cels[li]
        if src then
          local cel = sprite:newCel(layer, newIndex, src.image, Point(src.x, src.y))
          cel.opacity = src.opacity
          cel.zIndex = src.zIndex
          cel.data = src.data
        end
      end
    end

    -- The tags never moved, only what sits under them, so each one is simply
    -- re-pointed at the span its block now occupies.
    local at = 1
    for _, block in ipairs(blocks) do
      local len = block.to - block.from + 1
      block.tag.fromFrame = sprite.frames[at]
      block.tag.toFrame = sprite.frames[at + len - 1]
      at = at + len
    end
  end)

  return { moved = #seq, loose = loose, warnings = warnings, order = blocks }
end

--- How many cels share their image with another frame.
--
-- Aseprite links cels that were never edited apart, and writing them back one
-- at a time breaks the link. The result looks identical and takes more room,
-- which is worth saying out loud rather than leaving to be noticed later.
function M.linkedCels(sprite)
  local seen, linked = {}, 0
  for _, layer in ipairs(sprite.layers) do
    for f = 1, #sprite.frames do
      local cel = layer:cel(f)
      if cel then
        local id = cel.image.id
        if id then
          if seen[id] then linked = linked + 1 else seen[id] = true end
        end
      end
    end
  end
  return linked
end

return M
