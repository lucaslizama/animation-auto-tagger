-- Unit tests for naming.lua. Run with a stock Lua interpreter:
--   lua tests/run_tests.lua
-- (Aseprite is not needed; naming.lua has no editor dependencies.)

package.path = "./src/?.lua;../src/?.lua;" .. package.path
local naming = require("naming")

local failures, checks = 0, 0

local function check(ok, msg)
  checks = checks + 1
  if not ok then
    failures = failures + 1
    io.write("  FAIL: ", msg, "\n")
  end
end

local function eq(actual, expected, msg)
  check(actual == expected,
    ("%s (expected %s, got %s)"):format(msg, tostring(expected), tostring(actual)))
end

local function titles(list)
  local t = {}
  for i, e in ipairs(list) do t[i] = e.title end
  return table.concat(t, ",")
end

local suites = {}
local function suite(name, fn) suites[#suites + 1] = { name = name, fn = fn } end

--------------------------------------------------------------------- parsing

suite("parse: canonical name_anim_index", function()
  local p = naming.parse("hero_run_03")
  check(p.ok, "should parse")
  eq(p.base, "hero", "base")
  eq(p.anim, "run", "anim")
  eq(p.index, 3, "index")
  eq(p.indexText, "03", "index text keeps padding")
end)

suite("parse: animation name containing separators", function()
  local mid = naming.parse("hero_attack_heavy_00", { animMode = "middle" })
  eq(mid.base, "hero", "middle base")
  eq(mid.anim, "attack_heavy", "middle anim")

  local last = naming.parse("hero_attack_heavy_00", { animMode = "last" })
  eq(last.base, "hero_attack", "last base")
  eq(last.anim, "heavy", "last anim")

  local whole = naming.parse("hero_attack_heavy_00", { animMode = "whole" })
  eq(whole.base, "", "whole base")
  eq(whole.anim, "hero_attack_heavy", "whole anim")
end)

suite("parse: no base token", function()
  local p = naming.parse("run_00")
  eq(p.base, "", "base is empty when only one token precedes the index")
  eq(p.anim, "run", "anim")
  eq(p.index, 0, "index")
end)

suite("parse: digits inside the name stay in the stem", function()
  local p = naming.parse("hero_run2_05")
  eq(p.base, "hero", "base")
  eq(p.anim, "run2", "anim keeps its own digits")
  eq(p.index, 5, "index is the trailing token only")
end)

suite("parse: glued index", function()
  local p = naming.parse("hero_run01", { allowGluedIndex = true })
  check(p.ok, "glued index parses")
  eq(p.anim, "run", "anim")
  eq(p.index, 1, "index")

  local off = naming.parse("hero_run01", { allowGluedIndex = false, allowNoIndex = true })
  eq(off.anim, "run01", "with glued index off the digits stay in the name")

  local bare = naming.parse("0001", { allowGluedIndex = true, allowNoIndex = false })
  check(not bare.ok, "a name that is only digits is not an animation")
end)

suite("parse: missing index", function()
  local ok = naming.parse("hero_idle", { allowNoIndex = true, allowGluedIndex = false })
  check(ok.ok, "parses as a single-frame animation")
  eq(ok.anim, "idle", "anim")
  eq(ok.index, nil, "no index")

  local strict = naming.parse("hero_idle", { allowNoIndex = false, allowGluedIndex = false })
  check(not strict.ok, "rejected when an index is required")
end)

suite("parse: alternate separator", function()
  local p = naming.parse("hero-run-03", { separator = "-" })
  eq(p.base, "hero", "base")
  eq(p.anim, "run", "anim")
  eq(p.index, 3, "index")
end)

suite("parse: separator that is a pattern metacharacter", function()
  local p = naming.parse("hero.run.03", { separator = "." })
  eq(p.base, "hero", "base")
  eq(p.anim, "run", "anim")
  eq(p.index, 3, "index")
end)

suite("parse: custom pattern", function()
  local three = naming.parse("f00_run_hero", { customPattern = "^(%d+)_(%a+)_(%a+)$" })
  check(not three.ok, "third capture must be numeric to be an index")

  local p = naming.parse("hero@run@07", { customPattern = "^(%w+)@(%w+)@(%d+)$" })
  check(p.ok, "custom pattern parses")
  eq(p.base, "hero", "base")
  eq(p.anim, "run", "anim")
  eq(p.index, 7, "index")

  local two = naming.parse("run#12", { customPattern = "^(%a+)#(%d+)$" })
  eq(two.base, "", "two captures mean anim + index")
  eq(two.anim, "run", "anim")
  eq(two.index, 12, "index")
end)

---------------------------------------------------------------------- groups

suite("group: orders frames numerically, not lexically", function()
  local r = naming.group({
    { title = "hero_run_10" }, { title = "hero_run_2" }, { title = "hero_run_1" },
  })
  eq(#r.groups, 1, "one group")
  eq(titles(r.groups[1].items), "hero_run_1,hero_run_2,hero_run_10", "numeric order")
end)

suite("group: alphabetical vs first-seen ordering", function()
  local entries = {
    { title = "hero_run_00" }, { title = "hero_attack_00" }, { title = "hero_idle_00" },
  }
  local alpha = naming.group(entries, { groupOrder = "alphabetical" })
  eq(alpha.groups[1].name .. "," .. alpha.groups[2].name .. "," .. alpha.groups[3].name,
     "attack,idle,run", "alphabetical")

  local seen = naming.group(entries, { groupOrder = "first-seen" })
  eq(seen.groups[1].name .. "," .. seen.groups[2].name .. "," .. seen.groups[3].name,
     "run,attack,idle", "first-seen")
end)

suite("group: unmatched entries are reported, not dropped", function()
  local r = naming.group({
    { title = "hero_run_00" }, { title = "palette" },
  }, { allowNoIndex = false, allowGluedIndex = false })
  eq(#r.groups, 1, "one group")
  eq(#r.unmatched, 1, "one unmatched")
  eq(r.unmatched[1].entry.title, "palette", "the unmatched title")
end)

suite("group: duplicate indices warn", function()
  -- Inconsistent zero padding is the realistic way this happens.
  local r = naming.group({ { title = "hero_run_0" }, { title = "hero_run_00" } })
  eq(#r.groups, 1, "still one group")
  check(#r.warnings >= 1, "duplicate index produces a warning")
  check(r.warnings[1]:find("index", 1, true) ~= nil, "warning mentions the index")
end)

suite("group: payload fields survive", function()
  local r = naming.group({ { title = "hero_run_00", path = "/tmp/hero_run_00.png" } })
  eq(r.groups[1].items[1].path, "/tmp/hero_run_00.png", "path passed through")
end)

suite("group: bases collected and split", function()
  local r = naming.group({
    { title = "hero_run_00" }, { title = "orc_run_00" }, { title = "hero_idle_00" },
  })
  eq(table.concat(r.bases, ","), "hero,orc", "bases sorted and unique")
  eq(#r.groups, 2, "hero_run + orc_run share the tag \"run\"; idle is its own tag")
  local mixed = false
  for _, w in ipairs(r.warnings) do
    if w:find("mixes base names", 1, true) then mixed = true end
  end
  check(mixed, "and warns that a tag mixes base names")

  local prefixed = naming.group({
    { title = "hero_run_00" }, { title = "orc_run_00" },
  }, { prefixTagWithBase = true })
  eq(#prefixed.groups, 2, "prefixing keeps them apart")
  eq(prefixed.groups[1].name, "hero_run", "prefixed tag name")

  local buckets = naming.splitByBase(prefixed.groups)
  eq(#buckets, 2, "two buckets")
  eq(buckets[1].base, "hero", "first bucket")
end)

suite("frameCount", function()
  local r = naming.group({
    { title = "hero_run_00" }, { title = "hero_run_01" }, { title = "hero_idle_00" },
  })
  eq(naming.frameCount(r.groups), 3, "total frames")
end)

------------------------------------------------------------------------ run

for _, s in ipairs(suites) do
  local before = failures
  local ok, err = pcall(s.fn)
  if not ok then
    failures = failures + 1
    io.write("  ERROR: ", tostring(err), "\n")
  end
  io.write((failures > before) and "[FAIL] " or "[ ok ] ", s.name, "\n")
end

io.write(("\n%d checks, %d failure(s)\n"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)
