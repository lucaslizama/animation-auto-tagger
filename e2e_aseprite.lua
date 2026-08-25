-- End-to-end check against a real Aseprite, no UI involved:
--   aseprite --batch --script e2e_aseprite.lua
--
-- Builds a tagged sprite from samples/hero, saves it, reopens it and checks the
-- tags survived the round trip. The other suites run against a fake API; this
-- one is the answer to "but does Aseprite actually do that?".

local naming  = require("naming")
local config  = require("config")
local collect = require("collect")
local sources = require("sources")
local builder = require("builder")

local failures, checks = 0, 0
local function check(ok, msg)
  checks = checks + 1
  if not ok then failures = failures + 1; print("  FAIL: " .. msg) end
end
local function eq(a, e, msg)
  check(a == e, ("%s (expected %s, got %s)"):format(msg, tostring(e), tostring(a)))
end

local root = app.fs.filePath(app.fs.normalizePath(debug.getinfo(1, "S").source:sub(2)))
local samples = app.fs.joinPath(root, "samples/hero")
print("samples: " .. samples)

local cfg = config.new()
cfg.closeSources = false

local entries = collect.fromFolder(samples)
eq(#entries, 20, "collected 20 sample frames")

local grouped = naming.group(entries, config.namingOpts(cfg))
eq(#grouped.groups, 5, "five animations")
eq(naming.frameCount(grouped.groups), 20, "twenty frames")

local pool = sources.newPool()
local reports, errors = builder.buildAll(grouped, cfg, { pool = pool, folder = samples })
for _, e in ipairs(errors) do print("  error: " .. e) end
eq(#errors, 0, "no errors")
eq(#reports, 1, "one sprite built")

local r = reports[1]
local spr = r.sprite
eq(#spr.frames, 20, "sprite has 20 frames")
eq(spr.width .. "x" .. spr.height, "40x32", "canvas grew to fit the wide attack frames")
eq(#spr.tags, 5, "five tags")

-- Tag.fromFrame / Tag.toFrame hand back Frame objects, not plain numbers.
local function tagRange(tag)
  return tag.fromFrame.frameNumber, tag.toFrame.frameNumber
end

local expected = {
  { "attack", 1, 5 }, { "hurt", 6, 7 }, { "idle", 8, 11 },
  { "jump", 12, 14 }, { "run", 15, 20 },
}
for i, want in ipairs(expected) do
  local tag = spr.tags[i]
  local from, to = tagRange(tag)
  eq(tag.name, want[1], "tag " .. i .. " name")
  eq(from, want[2], want[1] .. " starts at " .. want[2])
  eq(to, want[3], want[1] .. " ends at " .. want[3])
end

eq(spr.frames[1].duration, 0.1, "frame duration is 100ms")

-- Every frame must actually carry pixels; an empty cel would mean drawSprite
-- silently did nothing.
local layer = spr.layers[1]
local empty = 0
for f = 1, #spr.frames do
  local cel = layer:cel(f)
  if not cel or cel.image:isEmpty() then empty = empty + 1 end
end
eq(empty, 0, "no empty frames")

-- The 32-wide frames should be centred on the 40-wide canvas.
local idleCel = layer:cel(8)
eq(idleCel.bounds.width, 32, "idle cel is 32 wide")
eq(idleCel.position.x, 4, "and centred (40-32)/2")

sources.release(pool, cfg)

local out = app.fs.joinPath(app.fs.tempPath, "aat_e2e.aseprite")
spr:saveAs(out)
spr:close()

local reopened = Sprite { fromFile = out }
eq(#reopened.frames, 20, "reopened: 20 frames")
eq(#reopened.tags, 5, "reopened: 5 tags")
eq(reopened.tags[5].name, "run", "reopened: last tag name")
local rf, rt = tagRange(reopened.tags[5])
eq(rf .. "-" .. rt, "15-20", "reopened: last tag range")
reopened:close()

--------------------------------------------------------------------------
-- The drag path. Opening the files the way Aseprite does it folds each
-- numbered run into a single sprite, so 20 files arrive as 5 sprites holding
-- 20 frames between them. The result has to come out identical either way.
--------------------------------------------------------------------------

for _, name in ipairs(app.fs.listFiles(samples)) do
  Sprite { fromFile = app.fs.joinPath(samples, name) }
end
print(("open-sprite path: %d sprites open"):format(#app.sprites))
eq(#app.sprites, 20, "each file opened as its own sprite")
-- ... but each one swallowed the rest of its run.
local runSprite
for _, sp in ipairs(app.sprites) do
  if app.fs.fileTitle(sp.filename) == "hero_run_00" then runSprite = sp end
end
eq(runSprite and #runSprite.frames, 6, "hero_run_00 came in holding the whole run")

local openEntries = collect.fromSprites(app.sprites)
local openGrouped = naming.group(openEntries, config.namingOpts(cfg))
eq(#openGrouped.groups, 5, "still five animations")

local pool2 = sources.newPool()
local reports2, errors2, notes2 = builder.buildAll(openGrouped, cfg, { pool = pool2 })
for _, e in ipairs(errors2) do print("  error: " .. e) end
eq(#errors2, 0, "no errors from the open-sprite path")
eq(#notes2, 15, "the 15 swallowed siblings were noted, not treated as failures")
eq(#reports2, 1, "one sprite")
eq(reports2[1].frames, 20, "all 20 frames survived the sequence folding")
eq(#reports2[1].sprite.tags, 5, "five tags")
local of, ot = tagRange(reports2[1].sprite.tags[5])
eq(reports2[1].sprite.tags[5].name .. " " .. of .. "-" .. ot, "run 15-20",
   "and the ranges match the folder path exactly")
sources.release(pool2, cfg)

--------------------------------------------------------------------------
-- A truncated drop. Aseprite's X11 handler cuts the dropped path list once it
-- gets long, so only the first handful of files ever arrive. The plugin has to
-- notice they share a folder and read the rest off disk.
--------------------------------------------------------------------------

for i = #app.sprites, 1, -1 do app.sprites[i]:close() end
eq(#app.sprites, 0, "cleared before the truncation scenario")

local names = {}
for _, n in ipairs(app.fs.listFiles(samples)) do names[#names + 1] = n end
table.sort(names)
for i = 1, 9 do   -- roughly what survives the ~867 character cut
  Sprite { fromFile = app.fs.joinPath(samples, names[i]) }
end
print(("truncated drop: %d of 20 files arrived"):format(9))

local dropped = collect.fromSprites(app.sprites)
local merged, recovered = collect.completeFromFolder(dropped, cfg, config.namingOpts(cfg))
check(recovered > 0, "frames were recovered from the folder")
eq(#merged, 20, "back to twenty entries")

local grouped3 = naming.group(merged, config.namingOpts(cfg))
eq(#grouped3.groups, 5, "five animations again")

local pool3 = sources.newPool()
local reports3, errors3 = builder.buildAll(grouped3, cfg, { pool = pool3 })
for _, e in ipairs(errors3) do print("  error: " .. e) end
eq(#errors3, 0, "no errors")
eq(reports3[1].frames, 20, "all 20 frames, from a drop that lost half of them")
eq(#reports3[1].sprite.tags, 5, "five tags")
local tf, tt = tagRange(reports3[1].sprite.tags[5])
eq(reports3[1].sprite.tags[5].name .. " " .. tf .. "-" .. tt, "run 15-20",
   "including the run that never arrived at all")
sources.release(pool3, cfg)

--------------------------------------------------------------------------
-- One file is enough. A single path is nowhere near the ~867 character cut, so
-- dragging one frame never errors -- and the folder completion turns it back
-- into the whole character. This is the workflow worth recommending.
--------------------------------------------------------------------------

for i = #app.sprites, 1, -1 do app.sprites[i]:close() end
Sprite { fromFile = app.fs.joinPath(samples, "hero_attack_00.png") }
eq(#app.sprites, 1, "one file dropped")

local one = collect.fromSprites(app.sprites)
local oneMerged, oneRecovered = collect.completeFromFolder(one, cfg, config.namingOpts(cfg))
eq(oneRecovered, 19, "the other nineteen came from the folder")

local oneGrouped = naming.group(oneMerged, config.namingOpts(cfg))
local pool4 = sources.newPool()
local reports4, errors4 = builder.buildAll(oneGrouped, cfg, { pool = pool4 })
eq(#errors4, 0, "no errors")
eq(reports4[1].frames, 20, "one dropped file rebuilt all 20 frames")
eq(#reports4[1].sprite.tags, 5, "and all five tags")
local sf, st = tagRange(reports4[1].sprite.tags[5])
eq(reports4[1].sprite.tags[5].name .. " " .. sf .. "-" .. st, "run 15-20", "ranges intact")
sources.release(pool4, cfg)

--------------------------------------------------------------------------
-- Appending into a sprite that already exists. The fake API answers "does the
-- builder do the arithmetic right"; only Aseprite answers "is newLayer real,
-- and does a tag created at frame 24 survive a save".
--------------------------------------------------------------------------

for i = #app.sprites, 1, -1 do app.sprites[i]:close() end

local existing = Sprite(40, 32, ColorMode.RGB)
existing.layers[1].name = "background"
for i = 2, 3 do existing:newEmptyFrame(i) end
existing:newTag(1, 3).name = "existing"
eq(#existing.frames, 3, "target starts with 3 frames")

local pool5 = sources.newPool()
local reports5, errors5 = builder.buildAll(
  naming.group(collect.fromFolder(samples), config.namingOpts(cfg)), cfg,
  { pool = pool5, folder = samples, target = existing })
for _, e in ipairs(errors5) do print("  error: " .. e) end
eq(#errors5, 0, "no errors")
eq(#reports5, 1, "one report")
eq(reports5[1].sprite, existing, "wrote into the sprite it was handed")
eq(reports5[1].appended, true, "reported as an append")
eq(reports5[1].firstFrame, 4, "started after the frames already there")

eq(#existing.frames, 23, "3 existing + 20 appended")
eq(#existing.layers, 2, "the frames went onto a layer of their own")
eq(existing.layers[1].name, "background", "the original layer is untouched")
eq(#existing.tags, 6, "the tag that was there, plus five")

local af, at = tagRange(existing.tags[#existing.tags])
eq(existing.tags[#existing.tags].name .. " " .. af .. "-" .. at, "run 18-23",
   "the last appended tag sits at the end")
local ef, et = tagRange(existing.tags[1])
eq(ef .. "-" .. et, "1-3", "the tag that was already there did not move")

-- The appended cels must hold pixels, and must not have landed on frame 1.
local appendedLayer = existing.layers[2]
local emptyAppended = 0
for f = 4, #existing.frames do
  local cel = appendedLayer:cel(f)
  if not cel or cel.image:isEmpty() then emptyAppended = emptyAppended + 1 end
end
eq(emptyAppended, 0, "every appended frame carries pixels")
eq(appendedLayer:cel(1), nil, "nothing was written over the existing frames")

sources.release(pool5, cfg)

local appendOut = app.fs.joinPath(app.fs.tempPath, "aat_e2e_append.aseprite")
existing:saveAs(appendOut)
existing:close()

local reopenedAppend = Sprite { fromFile = appendOut }
eq(#reopenedAppend.frames, 23, "reopened: 23 frames")
eq(#reopenedAppend.tags, 6, "reopened: 6 tags")
eq(#reopenedAppend.layers, 2, "reopened: both layers")
local rrf, rrt = tagRange(reopenedAppend.tags[6])
eq(rrf .. "-" .. rrt, "18-23", "reopened: appended tag range survived the round trip")
reopenedAppend:close()

--------------------------------------------------------------------------
-- Appending a sprite into itself has to be refused, not attempted.
--------------------------------------------------------------------------

local selfTarget = Sprite { fromFile = app.fs.joinPath(samples, "hero_idle_00.png") }
local selfEntries = collect.fromSprites({ selfTarget })
local pool6 = sources.newPool()
local reports6, errors6 = builder.buildAll(
  naming.group(selfEntries, config.namingOpts(cfg)), cfg,
  { pool = pool6, target = selfTarget })
eq(#reports6, 0, "nothing built")
eq(#errors6, 1, "one error")
eq(#selfTarget.frames, 4, "the sprite was left exactly as it was")
sources.release(pool6, cfg)
selfTarget:close()

print(("\n%d checks, %d failure(s)"):format(checks, failures))
if failures > 0 then os.exit(1) end
