-- The drag path, as close as a script can get to it:
--   aseprite --batch <every sample frame> --script tests/e2e_dragpath.lua
--
-- The frames come from tests/make_samples.lua, which the runners call first so
-- the files exist before Aseprite starts.
--
-- Aseprite opens the files through its own path first, which folds each
-- numbered run into a single sprite. The plugin then has to rebuild the same
-- 20-frame, 5-tag result it gets from the folder.

-- Run from the repo root: aseprite --batch --script tests/e2e_dragpath.lua
-- The modules live in src/, which is not on Aseprite's default search path.
local here = (debug.getinfo(1, "S").source:sub(2)):match("^(.*)[/\\]") or "."
package.path = here .. "/../src/?.lua;" .. package.path

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

print(("aseprite opened %d sprites from 20 files"):format(#app.sprites))
check(#app.sprites > 0, "something is open")

local cfg = config.new()
cfg.closeSources = false

local entries = collect.fromSprites(app.sprites)
local grouped = naming.group(entries, config.namingOpts(cfg))
eq(#grouped.groups, 5, "five animations")

local pool = sources.newPool()
local reports, errors, notes = builder.buildAll(grouped, cfg, { pool = pool })
for _, e in ipairs(errors) do print("  error: " .. e) end
eq(#errors, 0, "no errors")
eq(#reports, 1, "one sprite")
eq(reports[1].frames, 20, "20 frames, whatever Aseprite did to the files on the way in")
eq(#reports[1].sprite.tags, 5, "five tags")

local expected = {
  { "attack", 1, 5 }, { "hurt", 6, 7 }, { "idle", 8, 11 },
  { "jump", 12, 14 }, { "run", 15, 20 },
}
for i, want in ipairs(expected) do
  local tag = reports[1].sprite.tags[i]
  eq(tag.name, want[1], "tag " .. i .. " name")
  eq(tag.fromFrame.frameNumber, want[2], want[1] .. " starts at " .. want[2])
  eq(tag.toFrame.frameNumber, want[3], want[1] .. " ends at " .. want[3])
end

eq(reports[1].sprite.width .. "x" .. reports[1].sprite.height, "40x32", "canvas")
sources.release(pool, cfg)

print(("\n%d checks, %d failure(s)"):format(checks, failures))
-- Aseprite's Lua has no os.exit, so the exit code cannot carry the verdict and
-- a runner reading it would call a failing suite a pass. This line is what the
-- runner actually checks.
print(failures > 0 and "e2e-result: FAIL" or "e2e-result: ok")
