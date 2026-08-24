-- Tests for builder.lua / sources.lua against the fake Aseprite API.
--   lua tests/test_builder.lua

package.path = "./?.lua;./tests/?.lua;../?.lua;../tests/?.lua;" .. package.path

local fake = require("fake_aseprite").install()
local naming  = require("naming")
local config  = require("config")
local sources = require("sources")
local builder = require("builder")

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

--- Register fake files and return the entries the grouping stage expects.
local function withFiles(specs)
  fake.reset()
  local entries = {}
  for _, spec in ipairs(specs) do
    local path = "/art/" .. spec[1] .. ".png"
    fake.files[path] = {
      width = spec[2] or 16, height = spec[3] or 16,
      colorMode = spec.colorMode or fake.ColorMode.RGB,
      frameCount = spec.frameCount or 1,
      paletteColors = spec.paletteColors,
    }
    entries[#entries + 1] = { title = spec[1], path = path }
  end
  return entries
end

local function buildFrom(specs, overrides)
  local entries = withFiles(specs)
  local cfg = config.new()
  for k, v in pairs(overrides or {}) do cfg[k] = v end
  local grouped = naming.group(entries, config.namingOpts(cfg))
  local pool = sources.newPool()
  local reports, errors = builder.buildAll(grouped, cfg, { pool = pool, folder = "/art" })
  return reports, errors, grouped, pool, cfg
end

------------------------------------------------------------------- suites

suite("build: frames laid out in tag order", function()
  local reports, errors = buildFrom {
    { "hero_run_00" }, { "hero_run_01" }, { "hero_run_02" },
    { "hero_idle_00" }, { "hero_idle_01" },
  }
  eq(#errors, 0, "no errors")
  eq(#reports, 1, "one sprite")
  local r = reports[1]
  eq(r.frames, 5, "five frames")
  eq(#r.sprite.frames, 5, "sprite has five frames")
  eq(#r.tags, 2, "two tags")
  -- alphabetical group order puts idle first
  eq(r.tags[1].name, "idle", "first tag")
  eq(r.tags[1].from .. "-" .. r.tags[1].to, "1-2", "idle range")
  eq(r.tags[2].name, "run", "second tag")
  eq(r.tags[2].from .. "-" .. r.tags[2].to, "3-5", "run range")
  eq(r.sprite.tags[2].name, "run", "tag applied to the sprite")
  eq(r.sprite.tags[2].fromFrame .. "-" .. r.sprite.tags[2].toFrame, "3-5", "sprite tag range")
end)

suite("build: every frame gets exactly one cel drawn from its source", function()
  local reports = buildFrom { { "hero_run_00" }, { "hero_run_01" } }
  local layer = reports[1].sprite.layers[1]
  for f = 1, 2 do
    local cel = layer:cel(f)
    check(cel ~= nil, "cel exists at frame " .. f)
    eq(#cel.image.drawn, 1, "one drawSprite call for frame " .. f)
    eq(cel.image.drawn[1].frame, 1, "drew source frame 1")
  end
  eq(layer:cel(1).image.drawn[1].sprite.filename, "/art/hero_run_00.png", "frame 1 source")
  eq(layer:cel(2).image.drawn[1].sprite.filename, "/art/hero_run_01.png", "frame 2 source")
end)

suite("build: canvas is the largest source and smaller frames are aligned", function()
  local reports = buildFrom({
    { "hero_idle_00", 16, 16 }, { "hero_idle_01", 32, 24 },
  }, { align = "center" })
  local r = reports[1]
  eq(r.canvas.width .. "x" .. r.canvas.height, "32x24", "canvas takes the max")
  local layer = r.sprite.layers[1]
  eq(layer:cel(1).position.x .. "," .. layer:cel(1).position.y, "8,4", "16x16 centred in 32x24")
  eq(layer:cel(2).position.x .. "," .. layer:cel(2).position.y, "0,0", "32x24 sits at the origin")
end)

suite("build: alignment options", function()
  eq(select(1, builder.offsetFor("top-left", 32, 32, 16, 8)) .. ","
     .. select(2, builder.offsetFor("top-left", 32, 32, 16, 8)), "0,0", "top-left")
  local x, y = builder.offsetFor("bottom-center", 32, 32, 16, 8)
  eq(x .. "," .. y, "8,24", "bottom-center")
  x, y = builder.offsetFor("bottom-left", 32, 32, 16, 8)
  eq(x .. "," .. y, "0,24", "bottom-left")
  x, y = builder.offsetFor("top-center", 32, 32, 16, 8)
  eq(x .. "," .. y, "8,0", "top-center")
end)

suite("build: canvasMode=first pins the canvas and warns about oversized frames", function()
  local reports = buildFrom({
    { "hero_idle_00", 16, 16 }, { "hero_idle_01", 32, 32 },
  }, { canvasMode = "first" })
  local r = reports[1]
  eq(r.canvas.width, 16, "canvas from the first source")
  check(#r.warnings >= 1, "warns that a frame is bigger than the canvas")
end)

suite("build: frame duration", function()
  local reports = buildFrom({ { "hero_run_00" }, { "hero_run_01" } }, { frameDurationMs = 80 })
  eq(reports[1].sprite.frames[1].duration, 0.08, "80ms becomes 0.08s")
  eq(reports[1].sprite.frames[2].duration, 0.08, "applied to every frame")
end)

suite("build: multi-frame sources expand into one frame each", function()
  fake.reset()
  local path = "/art/hero_run_00.gif"
  fake.files[path] = { width = 16, height = 16, colorMode = fake.ColorMode.RGB, frameCount = 4 }
  local cfg = config.new()
  local grouped = naming.group({ { title = "hero_run_00", path = path } }, config.namingOpts(cfg))
  local reports = builder.buildAll(grouped, cfg, { pool = sources.newPool() })
  eq(reports[1].frames, 4, "four frames from a four-frame file")
  eq(reports[1].tags[1].to, 4, "the tag spans all of them")
  local layer = reports[1].sprite.layers[1]
  eq(layer:cel(3).image.drawn[1].frame, 3, "source frame 3 drawn into destination frame 3")

  cfg.expandMultiFrame = false
  local single = builder.buildAll(grouped, cfg, { pool = sources.newPool() })
  eq(single[1].frames, 1, "expansion off keeps only the first frame")
end)

suite("build: still images load as one frame, not as a numbered sequence", function()
  -- Aseprite opens hero_run_00.png and helpfully pulls _01.._05 in with it.
  -- That is exactly the naming this plugin uses, so every file would contribute
  -- the whole run and the frame count would balloon.
  fake.reset()
  local titles = {}
  for i = 0, 5 do
    local title = ("hero_run_%02d"):format(i)
    fake.files["/art/" .. title .. ".png"] =
      { width = 16, height = 16, sequence = 6 - i }
    titles[#titles + 1] = { title = title, path = "/art/" .. title .. ".png" }
  end
  local cfg = config.new()
  local grouped = naming.group(titles, config.namingOpts(cfg))
  local pool = sources.newPool()
  local reports = builder.buildAll(grouped, cfg, { pool = pool })
  eq(reports[1].frames, 6, "six files, six frames")
  for _, s in ipairs(pool.order) do
    check(s.loadedOneFrame, s.filename .. " was loaded with oneFrame=true")
  end
end)

suite("build: an open sprite Aseprite loaded as a sequence keeps all its frames", function()
  -- Dragging six frames in gives ONE sprite holding all six, not six sprites.
  -- Treating it as a single frame would silently drop five of them.
  fake.reset()
  local cfg = config.new()
  local spr = fake.newSprite(16, 16, fake.ColorMode.RGB,
                             { filename = "/art/hero_run_00.png", frameCount = 6 })
  local grouped = naming.group({ { title = "hero_run_00", sprite = spr } },
                               config.namingOpts(cfg))
  local reports = builder.buildAll(grouped, cfg, { pool = sources.newPool() })
  eq(reports[1].frames, 6, "all six frames kept")
  eq(reports[1].tags[1].to, 6, "and the tag spans them")
end)

suite("build: a sibling already swallowed by a sequence is skipped, not counted twice", function()
  fake.reset()
  local cfg = config.new()
  local whole = fake.newSprite(16, 16, fake.ColorMode.RGB,
                               { filename = "/art/hero_run_00.png", frameCount = 6 })
  local overlap = fake.newSprite(16, 16, fake.ColorMode.RGB,
                                 { filename = "/art/hero_run_03.png", frameCount = 3 })
  local grouped = naming.group({
    { title = "hero_run_00", sprite = whole },
    { title = "hero_run_03", sprite = overlap },
  }, config.namingOpts(cfg))
  local reports, errors, notes = builder.buildAll(grouped, cfg, { pool = sources.newPool() })
  eq(reports[1].frames, 6, "six frames, not nine")
  eq(#errors, 0, "an expected skip is not an error")
  eq(#notes, 1, "it is reported as a note")
  check(notes[1]:find("hero_run_03", 1, true) ~= nil, "naming the skipped file")
end)

suite("build: a following animation is not mistaken for an overlap", function()
  fake.reset()
  local cfg = config.new()
  local run = fake.newSprite(16, 16, fake.ColorMode.RGB,
                             { filename = "/art/hero_run_00.png", frameCount = 6 })
  local idle = fake.newSprite(16, 16, fake.ColorMode.RGB,
                              { filename = "/art/hero_idle_00.png", frameCount = 4 })
  local grouped = naming.group({
    { title = "hero_run_00", sprite = run },
    { title = "hero_idle_00", sprite = idle },
  }, config.namingOpts(cfg))
  local reports, errors, notes = builder.buildAll(grouped, cfg, { pool = sources.newPool() })
  eq(#errors, 0, "no errors")
  eq(#notes, 0, "coverage is tracked per tag, not across tags")
  eq(reports[1].frames, 10, "ten frames in total")
end)

suite("build: splitByBase produces one sprite per character", function()
  local reports, errors = buildFrom({
    { "hero_run_00" }, { "hero_idle_00" }, { "orc_run_00" },
  }, { splitByBase = true, prefixTagWithBase = true })
  eq(#errors, 0, "no errors")
  eq(#reports, 2, "two sprites")
  eq(reports[1].sprite.filename, "/art/hero.aseprite", "named after the base")
  eq(reports[1].frames, 2, "hero has both of its animations")
  eq(reports[2].sprite.filename, "/art/orc.aseprite", "second base")
  eq(reports[2].frames, 1, "orc has one frame")
  eq(reports[1].sprite.layers[1].name, "hero", "layer named after the base")
end)

suite("build: indexed sources are converted to rgb by default", function()
  local reports = buildFrom({
    { "hero_run_00", colorMode = fake.ColorMode.INDEXED, paletteColors = { 1, 2, 3 } },
  })
  eq(reports[1].colorMode, "rgb", "result is rgb")
  local converted = false
  for _, c in ipairs(fake.app.commands) do
    if c.name == "ChangePixelFormat" and c.params.format == "rgb" then converted = true end
  end
  check(converted, "the source was converted before compositing")
end)

suite("build: a uniform indexed palette is preserved without requantizing", function()
  local reports = buildFrom({
    { "hero_run_00", colorMode = fake.ColorMode.INDEXED, paletteColors = { 1, 2, 3 } },
    { "hero_run_01", colorMode = fake.ColorMode.INDEXED, paletteColors = { 1, 2, 3 } },
  }, { colorMode = "indexed" })
  eq(reports[1].colorMode, "indexed", "result is indexed")
  eq(#fake.app.commands, 0, "no ChangePixelFormat round trip was needed")
  eq(#reports[1].sprite.palettes[1], 3, "the shared palette was copied over")
end)

suite("build: mismatched indexed palettes fall back to the rgb route", function()
  local reports = buildFrom({
    { "hero_run_00", colorMode = fake.ColorMode.INDEXED, paletteColors = { 1, 2, 3 } },
    { "hero_run_01", colorMode = fake.ColorMode.INDEXED, paletteColors = { 9, 9, 9 } },
  }, { colorMode = "indexed" })
  eq(reports[1].colorMode, "indexed", "still ends up indexed")
  local final = fake.app.commands[#fake.app.commands]
  eq(final.name, "ChangePixelFormat", "converted at the end instead")
  eq(final.params.format, "indexed", "to indexed")
end)

suite("build: a multi-frame source is only converted once", function()
  fake.reset()
  local path = "/art/hero_run_00.gif"
  fake.files[path] = { width = 16, height = 16, colorMode = fake.ColorMode.INDEXED,
                       frameCount = 5, paletteColors = { 1, 2 } }
  local cfg = config.new()   -- rgb target, so all five frames need conversion
  local grouped = naming.group({ { title = "hero_run_00", path = path } },
                               config.namingOpts(cfg))
  local reports = builder.buildAll(grouped, cfg, { pool = sources.newPool() })
  eq(reports[1].frames, 5, "five frames")
  local conversions = 0
  for _, c in ipairs(fake.app.commands) do
    if c.name == "ChangePixelFormat" then conversions = conversions + 1 end
  end
  eq(conversions, 1, "converted once, not once per frame")
end)

suite("build: an already-open source is duplicated rather than converted in place", function()
  fake.reset()
  local cfg = config.new()
  local userSprite = fake.newSprite(16, 16, fake.ColorMode.INDEXED,
                                    { filename = "/art/hero_run_00.aseprite", frameCount = 3 })
  local grouped = naming.group({ { title = "hero_run_00", sprite = userSprite } },
                               config.namingOpts(cfg))
  local pool = sources.newPool()
  local reports = builder.buildAll(grouped, cfg, { pool = pool })
  eq(reports[1].frames, 3, "three frames")
  eq(userSprite.colorMode, fake.ColorMode.INDEXED, "the user's sprite kept its color mode")
  eq(#pool.temps, 1, "exactly one throwaway duplicate")
  local dup = pool.temps[1]
  sources.release(pool, cfg)
  check(dup.closed, "the duplicate was cleaned up")
end)

suite("build: colorMode 'same as first source'", function()
  local reports = buildFrom({
    { "hero_run_00", colorMode = fake.ColorMode.GRAY },
  }, { colorMode = "same as first source" })
  eq(reports[1].colorMode, "gray", "follows the source")
end)

suite("sources: pool closes what it opened and leaves user tabs alone", function()
  local reports, errors, grouped, pool, cfg = buildFrom { { "hero_run_00" }, { "hero_run_01" } }
  local opened = {}
  for _, s in ipairs(pool.order) do opened[#opened + 1] = s end
  eq(#opened, 2, "two sprites were opened")

  local userSprite = fake.newSprite(16, 16, fake.ColorMode.RGB, { filename = "/art/hero_run_02.png" })
  sources.spriteFor(pool, { title = "hero_run_02", sprite = userSprite }, cfg)
  cfg.closeSources = false
  sources.release(pool, cfg)
  for _, s in ipairs(opened) do check(s.closed, "opened sprite was closed") end
  check(not userSprite.closed, "the user's own sprite stayed open")
end)

suite("sources: closeSources only closes unmodified user tabs", function()
  local cfg = config.new()
  cfg.closeSources = true
  local pool = sources.newPool()
  local clean = fake.newSprite(16, 16, fake.ColorMode.RGB, { filename = "/art/a.png" })
  local dirty = fake.newSprite(16, 16, fake.ColorMode.RGB, { filename = "/art/b.png" })
  dirty.isModified = true
  sources.spriteFor(pool, { title = "a", sprite = clean }, cfg)
  sources.spriteFor(pool, { title = "b", sprite = dirty }, cfg)
  sources.release(pool, cfg)
  check(clean.closed, "unmodified tab closed")
  check(not dirty.closed, "modified tab kept")
end)

suite("build: unreadable files are reported, the rest still build", function()
  fake.reset()
  fake.files["/art/hero_run_00.png"] = { width = 16, height = 16 }
  local cfg = config.new()
  local grouped = naming.group({
    { title = "hero_run_00", path = "/art/hero_run_00.png" },
    { title = "hero_run_01", path = "/art/missing.png" },
  }, config.namingOpts(cfg))
  local reports, errors = builder.buildAll(grouped, cfg, { pool = sources.newPool() })
  eq(#reports, 1, "still produced a sprite")
  eq(reports[1].frames, 1, "with the readable frame only")
  eq(#errors, 1, "and reported the bad one")
  check(errors[1]:find("hero_run_01", 1, true) ~= nil, "error names the file")
end)

--- Sets up a folder of 20 frames and "drops" only the first `n` of them,
-- the way Aseprite's truncated X11 drop does.
local function truncatedDrop(n)
  fake.reset()
  local names, files = {}, {}
  for _, spec in ipairs({ {"attack",5}, {"hurt",2}, {"idle",4}, {"jump",3}, {"run",6} }) do
    for i = 0, spec[2] - 1 do
      local title = ("hero_%s_%02d"):format(spec[1], i)
      names[#names + 1] = title
      files[#files + 1] = title .. ".png"
      fake.files["/art/" .. title .. ".png"] = { width = 16, height = 16 }
    end
  end
  table.sort(names)
  table.sort(files)
  fake.dirs["/art"] = files

  local dropped = {}
  for i = 1, n do
    local title = names[i]
    dropped[#dropped + 1] = {
      title = title,
      path = "/art/" .. title .. ".png",
      sprite = fake.newSprite(16, 16, fake.ColorMode.RGB,
                              { filename = "/art/" .. title .. ".png" }),
    }
  end
  return dropped
end

suite("collect: a truncated drop is completed from its folder", function()
  local collect = require("collect")
  local dropped = truncatedDrop(9)
  local cfg = config.new()
  local merged, added = collect.completeFromFolder(dropped, cfg, config.namingOpts(cfg))
  eq(#dropped, 9, "nine files survived the drop")
  eq(added, 11, "eleven recovered from the folder")
  eq(#merged, 20, "twenty in total")
  local withSprites = 0
  for _, e in ipairs(merged) do if e.sprite then withSprites = withSprites + 1 end end
  eq(withSprites, 9, "the ones already open are reused, not reopened")
end)

suite("collect: gaps mode only completes animations that arrived", function()
  local collect = require("collect")
  local dropped = truncatedDrop(9)   -- attack 00-04, hurt 00-01, idle 00-01
  local cfg = config.new()
  cfg.completeDrops = "gaps"
  local merged, added = collect.completeFromFolder(dropped, cfg, config.namingOpts(cfg))
  eq(added, 2, "only the two missing idle frames")
  local anims = {}
  for _, e in ipairs(merged) do anims[e.title:match("^hero_(%a+)_")] = true end
  check(anims.jump == nil, "jump never arrived, so it is not pulled in")
  check(anims.run == nil, "nor run")
end)

suite("collect: off mode leaves the drop alone", function()
  local collect = require("collect")
  local dropped = truncatedDrop(9)
  local cfg = config.new()
  cfg.completeDrops = "off"
  local merged, added = collect.completeFromFolder(dropped, cfg, config.namingOpts(cfg))
  eq(added, 0, "nothing added")
  eq(#merged, 9, "nine entries")
end)

suite("collect: files spread across folders are not completed", function()
  local collect = require("collect")
  fake.reset()
  local cfg = config.new()
  local dropped = {
    { title = "hero_run_00", path = "/a/hero_run_00.png" },
    { title = "hero_run_01", path = "/b/hero_run_01.png" },
  }
  local _, added = collect.completeFromFolder(dropped, cfg, config.namingOpts(cfg))
  eq(added, 0, "no single folder to complete from")
end)

suite("build: a truncated drop still produces the whole character", function()
  local collect = require("collect")
  local dropped = truncatedDrop(9)
  local cfg = config.new()
  cfg.closeSources = false
  local merged = collect.completeFromFolder(dropped, cfg, config.namingOpts(cfg))
  local grouped = naming.group(merged, config.namingOpts(cfg))
  local reports, errors = builder.buildAll(grouped, cfg, { pool = sources.newPool() })
  eq(#errors, 0, "no errors")
  eq(reports[1].frames, 20, "all 20 frames")
  eq(#reports[1].tags, 5, "all 5 tags")
  eq(reports[1].tags[5].name .. " " .. reports[1].tags[5].from .. "-" .. reports[1].tags[5].to,
     "run 15-20", "and run is intact even though none of it survived the drop")
end)

suite("collect: only image files in the folder become entries", function()
  fake.reset()
  fake.dirs["/art"] = { "hero_run_00.png", "hero_run_01.png", "notes.txt", "sheet.aseprite" }
  local collect = require("collect")
  local entries = collect.fromFolder("/art")
  eq(#entries, 3, "txt skipped, png and aseprite kept")
  eq(entries[1].title, "hero_run_00", "titles have no extension")
  eq(entries[1].path, "/art/hero_run_00.png", "full path kept")
  eq(collect.fromFolder("/nope")[1], nil, "a missing folder yields nothing")
end)

suite("collect: open sprites without a filename are skipped", function()
  fake.reset()
  local collect = require("collect")
  local named = fake.newSprite(16, 16, fake.ColorMode.RGB, { filename = "/art/hero_run_00.png" })
  fake.newSprite(16, 16, fake.ColorMode.RGB)
  local entries = collect.fromSprites(fake.app.sprites)
  eq(#entries, 1, "only the saved one")
  eq(entries[1].sprite, named, "carries the sprite itself")
  eq(collect.commonFolder(entries), "/art", "common folder")
end)

suite("build: everything wrapped in a single transaction per sprite", function()
  fake.reset()
  buildFrom { { "hero_run_00" }, { "hero_idle_00" } }
  eq(#fake.app.transactions, 1, "one transaction")
  eq(fake.app.transactions[1], "Build tagged animation", "named for the undo history")
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
