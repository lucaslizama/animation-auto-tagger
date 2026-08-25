-- Tests for the drop-detection debounce in watcher.lua.
--   lua tests/test_watcher.lua

package.path = "./src/?.lua;./tests/?.lua;../src/?.lua;../tests/?.lua;" .. package.path

local fake    = require("fake_aseprite").install()
local config  = require("config")
local watcher = require("watcher")

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

local function newWatcher(overrides)
  fake.reset()
  local cfg = config.new()
  cfg.watchQuietTicks = 2
  for k, v in pairs(overrides or {}) do cfg[k] = v end
  local batches = {}
  local w = watcher.new {
    getConfig = function() return cfg end,
    onBatch = function(sprites) batches[#batches + 1] = sprites end,
  }
  return w, batches, cfg
end

local function drop(name)
  return fake.newSprite(16, 16, fake.ColorMode.RGB, { filename = "/art/" .. name .. ".png" })
end

------------------------------------------------------------------- suites

suite("a multi-file drop fires exactly once, after it settles", function()
  local w, batches = newWatcher()
  w:start()

  drop("hero_run_00"); w:tick()
  drop("hero_run_01"); w:tick()
  drop("hero_run_02"); w:tick()
  eq(#batches, 0, "nothing fired while files were still arriving")

  w:tick()            -- first quiet tick
  eq(#batches, 0, "still waiting")
  w:tick()            -- second quiet tick reaches watchQuietTicks
  eq(#batches, 1, "fired once")
  eq(#batches[1], 3, "with all three sprites")

  w:tick(); w:tick(); w:tick()
  eq(#batches, 1, "and does not fire again on its own")
end)

suite("sprites already open when watching starts are not a batch", function()
  local w, batches = newWatcher()
  drop("hero_run_00")
  drop("hero_run_01")
  w:start()           -- start() syncs, so these count as known
  w:tick(); w:tick(); w:tick()
  eq(#batches, 0, "no batch from pre-existing sprites")
end)

suite("unsaved sprites are ignored", function()
  local w, batches = newWatcher()
  w:start()
  fake.newSprite(16, 16, fake.ColorMode.RGB)   -- File > New, no filename
  w:tick(); w:tick(); w:tick()
  eq(#batches, 0, "a sprite with no filename is not a dropped frame")
end)

suite("a file closed again before the batch settles is dropped", function()
  local w, batches = newWatcher()
  w:start()
  local a = drop("hero_run_00")
  local b = drop("hero_run_01")
  w:tick()
  a:close()
  w:tick(); w:tick()
  eq(#batches, 1, "fired")
  eq(#batches[1], 1, "only the surviving sprite")
  eq(#batches[1][1].filename, #b.filename, "the one still open")
end)

suite("whatever the callback creates is not seen as a new drop", function()
  fake.reset()
  local cfg = config.new()
  cfg.watchQuietTicks = 1
  local batches = {}
  local w
  w = watcher.new {
    getConfig = function() return cfg end,
    onBatch = function(sprites)
      batches[#batches + 1] = sprites
      -- The builder names the result, so it does have a filename.
      fake.newSprite(16, 16, fake.ColorMode.RGB, { filename = "/art/hero.aseprite" })
    end,
  }
  w:start()
  drop("hero_run_00")
  w:tick(); w:tick()
  eq(#batches, 1, "the drop fired")
  w:tick(); w:tick(); w:tick()
  eq(#batches, 1, "the sprite the callback made did not fire a second batch")
end)

suite("an error in the callback does not wedge the watcher", function()
  fake.reset()
  local cfg = config.new()
  cfg.watchQuietTicks = 1
  local calls = 0
  local w
  w = watcher.new {
    getConfig = function() return cfg end,
    onBatch = function() calls = calls + 1; error("boom") end,
  }
  w:start()
  drop("hero_run_00")
  w:tick(); w:tick()
  eq(calls, 1, "callback ran")
  check(not w.busy, "the re-entrancy guard was released")

  drop("hero_run_01")
  w:tick(); w:tick()
  eq(calls, 2, "a later drop still fires")
end)

suite("a held watcher does not ask again until it is released", function()
  fake.reset()
  local cfg = config.new()
  cfg.watchQuietTicks = 1
  local calls, w = 0, nil
  w = watcher.new {
    getConfig = function() return cfg end,
    onBatch = function() calls = calls + 1; w:hold() end,   -- non-modal: returns at once
  }
  w:start()
  drop("hero_run_00")
  w:tick(); w:tick()
  eq(calls, 1, "asked once")

  drop("hero_run_01")
  w:tick(); w:tick(); w:tick()
  eq(calls, 1, "still just once while the prompt is up")

  w:release()
  drop("hero_run_02")
  w:tick(); w:tick()
  eq(calls, 2, "and asks again once released")
end)

suite("release resyncs, so what the prompt built is not a new drop", function()
  fake.reset()
  local cfg = config.new()
  cfg.watchQuietTicks = 1
  local calls, w = 0, nil
  w = watcher.new {
    getConfig = function() return cfg end,
    onBatch = function() calls = calls + 1; w:hold() end,
  }
  w:start()
  drop("hero_run_00")
  w:tick(); w:tick()
  eq(calls, 1, "asked once")

  -- The user clicks Build: the sprite is created, then the dialog closes.
  fake.newSprite(16, 16, fake.ColorMode.RGB, { filename = "/art/hero.aseprite" })
  w:release()
  w:tick(); w:tick(); w:tick()
  eq(calls, 1, "the built sprite did not trigger a second prompt")
end)

suite("stopping while held does not wedge the watcher", function()
  fake.reset()
  local cfg = config.new()
  cfg.watchQuietTicks = 1
  local calls, w = 0, nil
  w = watcher.new {
    getConfig = function() return cfg end,
    onBatch = function() calls = calls + 1; w:hold() end,
  }
  w:start()
  drop("hero_run_00")
  w:tick(); w:tick()
  w:stop()
  w:start()
  drop("hero_run_01")
  w:tick(); w:tick()
  eq(calls, 2, "a restart clears the hold")
end)

suite("start/stop", function()
  local w = newWatcher()
  check(not w:isRunning(), "not running initially")
  w:start()
  check(w:isRunning(), "running after start")
  w:stop()
  check(not w:isRunning(), "stopped")
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
