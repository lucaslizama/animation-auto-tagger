--- Filename parsing and grouping for the Animation Auto-Tagger.
--
-- This module is deliberately free of Aseprite globals: it takes plain
-- strings and tables in, and returns plain tables. That keeps it runnable
-- under a stock `lua` interpreter, which is the only way to actually test
-- this logic without launching the editor (see tests/run_tests.lua).

local M = {}

-- How much of the file title counts as the animation name, given a title
-- like "hero_attack_heavy_00":
--   "middle" -> base "hero",        anim "attack_heavy"  (first token is the character)
--   "last"   -> base "hero_attack", anim "heavy"         (anim is a single token)
--   "whole"  -> base "",            anim "hero_attack_heavy"
M.ANIM_MODES = { "middle", "last", "whole" }

M.GROUP_ORDERS = { "alphabetical", "first-seen" }

M.defaults = {
  separator = "_",
  animMode = "middle",
  groupOrder = "alphabetical",
  -- Accept "run01" (digits glued to the name) as well as "run_01".
  allowGluedIndex = true,
  -- Accept "hero_idle" with no trailing number as a one-frame animation.
  allowNoIndex = true,
  -- Custom Lua pattern; when set it replaces the separator/mode logic.
  -- Must yield 2 captures (anim, index) or 3 captures (base, anim, index).
  customPattern = "",
  -- Tag name gets the base prepended, e.g. "hero_idle" instead of "idle".
  prefixTagWithBase = false,
}

local function escapePattern(s)
  return (s:gsub("(%W)", "%%%1"))
end

local function withDefaults(opts)
  local o = {}
  for k, v in pairs(M.defaults) do o[k] = v end
  for k, v in pairs(opts or {}) do
    if v ~= nil then o[k] = v end
  end
  if o.separator == "" then o.separator = "_" end
  return o
end
M.withDefaults = withDefaults

local function splitStem(stem, esep, mode)
  if mode == "whole" then
    return "", stem
  elseif mode == "last" then
    local base, anim = stem:match("^(.*)" .. esep .. "([^" .. esep .. "]+)$")
    if base then return base, anim end
    return "", stem
  else -- "middle"
    local base, anim = stem:match("^([^" .. esep .. "]+)" .. esep .. "(.+)$")
    if base then return base, anim end
    return "", stem
  end
end

--- Parse a bare file title (no directory, no extension).
-- Returns a table { ok, base, anim, index, indexText, title } — on failure
-- only { ok = false, title = title, reason = string }.
function M.parse(title, opts)
  local o = withDefaults(opts)

  if type(title) ~= "string" or title == "" then
    return { ok = false, title = tostring(title), reason = "empty name" }
  end

  if o.customPattern ~= "" then
    local a, b, c = title:match(o.customPattern)
    if a == nil then
      return { ok = false, title = title, reason = "custom pattern did not match" }
    end
    local base, anim, indexText
    if c ~= nil then base, anim, indexText = a, b, c
    else base, anim, indexText = "", a, b end
    local index = tonumber(indexText)
    if index == nil then
      return { ok = false, title = title, reason = "custom pattern index capture is not a number" }
    end
    return { ok = true, title = title, base = base, anim = anim,
             index = index, indexText = tostring(indexText) }
  end

  local esep = escapePattern(o.separator)

  -- Greedy stem match so "hero_run_2_00" keeps "2" in the stem and only the
  -- final numeric token becomes the frame index.
  local stem, indexText = title:match("^(.*)" .. esep .. "(%d+)$")

  if not stem and o.allowGluedIndex then
    local s, i = title:match("^(.-)(%d+)$")
    -- Only accept the glued form when something is left of the digits,
    -- otherwise "0001.png" would parse as an animation with an empty name.
    if s and s ~= "" then stem, indexText = s, i end
  end

  if not stem then
    if not o.allowNoIndex then
      return { ok = false, title = title, reason = "no frame index found" }
    end
    stem, indexText = title, nil
  end

  local base, anim = splitStem(stem, esep, o.animMode)
  if anim == nil or anim == "" then
    return { ok = false, title = title, reason = "no animation name found" }
  end

  return {
    ok = true,
    title = title,
    base = base,
    anim = anim,
    index = indexText and tonumber(indexText) or nil,
    indexText = indexText,
  }
