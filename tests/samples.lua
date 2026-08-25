--- The sample frames the end-to-end suites build from.
--
-- Made by Aseprite when they are needed rather than kept in the repository.
-- The names are the whole point of the fixture and the pictures only have to be
-- distinguishable, so there is nothing here worth storing: twenty flat-filled
-- PNGs that any machine can regenerate in a moment.
--
-- They land in the temp directory, so a checkout stays clean and nothing has to
-- be tidied up afterwards.

local M = {}

-- The attack frames are wider than the rest on purpose: that is what makes the
-- suites able to check a canvas growing to fit the widest source.
M.HERO = {
  { name = "attack", frames = 5, width = 40, height = 32 },
  { name = "hurt",   frames = 2, width = 32, height = 32 },
  { name = "idle",   frames = 4, width = 32, height = 32 },
  { name = "jump",   frames = 3, width = 32, height = 32 },
  { name = "run",    frames = 6, width = 32, height = 32 },
}

--- Where the frames go, unless a caller says otherwise.
function M.defaultDir()
  return app.fs.joinPath(app.fs.tempPath, "animation-auto-tagger-samples")
end

--- Write one frame, filled edge to edge.
--
-- Filled rather than drawn on, so the cel's bounds are the whole image: a
-- transparent margin would shrink them and make every size the suites check
-- meaningless.
local function writeFrame(path, w, h, r, g, b)
  local sprite = Sprite(w, h, ColorMode.RGB)
  local img = Image(w, h, ColorMode.RGB)
  img:clear(Color { r = r, g = g, b = b, a = 255 })
  sprite:newCel(sprite.layers[1], 1, img, Point(0, 0))
  sprite:saveAs(path)
  sprite:close()
end

--- Make sure the sample frames exist, and return the directory holding them.
--
-- `base` names the character, so a second cast member can be made for testing
-- one-sprite-per-base. Existing files are left alone, which keeps a re-run
-- close to free.
function M.ensure(dir, base, spec)
  dir = dir or app.fs.joinPath(M.defaultDir(), base or "hero")
  base = base or "hero"
  spec = spec or M.HERO

  if not app.fs.isDirectory(dir) then
    app.fs.makeAllDirectories(dir)
  end

  local written = 0
  for a, anim in ipairs(spec) do
    for i = 0, anim.frames - 1 do
      local path = app.fs.joinPath(dir, ("%s_%s_%02d.png"):format(base, anim.name, i))
      if not app.fs.isFile(path) then
        -- A colour per animation, lightened per frame, so a glance at the built
        -- timeline says whether the ordering came out right.
        writeFrame(path, anim.width, anim.height,
                   30 + a * 40, 40 + i * 30, 150 - a * 20)
        written = written + 1
      end
    end
  end

  return dir, written
end

--- Every frame the spec describes, as full paths, in name order.
function M.paths(dir, base, spec)
  base = base or "hero"
  spec = spec or M.HERO
  local out = {}
  for _, anim in ipairs(spec) do
    for i = 0, anim.frames - 1 do
      out[#out + 1] = app.fs.joinPath(dir, ("%s_%s_%02d.png"):format(base, anim.name, i))
    end
  end
  table.sort(out)
  return out
end

--- How many frames the spec adds up to.
function M.frameCount(spec)
  local n = 0
  for _, anim in ipairs(spec or M.HERO) do n = n + anim.frames end
  return n
end

return M
