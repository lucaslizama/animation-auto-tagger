-- Tests for builder.lua / sources.lua against the fake Aseprite API.
--   lua tests/test_builder.lua

package.path = "./src/?.lua;./tests/?.lua;../src/?.lua;../tests/?.lua;" .. package.path

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

--- Build into an existing sprite. `target` describes the sprite appended to.
local function appendFrom(specs, overrides, target, buildOpts)
  target = target or {}
  buildOpts = buildOpts or {}
  local entries = withFiles(specs)   -- resets the fake, so the target comes after
  local dest = fake.newSprite(target.width or 16, target.height or 16,
    target.colorMode or fake.ColorMode.RGB,
    { filename = target.filename or "/art/scene.aseprite",
      frameCount = target.frameCount or 3 })
  -- Deliberately spanning to the last frame: that is the range Aseprite grows
  -- when frames are appended after it.
  for _, name in ipairs(target.tags or {}) do
    dest:newTag(1, #dest.frames).name = name
  end
  -- Art already on the sprite, so a canvas grow can be seen to move it.
  dest:newCel(dest.layers[1], 1, Image(dest.width, dest.height), Point(0, 0))
  local cfg = config.new()
  cfg.buildTarget = "active sprite"
  for k, v in pairs(overrides or {}) do cfg[k] = v end
  local grouped = naming.group(entries, config.namingOpts(cfg))
  local pool = sources.newPool()
  local reports, errors = builder.buildAll(grouped, cfg,
    { pool = pool, folder = "/art", target = dest, allowShrink = buildOpts.allowShrink })
  return reports, errors, dest
end

--- Build into a sprite whose tags are laid out as { name, from, to }.
local function replaceFrom(specs, tagSpecs, targetOpts, overrides)
  targetOpts = targetOpts or {}
  local entries = withFiles(specs)   -- resets the fake, so the target comes after
  local dest = fake.newSprite(targetOpts.width or 16, targetOpts.height or 16,
    fake.ColorMode.RGB,
    { filename = "/art/scene.aseprite", frameCount = targetOpts.frameCount or 9 })
  if targetOpts.layerName then dest.layers[1].name = targetOpts.layerName end
  for _, t in ipairs(tagSpecs) do
    local tag = dest:newTag(t[2], t[3])
    tag.name = t[1]
    if t[4] then tag.aniDir = t[4] end
  end

  local cfg = config.new()
  cfg.buildTarget = "an open sprite"
  cfg.existingTags = "replace"
  for k, v in pairs(overrides or {}) do cfg[k] = v end

  local grouped = naming.group(entries, config.namingOpts(cfg))
  local reports, errors = builder.buildAll(grouped, cfg,
    { pool = sources.newPool(), folder = "/art", target = dest })
  return reports, errors, dest
end

--- A sprite's tags as "name from-to", in order.
local function tagLayout(sprite)
  local out = {}
  for _, t in ipairs(sprite.tags) do
    out[#out + 1] = ("%s %d-%d"):format(t.name, t.fromFrame.frameNumber, t.toFrame.frameNumber)
  end
  return table.concat(out, "  ")
end

--- The tag with `name` in a report, or nil.
local function tagNamed(report, name)
  for _, t in ipairs(report.tags) do
    if t.name == name then return t end
  end
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
  eq(r.sprite.tags[2].fromFrame.frameNumber .. "-" .. r.sprite.tags[2].toFrame.frameNumber,
     "3-5", "sprite tag range")
end)

suite("build: every frame gets exactly one cel drawn from its source", function()
  local reports = buildFrom { { "hero_run_00" }, { "hero_run_01" } }
  local layer = reports[1].sprite.layers[1]
  for f = 1, 2 do
    local cel = layer:cel(f)
    check(cel ~= nil, "cel exists at frame " .. f)
    eq(#cel.image.drawn, 1, "one draw call for frame " .. f)
  end
  -- Still frames are read as images, so each cel is drawn from a file rather
  -- than from a sprite that had to be opened for it.
  eq(layer:cel(1).image.drawn[1].image.fromFile, "/art/hero_run_00.png", "frame 1 source")
  eq(layer:cel(2).image.drawn[1].image.fromFile, "/art/hero_run_01.png", "frame 2 source")
end)

suite("sources: still frames are read without opening a sprite", function()
  local _, _, _, pool = buildFrom {
    { "hero_run_00" }, { "hero_run_01" }, { "hero_idle_00" },
  }
  eq(#pool.order, 0, "nothing was opened as a document")
  eq(#fake.app.sprites, 1, "only the sprite that was built exists")
  local cached = 0
  for _ in pairs(pool.images) do cached = cached + 1 end
  eq(cached, 3, "each file read once, and cached")
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

suite("build: indexed sources are composited as rgb by default", function()
  local reports = buildFrom({
    { "hero_run_00", colorMode = fake.ColorMode.INDEXED, paletteColors = { 1, 2, 3 } },
  })
  eq(reports[1].colorMode, "rgb", "result is rgb")
  -- drawImage crosses colour modes on its own, so a still frame no longer
  -- needs a sprite opened and put through ChangePixelFormat to be converted.
  eq(#fake.app.commands, 0, "no conversion round trip was needed")
  eq(reports[1].sprite.layers[1]:cel(1).image.colorMode, fake.ColorMode.RGB,
     "the cel was composited in rgb")
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
  fake.reset()
  -- Only a file that genuinely holds an animation still needs a document; a
  -- still frame is read as an image and never reaches the pool at all.
  fake.files["/art/hero_run.gif"] = { width = 16, height = 16, frameCount = 3 }
  local cfg = config.new()
  local pool = sources.newPool()
  local opened = sources.spriteFor(pool, { title = "hero_run", path = "/art/hero_run.gif" }, cfg)
  check(opened ~= nil, "the animated file was opened")
  eq(#pool.order, 1, "and tracked as ours")

  local userSprite = fake.newSprite(16, 16, fake.ColorMode.RGB, { filename = "/art/hero_run_02.png" })
  sources.spriteFor(pool, { title = "hero_run_02", sprite = userSprite }, cfg)
  cfg.closeSources = false
  sources.release(pool, cfg)
  check(opened.closed, "the opened sprite was closed")
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

suite("collect: on Windows a file is not added twice for differing case", function()
  local collect = require("collect")
  fake.reset()
  fake.app.fs.pathSeparator = "\\"
  fake.dirs["/art"] = { "Hero_run_00.png", "hero_run_01.png" }
  fake.files["/art/Hero_run_00.png"] = { width = 16, height = 16 }
  fake.files["/art/hero_run_01.png"] = { width = 16, height = 16 }
  local cfg = config.new()
  -- The open sprite reports a different case than the directory listing.
  -- The open sprite reports "hero_..." where the listing says "Hero_...".
  local dropped = { { title = "hero_run_00", path = "/art/hero_run_00.png",
                      sprite = fake.newSprite(16, 16, fake.ColorMode.RGB,
                                              { filename = "/art/hero_run_00.png" }) } }
  local merged, added = collect.completeFromFolder(dropped, cfg, config.namingOpts(cfg))
  fake.app.fs.pathSeparator = "/"
  eq(added, 1, "only the genuinely missing file")
  eq(#merged, 2, "no duplicate for the case difference")
end)

suite("collect: on Linux case still distinguishes two files", function()
  local collect = require("collect")
  fake.reset()
  fake.dirs["/art"] = { "Hero_run_00.png", "hero_run_00.png" }
  fake.files["/art/Hero_run_00.png"] = { width = 16, height = 16 }
  fake.files["/art/hero_run_00.png"] = { width = 16, height = 16 }
  local cfg = config.new()
  local dropped = { { title = "hero_run_00", path = "/art/hero_run_00.png" } }
  local _, added = collect.completeFromFolder(dropped, cfg, config.namingOpts(cfg))
  eq(added, 1, "Hero_run_00.png is a different file and is picked up")
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

suite("build: a folded sequence is not counted again from the folder", function()
  fake.reset()
  -- Aseprite folded hero_run_00..05 into one dropped sprite of 6 frames. The
  -- folder completion then offers _01.._05 as files: reading them as images
  -- would silently double the run.
  local dir = {}
  for i = 0, 5 do
    local name = ("hero_run_%02d"):format(i)
    fake.files["/art/" .. name .. ".png"] = { width = 16, height = 16 }
    dir[#dir + 1] = name .. ".png"
  end
  fake.dirs["/art"] = dir

  local folded = fake.newSprite(16, 16, fake.ColorMode.RGB,
    { filename = "/art/hero_run_00.png", frameCount = 6 })
  local entries = { { title = "hero_run_00", sprite = folded } }
  for i = 1, 5 do
    entries[#entries + 1] = { title = ("hero_run_%02d"):format(i),
                              path = ("/art/hero_run_%02d.png"):format(i) }
  end

  local cfg = config.new()
  local grouped = naming.group(entries, config.namingOpts(cfg))
  local pool = sources.newPool()
  local reports, errors, notes = builder.buildAll(grouped, cfg, { pool = pool })
  eq(#errors, 0, "no errors")
  eq(reports[1].frames, 6, "six frames, not eleven")
  eq(#notes, 5, "the five it skipped were reported as notes")
  local cached = 0
  for _ in pairs(pool.images) do cached = cached + 1 end
  eq(cached, 0, "and none of them were even read")
end)

suite("select: unticked animations are left out of the build", function()
  local ui = require("ui")
  local entries = withFiles {
    { "hero_run_00" }, { "hero_run_01" },
    { "hero_idle_00" },
    { "hero_jump_00" },
  }
  local cfg = config.new()
  local grouped = naming.group(entries, config.namingOpts(cfg))
  eq(#grouped.groups, 3, "three animations found")

  eq(ui.selectedGroups(grouped, {}), 3, "nothing unticked means all of them")
  eq(ui.selectedGroups(grouped, { idle = true }), 2, "unticking one drops it")
  eq(ui.selectedGroups(grouped, { idle = true, jump = true, run = true }), 0,
     "unticking everything leaves nothing")

  local kept = ui.withoutExcluded(grouped, { idle = true })
  local names = {}
  for _, g in ipairs(kept.groups) do names[#names + 1] = g.name end
  eq(table.concat(names, ","), "jump,run", "and the rest keep their order")
  eq(#grouped.groups, 3, "the original grouping is not modified")
end)

suite("select: a build skips the animations that were unticked", function()
  local entries = withFiles {
    { "hero_run_00" }, { "hero_run_01" },
    { "hero_idle_00" },
  }
  local ui = require("ui")
  local cfg = config.new()
  local grouped = ui.withoutExcluded(naming.group(entries, config.namingOpts(cfg)),
                                     { idle = true })
  local reports = builder.buildAll(grouped, cfg, { pool = sources.newPool(), folder = "/art" })
  eq(reports[1].frames, 2, "only run's two frames were built")
  eq(#reports[1].tags, 1, "one tag")
  eq(reports[1].tags[1].name, "run", "and it is the one that stayed ticked")
end)

suite("order: animations follow the arranged order", function()
  local ui = require("ui")
  local entries = withFiles {
    { "hero_run_00" }, { "hero_idle_00" }, { "hero_jump_00" },
  }
  local cfg = config.new()
  local grouped = naming.group(entries, config.namingOpts(cfg))
  eq(#grouped.groups, 3, "three animations")

  local arranged = ui.withOrder(grouped, { "run", "jump", "idle" })
  local names = {}
  for _, g in ipairs(arranged.groups) do names[#names + 1] = g.name end
  eq(table.concat(names, ","), "run,jump,idle", "put in the order given")

  -- An order that went stale must not lose anything.
  local partial = ui.withOrder(grouped, { "jump" })
  local pnames = {}
  for _, g in ipairs(partial.groups) do pnames[#pnames + 1] = g.name end
  eq(table.concat(pnames, ","), "jump,idle,run", "unnamed ones keep their place after")

  local stale = ui.withOrder(grouped, { "walk", "crouch" })
  eq(#stale.groups, 3, "an order naming nothing that exists still keeps them all")
  eq(#grouped.groups, 3, "and the original grouping is untouched")
end)

suite("order: the arranged order is what gets built", function()
  local ui = require("ui")
  local entries = withFiles {
    { "hero_run_00" }, { "hero_idle_00" }, { "hero_jump_00" },
  }
  local cfg = config.new()
  local grouped = ui.withOrder(naming.group(entries, config.namingOpts(cfg)),
                               { "jump", "run", "idle" })
  local reports = builder.buildAll(grouped, cfg, { pool = sources.newPool(), folder = "/art" })
  local names = {}
  for _, t in ipairs(reports[1].tags) do names[#names + 1] = t.name end
  eq(table.concat(names, ","), "jump,run,idle", "tags laid down in that order")
  eq(reports[1].tags[1].from, 1, "and the first one starts at frame 1")
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

suite("append: frames land after the ones already there", function()
  local reports, errors, dest = appendFrom {
    { "hero_run_00" }, { "hero_run_01" }, { "hero_run_02" },
    { "hero_idle_00" }, { "hero_idle_01" },
  }
  eq(#errors, 0, "no errors")
  eq(#reports, 1, "one report")
  local r = reports[1]
  eq(r.sprite, dest, "wrote into the sprite it was given")
  eq(r.appended, true, "reported as an append")
  eq(r.frames, 5, "counts only what it added")
  eq(r.firstFrame, 4, "starts after the 3 that were there")
  eq(#dest.frames, 8, "3 existing + 5 appended")

  -- Tag order is alphabetical by default, so idle takes the first slot.
  local idle = tagNamed(r, "idle")
  eq(idle and idle.from, 4, "idle starts at frame 4")
  eq(idle and idle.to, 5, "idle ends at frame 5")
  local run = tagNamed(r, "run")
  eq(run and run.from, 6, "run starts at frame 6")
  eq(run and run.to, 8, "run ends at frame 8")
end)

suite("append: the existing art keeps its own layer", function()
  local reports, _, dest = appendFrom { { "hero_run_00" }, { "hero_run_01" } }
  eq(#dest.layers, 2, "one layer added, not reused")
  eq(dest.layers[1]:cel(1) ~= nil, true, "the original layer keeps its own art")
  eq(dest.layers[1]:cel(4), nil, "and gains nothing from the append")
  local added = dest.layers[2]
  eq(added:cel(4) ~= nil, true, "first appended cel at frame 4")
  eq(added:cel(5) ~= nil, true, "second appended cel at frame 5")
  eq(added:cel(1), nil, "nothing written over the existing frames")
  eq(reports[1].sprite.layers[2].name, "hero", "layer named after the base")
end)

local function warnedAbout(report, text)
  for _, w in ipairs(report.warnings) do
    if w:find(text, 1, true) then return true end
  end
  return false
end

suite("append: the canvas grows to fit frames bigger than the target", function()
  local reports, _, dest = appendFrom({ { "hero_run_00", 32, 32 } }, nil,
    { width = 16, height = 16 })
  local r = reports[1]
  eq(r.canvas.width, 32, "canvas grew to the incoming width")
  eq(r.canvas.height, 32, "canvas grew to the incoming height")
  eq(dest.width .. "x" .. dest.height, "32x32", "the sprite itself was resized")
  eq(warnedAbout(r, "canvas grew from 16x16 to 32x32"), true, "said so")
  eq(warnedAbout(r, "will be cropped"), false, "nothing was cropped")
end)

suite("append: growing carries the existing art with it", function()
  local _, _, dest = appendFrom({ { "hero_run_00", 32, 32 } }, { align = "center" },
    { width = 16, height = 16 })
  local kept = dest.layers[1]:cel(1)
  eq(kept.position.x, 8, "existing art centred on the wider canvas")
  eq(kept.position.y, 8, "and on the taller one")
end)

suite("append: growing to the top-left leaves the existing art in place", function()
  local _, _, dest = appendFrom({ { "hero_run_00", 32, 32 } }, { align = "top-left" },
    { width = 16, height = 16 })
  local kept = dest.layers[1]:cel(1)
  eq(kept.position.x, 0, "existing art stays at x 0")
  eq(kept.position.y, 0, "and at y 0")
  eq(dest.width .. "x" .. dest.height, "32x32", "the canvas still grew")
end)

suite("append: an unconfirmed shrink is refused, not applied", function()
  local reports, _, dest = appendFrom({ { "hero_run_00", 8, 8 } },
    { canvasMode = "custom", canvasWidth = 8, canvasHeight = 8 },
    { width = 16, height = 16 })
  eq(dest.width .. "x" .. dest.height, "16x16", "the target kept its size")
  eq(reports[1].canvas.width, 16, "and the report agrees")
  eq(warnedAbout(reports[1], "would crop the sprite being appended to"), true,
     "explained why the request was not honoured")
end)

suite("append: a confirmed shrink is carried out as asked", function()
  local reports, _, dest = appendFrom({ { "hero_run_00", 8, 8 } },
    { canvasMode = "custom", canvasWidth = 32, canvasHeight = 32 },
    { width = 64, height = 64 }, { allowShrink = true })
  eq(dest.width .. "x" .. dest.height, "32x32", "shrunk to the size that was typed")
  eq(reports[1].canvas.width, 32, "and the report agrees")
  eq(warnedAbout(reports[1], "went from 64x64 to 32x32"), true, "said what it cost")
  -- The 64x64 canvas was centred into 32x32, so everything moved up and left.
  eq(dest.layers[1]:cel(1).position.x, -16, "existing art moved with the crop")
end)

suite("append: a derived canvas never shrinks the target, and says nothing", function()
  local reports, _, dest = appendFrom({ { "hero_run_00", 8, 8 } }, { canvasMode = "max" },
    { width = 64, height = 64 })
  eq(dest.width .. "x" .. dest.height, "64x64", "left exactly as it was")
  eq(warnedAbout(reports[1], "would crop"), false, "no warning for a size it never asked for")
  eq(warnedAbout(reports[1], "canvas"), false, "and nothing about the canvas at all")
end)

suite("build: a custom canvas size is used as given", function()
  local reports = buildFrom({ { "hero_run_00", 8, 8 } },
    { canvasMode = "custom", canvasWidth = 48, canvasHeight = 24 })
  local spr = reports[1].sprite
  eq(spr.width .. "x" .. spr.height, "48x24", "sprite made at the custom size")
  eq(reports[1].canvas.width, 48, "reported width")
  eq(reports[1].canvas.height, 24, "reported height")
end)

suite("append: a custom canvas bigger than both grows the target to it", function()
  local reports, _, dest = appendFrom({ { "hero_run_00", 8, 8 } },
    { canvasMode = "custom", canvasWidth = 40, canvasHeight = 40 },
    { width = 16, height = 16 })
  eq(dest.width .. "x" .. dest.height, "40x40", "grown to the custom size")
  eq(warnedAbout(reports[1], "canvas grew from 16x16 to 40x40"), true, "said so")
end)

suite("append: the target's color mode is kept, never converted", function()
  local reports, _, dest = appendFrom({ { "hero_run_00" } }, { colorMode = "rgb" },
    { colorMode = fake.ColorMode.GRAY })
  eq(dest.colorMode, fake.ColorMode.GRAY, "the target is still gray")
  eq(reports[1].colorMode, "gray", "reported as gray, not the configured rgb")
end)

suite("append: the target is not renamed after the base", function()
  local _, _, dest = appendFrom({ { "hero_run_00" } }, { nameSpriteAfterBase = true })
  eq(dest.filename, "/art/scene.aseprite", "filename left alone")
end)

suite("append: a sprite cannot be appended to itself", function()
  fake.reset()
  local dest = fake.newSprite(16, 16, fake.ColorMode.RGB,
    { filename = "/art/hero_run_00.png" })
  local cfg = config.new()
  cfg.buildTarget = "active sprite"
  local grouped = naming.group({ { title = "hero_run_00", sprite = dest } },
    config.namingOpts(cfg))
  local reports, errors = builder.buildAll(grouped, cfg,
    { pool = sources.newPool(), target = dest })
  eq(#reports, 0, "nothing built")
  eq(#errors, 1, "one error")
  eq(errors[1]:find("one of the frames", 1, true) ~= nil, true, "explains the conflict")
  eq(#dest.frames, 1, "the sprite was left as it was")
end)

suite("append: splitByBase cannot apply, and says so", function()
  local reports, errors = appendFrom({
    { "hero_run_00" }, { "slime_run_00" },
  }, { splitByBase = true })
  eq(#errors, 0, "no errors")
  eq(#reports, 1, "one sprite, not one per base")
  eq(reports[1].warnings[1]:find("cannot apply when appending", 1, true) ~= nil, true,
     "warned that the option was dropped")
end)

suite("append: a tag ending on the last frame does not swallow the new ones", function()
  local _, _, dest = appendFrom({ { "hero_run_00" }, { "hero_run_01" } }, nil,
    { frameCount = 3, tags = { "existing" } })
  -- The fake models Aseprite here: inserting at frame 4 grows a tag that ends
  -- at frame 3 unless its range is put back afterwards.
  local existing = dest.tags[1]
  eq(existing.name, "existing", "the tag that was already there")
  eq(existing.fromFrame.frameNumber, 1, "still starts at frame 1")
  eq(existing.toFrame.frameNumber, 3, "still ends at frame 3")
end)

suite("replace: a matching tag is refreshed where it already sits", function()
  local reports, errors, dest = replaceFrom(
    { { "hero_idle_00" }, { "hero_idle_01" }, { "hero_idle_02" } },
    { { "idle", 1, 3 }, { "run", 4, 6 }, { "jump", 7, 9 } })
  eq(#errors, 0, "no errors")
  eq(#dest.frames, 9, "no frames added")
  eq(tagLayout(dest), "idle 1-3  run 4-6  jump 7-9", "the timeline is unchanged")
  eq(reports[1].replaced, 1, "one tag replaced")
  eq(#dest.tags, 3, "and no second idle tag was made")
  eq(dest.layers[#dest.layers]:cel(1) ~= nil, true, "frame 1 was rewritten")
  eq(dest.layers[#dest.layers]:cel(4), nil, "and run's frames were left alone")
end)

suite("replace: more frames than the tag held pushes the rest along", function()
  local _, _, dest = replaceFrom(
    { { "hero_idle_00" }, { "hero_idle_01" }, { "hero_idle_02" },
      { "hero_idle_03" }, { "hero_idle_04" } },
    { { "idle", 1, 3 }, { "run", 4, 6 }, { "jump", 7, 9 } })
  eq(#dest.frames, 11, "two frames added")
  eq(tagLayout(dest), "idle 1-5  run 6-8  jump 9-11", "idle grew, the others slid down")
end)

suite("replace: fewer frames shrinks the tag, and says what it cost", function()
  local reports, _, dest = replaceFrom(
    { { "hero_idle_00" } },
    { { "idle", 1, 3 }, { "run", 4, 6 }, { "jump", 7, 9 } })
  eq(#dest.frames, 7, "two frames removed")
  eq(tagLayout(dest), "idle 1-1  run 2-4  jump 5-7", "idle shrank, the others slid up")
  eq(warnedAbout(reports[1], "idle went from 3 frames to 1"), true, "said so")
  eq(warnedAbout(reports[1], "any other layer's cels"), true,
     "and warned what the deletion took with it")
end)

suite("replace: an animation with no matching tag is appended instead", function()
  local reports, _, dest = replaceFrom(
    { { "hero_attack_00" }, { "hero_attack_01" } },
    { { "idle", 1, 3 }, { "run", 4, 6 }, { "jump", 7, 9 } })
  eq(#dest.frames, 11, "appended at the end")
  eq(tagLayout(dest), "idle 1-3  run 4-6  jump 7-9  attack 10-11",
     "the tags that were there did not move")
  eq(reports[1].replaced, 0, "nothing was replaced")
end)

suite("replace: a mix of both, in one pass", function()
  local reports, _, dest = replaceFrom(
    { { "hero_idle_00" }, { "hero_idle_01" }, { "hero_attack_00" } },
    { { "idle", 1, 3 }, { "run", 4, 6 } },
    { frameCount = 6 })   -- every frame tagged, so the append lands right after
  -- idle shrinks 3 -> 2, so run slides up, and attack lands after it.
  eq(tagLayout(dest), "idle 1-2  run 3-5  attack 6-6", "replaced in place, then appended")
  eq(reports[1].replaced, 1, "one replaced")
end)

suite("replace: a layer of the same name is reused, not duplicated", function()
  local _, _, dest = replaceFrom(
    { { "hero_idle_00" } },
    { { "idle", 1, 3 } },
    { layerName = "hero" })
  eq(#dest.layers, 1, "no second layer was added")
  eq(dest.layers[1].name, "hero", "and it kept its name")
  eq(dest.layers[1]:cel(1) ~= nil, true, "the frames were written onto it")
end)

suite("replace: the tag itself is left as the user had it", function()
  local _, _, dest = replaceFrom(
    { { "hero_idle_00" }, { "hero_idle_01" }, { "hero_idle_02" } },
    { { "idle", 1, 3, "ping-pong" } },
    nil, { aniDir = "reverse" })
  eq(dest.tags[1].aniDir, "ping-pong", "direction untouched by the import setting")
  eq(dest.tags[1].name, "idle", "and so is the name")
end)

suite("append: a clashing tag name is called out", function()
  local reports = appendFrom({ { "hero_run_00" } }, nil, { tags = { "run" } })
  local warned = false
  for _, w in ipairs(reports[1].warnings) do
    if w:find("already has a tag named run", 1, true) then warned = true end
  end
  eq(warned, true, "warned about the duplicate tag name")
end)

suite("append: named for the undo history", function()
  appendFrom { { "hero_run_00" } }
  eq(fake.app.transactions[#fake.app.transactions], "Append tagged animation",
     "one undo step, named as an append")
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