end

--- The tag name an entry should end up with.
function M.tagName(parsed, opts)
  local o = withDefaults(opts)
  if o.prefixTagWithBase and parsed.base ~= "" then
    return parsed.base .. o.separator .. parsed.anim
  end
  return parsed.anim
end

--- Group a list of entries into animations.
--
-- `entries` is an array of tables that must carry a `title` field (the bare
-- file title). Every other field is passed through untouched, so callers can
-- hang a filename, a Sprite, a frame number, whatever they need off it.
--
-- Returns { groups = {...}, unmatched = {...}, bases = {...}, warnings = {...} }
-- where each group is { name, base, anim, items = { entry, ... } } and `items`
-- is sorted by frame index.
function M.group(entries, opts)
  local o = withDefaults(opts)
  local groups, order = {}, {}
  local unmatched, warnings = {}, {}
  local baseSet, bases = {}, {}

  for i, entry in ipairs(entries) do
    local parsed = M.parse(entry.title, o)
    if not parsed.ok then
      unmatched[#unmatched + 1] = { entry = entry, reason = parsed.reason }
    else
      local name = M.tagName(parsed, o)
      local g = groups[name]
      if not g then
        g = { name = name, base = parsed.base, anim = parsed.anim, items = {} }
        groups[name] = g
        order[#order + 1] = name
      elseif g.base ~= parsed.base then
        warnings[#warnings + 1] = ("tag %q mixes base names %q and %q")
          :format(name, g.base, parsed.base)
      end

      local item = {}
      for k, v in pairs(entry) do item[k] = v end
      item.parsed = parsed
      item.index = parsed.index
      item.seq = i
      g.items[#g.items + 1] = item

      if parsed.base ~= "" and not baseSet[parsed.base] then
        baseSet[parsed.base] = true
        bases[#bases + 1] = parsed.base
      end
    end
  end

  for _, name in ipairs(order) do
    local items = groups[name].items
    table.sort(items, function(a, b)
      local ai = a.index or -1
      local bi = b.index or -1
      if ai ~= bi then return ai < bi end
      if a.title ~= b.title then return a.title < b.title end
      return a.seq < b.seq
    end)
    -- Duplicated indices usually mean the naming scheme is off (or two
    -- variants of the same frame landed in the batch), so say so rather
    -- than silently picking an order.
    for i = 2, #items do
      if items[i].index ~= nil and items[i].index == items[i - 1].index then
        warnings[#warnings + 1] = ("tag %q has two frames with index %s (%s, %s)")
          :format(name, tostring(items[i].index), items[i - 1].title, items[i].title)
      end
    end
  end

  local ordered = {}
  for _, name in ipairs(order) do ordered[#ordered + 1] = groups[name] end
  if o.groupOrder == "alphabetical" then
    table.sort(ordered, function(a, b) return a.name < b.name end)
  end

  table.sort(bases)
  return { groups = ordered, unmatched = unmatched, bases = bases, warnings = warnings }
end

--- Split a group list into one bucket per base name, preserving group order.
-- Returns an array of { base = string, groups = { group, ... } }.
function M.splitByBase(groups)
  local buckets, order = {}, {}
  for _, g in ipairs(groups) do
    local b = g.base or ""
    if not buckets[b] then
      buckets[b] = { base = b, groups = {} }
      order[#order + 1] = b
    end
    local bucket = buckets[b]
    bucket.groups[#bucket.groups + 1] = g
  end
  table.sort(order)
  local out = {}
  for _, b in ipairs(order) do out[#out + 1] = buckets[b] end
  return out
end

--- Total frame count across groups.
function M.frameCount(groups)
  local n = 0
  for _, g in ipairs(groups) do n = n + #g.items end
  return n
end

return M
