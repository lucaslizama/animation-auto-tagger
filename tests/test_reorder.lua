-- Tests for reorder.lua against the fake Aseprite API.
--   lua tests/test_reorder.lua

package.path = "./src/?.lua;./tests/?.lua;../src/?.lua;../tests/?.lua;" .. package.path

local fake = require("fake_aseprite").install()
local reorder = require("reorder")

local failures, checks = 0, 0
local function check(ok, msg)
  checks = checks + 1
  if not ok then failures = failures + 1; io.write("  FAIL: ", msg, "\n") end
end
local function eq(a, e, msg)
  check(a == e, ("%s (expected %s, got %s)"):format(msg, tostring(e), tostring(a)))
end

local suites = {}
local function suite(name, fn) suites[#suites + 1] = { name = name, fn = fn } end

--- A sprite whose tags are laid out as { name, from, to }, with every frame
--- carrying a mark so it can be told apart after it moves.
local function spriteWith(frameCount, tagSpecs, opts)
  opts = opts or {}
  fake.reset()
  local s = fake.newSprite(8, 8, fake.ColorMode.RGB,
    { filename = "/art/hero.aseprite", frameCount = frameCount })
  for _ = 2, (opts.layers or 1) do s:newLayer() end

  for f = 1, frameCount do
    s.frames[f].duration = f / 100.0
    for _, layer in ipairs(s.layers) do
      local img = Image(8, 8, fake.ColorMode.RGB)
      img.mark = layer.name .. ":" .. f
      s:newCel(layer, f, img, Point(f, f * 2))
    end
  end
  for _, t in ipairs(tagSpecs) do
    local tag = s:newTag(t[2], t[3])
    tag.name = t[1]
    if t[4] then tag.aniDir = t[4] end
  end
  return s
end

local function layout(sprite)
  local out = {}
  for _, t in ipairs(sprite.tags) do
    out[#out + 1] = ("%s %d-%d"):format(t.name, t.fromFrame.frameNumber, t.toFrame.frameNumber)
  end
  table.sort(out, function(a, b)
    return tonumber(a:match("(%d+)-")) < tonumber(b:match("(%d+)-"))
  end)
  return table.concat(out, "  ")
end

--- What each frame is carrying now, on the first layer.
local function marks(sprite)
  local out = {}
  for f = 1, #sprite.frames do
    local cel = sprite.layers[1]:cel(f)
    out[#out + 1] = cel and cel.image.mark or "-"
  end
  return table.concat(out, ",")
end

--- Tag indices in the order the names are given.
local function orderOf(sprite, names)
  local order = {}
  for _, name in ipairs(names) do
    for i, t in ipairs(sprite.tags) do
      if t.name == name then order[#order + 1] = i end
    end
  end
  return order
end

------------------------------------------------------------------- suites

suite("reorder: blocks move, and the tags follow them", function()
  local s = spriteWith(6, { { "aa", 1, 2 }, { "bb", 3, 4 }, { "cc", 5, 6 } })
  local report = reorder.apply(s, orderOf(s, { "cc", "aa", "bb" }))
  eq(report ~= nil, true, "applied")
  eq(layout(s), "cc 1-2  aa 3-4  bb 5-6", "tags in the order asked for")
  eq(marks(s), "Layer 1:5,Layer 1:6,Layer 1:1,Layer 1:2,Layer 1:3,Layer 1:4",
     "and the frames went with them")
end)

suite("reorder: blocks of different lengths still line up", function()
  local s = spriteWith(6, { { "aa", 1, 1 }, { "bb", 2, 4 }, { "cc", 5, 6 } })
  reorder.apply(s, orderOf(s, { "bb", "cc", "aa" }))
  eq(layout(s), "bb 1-3  cc 4-5  aa 6-6", "spans kept their lengths")
  eq(marks(s), "Layer 1:2,Layer 1:3,Layer 1:4,Layer 1:5,Layer 1:6,Layer 1:1",
     "frames follow their own tag")
end)

suite("reorder: every layer moves, not just the first", function()
  local s = spriteWith(4, { { "aa", 1, 2 }, { "bb", 3, 4 } }, { layers = 3 })
  reorder.apply(s, orderOf(s, { "bb", "aa" }))
  eq(#s.layers, 3, "still three layers")
  for _, layer in ipairs(s.layers) do
    eq(layer:cel(1).image.mark, layer.name .. ":3", layer.name .. " frame 1 came from frame 3")
    eq(layer:cel(3).image.mark, layer.name .. ":1", layer.name .. " frame 3 came from frame 1")
  end
end)

suite("reorder: frame durations travel with their frames", function()
  local s = spriteWith(4, { { "aa", 1, 2 }, { "bb", 3, 4 } })
  reorder.apply(s, orderOf(s, { "bb", "aa" }))
  eq(("%.2f"):format(s.frames[1].duration), "0.03", "frame 1 took frame 3's duration")
  eq(("%.2f"):format(s.frames[3].duration), "0.01", "frame 3 took frame 1's duration")
end)

suite("reorder: cel position and opacity are not lost in the move", function()
  local s = spriteWith(4, { { "aa", 1, 2 }, { "bb", 3, 4 } })
  s.layers[1]:cel(3).opacity = 128
  s.layers[1]:cel(3).data = "keep me"
  reorder.apply(s, orderOf(s, { "bb", "aa" }))
  local moved = s.layers[1]:cel(1)
  eq(moved.position.x, 3, "position x came along")
  eq(moved.position.y, 6, "position y came along")
  eq(moved.opacity, 128, "opacity came along")
  eq(moved.data, "keep me", "and the cel's own note")
end)

suite("reorder: the tag keeps its name, direction and identity", function()
  local s = spriteWith(4, { { "aa", 1, 2, "ping-pong" }, { "bb", 3, 4 } })
  local aa = s.tags[1]
  reorder.apply(s, orderOf(s, { "bb", "aa" }))
  eq(aa.name, "aa", "same tag object, same name")
  eq(aa.aniDir, "ping-pong", "direction untouched")
  eq(aa.fromFrame.frameNumber, 3, "moved to its new span")
end)

suite("reorder: untagged frames go to the end, in their own order", function()
  local s = spriteWith(6, { { "aa", 1, 2 }, { "bb", 4, 5 } })
  local report = reorder.apply(s, orderOf(s, { "bb", "aa" }))
  eq(layout(s), "bb 1-2  aa 3-4", "the two blocks came first")
  eq(marks(s), "Layer 1:4,Layer 1:5,Layer 1:1,Layer 1:2,Layer 1:3,Layer 1:6",
     "then frames 3 and 6, still in that order")
  eq(report.loose, 2, "reported how many were loose")
end)

suite("reorder: a tag left out of the order keeps its place after the rest", function()
  local s = spriteWith(6, { { "aa", 1, 2 }, { "bb", 3, 4 }, { "cc", 5, 6 } })
  reorder.apply(s, orderOf(s, { "cc" }))
  eq(layout(s), "cc 1-2  aa 3-4  bb 5-6", "cc moved up, the others held their order")
end)

suite("reorder: overlapping tags are refused", function()
  local s = spriteWith(6, { { "aa", 1, 4 }, { "bb", 3, 6 } })
  local report, err = reorder.apply(s, orderOf(s, { "bb", "aa" }))
  eq(report, nil, "nothing applied")
  eq(err ~= nil and err:find("share frames", 1, true) ~= nil, true, "and it says why")
  eq(marks(s), "Layer 1:1,Layer 1:2,Layer 1:3,Layer 1:4,Layer 1:5,Layer 1:6",
     "the sprite was left alone")
end)

suite("reorder: a sprite with one tag has nothing to reorder", function()
  local s = spriteWith(4, { { "aa", 1, 4 } })
  local report, err = reorder.apply(s, { 1 })
  eq(report, nil, "refused")
  eq(err:find("fewer than two tags", 1, true) ~= nil, true, "and says so plainly")
end)

suite("reorder: asking for the order it is already in changes nothing", function()
  local s = spriteWith(4, { { "aa", 1, 2 }, { "bb", 3, 4 } })
  local report = reorder.apply(s, orderOf(s, { "aa", "bb" }))
  eq(report.moved, 0, "reported as a no-op")
  eq(#fake.app.transactions, 0, "and no undo step was made for it")
end)

suite("reorder: linked cels are called out before they are broken", function()
  local s = spriteWith(4, { { "aa", 1, 2 }, { "bb", 3, 4 } })
  -- Two frames sharing one image is what Aseprite calls a linked cel.
  local shared = s.layers[1]:cel(1).image
  s.layers[1]:cel(3).image = shared
  local report = reorder.apply(s, orderOf(s, { "bb", "aa" }))
  local warned = false
  for _, w in ipairs(report.warnings) do
    if w:find("its own copy", 1, true) then warned = true end
  end
  eq(warned, true, "warned that the link will not survive")
end)

suite("reorder: the sequence is worked out before anything moves", function()
  local s = spriteWith(6, { { "aa", 1, 2 }, { "bb", 3, 4 }, { "cc", 5, 6 } })
  local seq, blocks, loose = reorder.sequence(s, orderOf(s, { "cc", "bb", "aa" }))
  eq(table.concat(seq, ","), "5,6,3,4,1,2", "frame order")
  eq(#blocks, 3, "three blocks")
  eq(blocks[1].tag.name, "cc", "cc leads")
  eq(loose, 0, "no loose frames")
  eq(marks(s), "Layer 1:1,Layer 1:2,Layer 1:3,Layer 1:4,Layer 1:5,Layer 1:6",
     "and asking did not move anything")
end)

suite("move: an entry can be taken out and put back anywhere", function()
  local start = { 1, 2, 3, 4, 5 }
  eq(table.concat(reorder.moveTo(start, 4, 1), ","), "4,1,2,3,5", "to the top")
  eq(table.concat(reorder.moveTo(start, 2, 5), ","), "1,3,4,5,2", "to the bottom")
  eq(table.concat(reorder.moveTo(start, 3, 2), ","), "1,3,2,4,5", "one place up")
  eq(table.concat(reorder.moveTo(start, 3, 4), ","), "1,2,4,3,5", "one place down")
  eq(table.concat(reorder.moveTo(start, 1, 1), ","), "1,2,3,4,5", "nowhere is a no-op")
  eq(table.concat(reorder.moveTo(start, 2, 99), ","), "1,3,4,5,2", "past the end clamps")
  eq(table.concat(reorder.moveTo(start, 4, -3), ","), "4,1,2,3,5", "before the start clamps")
  eq(table.concat(start, ","), "1,2,3,4,5", "and the list given is left alone")
end)

suite("sort: by name, by length, and back to the timeline", function()
  -- deliberately not in name order, and with two tags the same length
  local s = spriteWith(12, {
    { "run",  1, 6 },   -- 6 frames
    { "idle", 7, 8 },   -- 2
    { "jump", 9, 10 },  -- 2
    { "hurt", 11, 12 }, -- 2
  })
  local function names(order)
    local out = {}
    for _, i in ipairs(order) do out[#out + 1] = s.tags[i].name end
    return table.concat(out, ",")
  end
  local start = { 1, 2, 3, 4 }

  eq(names(reorder.sortOrder(s, start, "name-asc")), "hurt,idle,jump,run", "A to Z")
  eq(names(reorder.sortOrder(s, start, "name-desc")), "run,jump,idle,hurt", "Z to A")
  eq(names(reorder.sortOrder(s, start, "frames-desc")), "run,idle,jump,hurt", "longest first")
  eq(names(reorder.sortOrder(s, start, "frames-asc")), "idle,jump,hurt,run", "shortest first")
  eq(names(reorder.sortOrder(s, start, "timeline")), "run,idle,jump,hurt", "timeline order")
  eq(names(start), "run,idle,jump,hurt", "the order given is left alone")
end)

suite("sort: equal rows keep the order they were already in", function()
  local s = spriteWith(9, {
    { "aa", 1, 3 }, { "bb", 4, 6 }, { "cc", 7, 9 },   -- all 3 frames
  })
  local function names(order)
    local out = {}
    for _, i in ipairs(order) do out[#out + 1] = s.tags[i].name end
    return table.concat(out, ",")
  end
  -- shuffled by hand, then sorted by something they all share
  local shuffled = { 3, 1, 2 }
  eq(names(reorder.sortOrder(s, shuffled, "frames-asc")), "cc,aa,bb",
     "a tie leaves them as they were")
  -- and sorting again changes nothing, which is what makes the button safe to
  -- press twice
  local once = reorder.sortOrder(s, shuffled, "frames-asc")
  eq(names(reorder.sortOrder(s, once, "frames-asc")), "cc,aa,bb", "sorting twice is stable")
end)

suite("sort: every criterion the dialog offers is one the module knows", function()
  local s = spriteWith(4, { { "aa", 1, 2 }, { "bb", 3, 4 } })
  for _, how in ipairs(reorder.SORTS) do
    local out = reorder.sortOrder(s, { 1, 2 }, how)
    eq(#out, 2, how .. " returns every tag")
  end

  -- The dialog's list and the module's have to agree, or a criterion falls
  -- through to timeline order without saying so.
  local known = {}
  for _, how in ipairs(reorder.SORTS) do known[how] = true end
  local ui = require("ui")
  eq(#ui.TAG_SORTS, #reorder.SORTS, "the dialog offers as many as the module knows")
  for _, pair in ipairs(ui.TAG_SORTS) do
    eq(known[pair[2]] == true, true, ("the dialog's %q is a criterion the module knows")
      :format(pair[2]))
  end
end)

--------------------------------------------------------------------- run

for _, s in ipairs(suites) do
  local before = failures
  local ok, err = pcall(s.fn)
  if not ok then failures = failures + 1; io.write("  ERROR: ", tostring(err), "\n") end
  io.write((failures > before) and "[FAIL] " or "[ ok ] ", s.name, "\n")
end

io.write(("\n%d checks, %d failure(s)\n"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)
