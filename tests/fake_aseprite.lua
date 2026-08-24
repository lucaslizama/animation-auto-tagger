--- A small stand-in for the Aseprite scripting API.
--
-- It covers exactly the surface builder.lua and sources.lua touch, which is
-- enough to test the parts most likely to be wrong: frame counts, tag ranges,
-- cel placement and colour-mode routing. It is a test double, not an emulator.

local F = {}

local nextId = 0
local function newId() nextId = nextId + 1; return nextId end

------------------------------------------------------------------ enums

local ColorMode = { RGB = "rgb", GRAY = "gray", INDEXED = "indexed", TILEMAP = "tilemap" }
local AniDir = { FORWARD = "forward", REVERSE = "reverse",
                 PING_PONG = "ping-pong", PING_PONG_REVERSE = "ping-pong-reverse" }

local function Point(x, y) return { x = x, y = y } end
local function Color(t) return { r = t.r, g = t.g, b = t.b } end

------------------------------------------------------------------ image

local Image = {}
Image.__index = Image

local function newImage(w, h, mode)
  return setmetatable({ width = w, height = h, colorMode = mode, drawn = {} }, Image)
end

function Image:drawSprite(sprite, frame, pos)
  self.drawn[#self.drawn + 1] = { sprite = sprite, frame = frame, pos = pos }
end

------------------------------------------------------------ layer / cel

local Layer = {}
Layer.__index = Layer

function Layer:cel(frameNumber) return self.celsByFrame[frameNumber] end

------------------------------------------------------------- palette

local Palette = {}
Palette.__index = Palette
Palette.__len = function(self) return #self.colors end

local function newPalette(colors)
  return setmetatable({ colors = colors or { 0 } }, Palette)
end

function Palette:getColor(i) return { rgbaPixel = self.colors[i + 1] } end

------------------------------------------------------------- sprite

local Sprite = {}
Sprite.__index = Sprite

local function newSprite(w, h, mode, opts)
  opts = opts or {}
  local s = setmetatable({
    id = newId(),
    width = w, height = h,
    colorMode = mode or ColorMode.RGB,
    filename = opts.filename or "",
    isModified = false,
    isValid = true,
    closed = false,
    transparentColor = 0,
    palettes = { newPalette(opts.paletteColors) },
    frames = {},
    layers = {},
    tags = {},
  }, Sprite)

  local layer = setmetatable({ name = "Layer 1", sprite = s, celsByFrame = {} }, Layer)
  s.layers[1] = layer

  for i = 1, (opts.frameCount or 1) do
    s.frames[i] = { frameNumber = i, duration = opts.frameDuration or 0.1, sprite = s }
  end
  F.app.sprites[#F.app.sprites + 1] = s
  return s
end

function Sprite:newEmptyFrame(n)
  table.insert(self.frames, n, { frameNumber = n, duration = 0.1, sprite = self })
  for i, f in ipairs(self.frames) do f.frameNumber = i end
  return self.frames[n]
end

function Sprite:newCel(layer, frame, image, position)
  local cel = { layer = layer, frameNumber = frame, image = image,
                position = position or Point(0, 0), sprite = self }
  layer.celsByFrame[frame] = cel
  return cel
end

function Sprite:deleteCel(cel) cel.layer.celsByFrame[cel.frameNumber] = nil end

function Sprite:newTag(from, to)
  local tag = { sprite = self, fromFrame = from, toFrame = to, name = "", aniDir = AniDir.FORWARD }
  self.tags[#self.tags + 1] = tag
  return tag
end

function Sprite:setPalette(p) self.palettes[1] = p end

function Sprite:close()
  self.closed = true
  self.isValid = false
  for i, s in ipairs(F.app.sprites) do
    if s == self then table.remove(F.app.sprites, i); break end
  end
end

------------------------------------------------------- virtual file system

-- Map of path -> { width, height, colorMode, frameCount, paletteColors }
F.files = {}

local function spriteFromFile(path, oneFrame)
  local spec = F.files[path]
  if not spec then error("no such fake file: " .. tostring(path)) end
  -- `sequence` models Aseprite's numbered-file-sequence detection: opening
  -- hero_run_00.png without oneFrame pulls _01, _02 ... in as extra frames.
  local frames = spec.frameCount or 1
  if not oneFrame and spec.sequence then frames = spec.sequence end
  local s = newSprite(spec.width, spec.height, spec.colorMode or ColorMode.RGB, {
    filename = path,
    frameCount = oneFrame and 1 or frames,
    paletteColors = spec.paletteColors,
    frameDuration = spec.frameDuration,
  })
  s.loadedOneFrame = oneFrame and true or false
  return s
end

----------------------------------------------------------------- app

local app = {}
app.sprite = nil
app.sprites = {}
F.app = app
app.transactions = {}
app.commands = {}

function app.transaction(a, b)
  local name, fn
  if type(a) == "function" then name, fn = "", a else name, fn = a, b end
  app.transactions[#app.transactions + 1] = name
  return fn()
end

app.fs = {
  pathSeparator = "/",
  joinPath = function(a, b)
    if a == "" then return b end
    return (a:gsub("/$", "")) .. "/" .. b
  end,
  filePath = function(p) return (p:match("^(.*)/[^/]*$")) or "" end,
  fileName = function(p) return (p:match("([^/]*)$")) end,
  fileTitle = function(p) return ((p:match("([^/]*)$")):gsub("%.[^.]*$", "")) end,
  fileExtension = function(p) return (p:match("%.([^.]*)$")) or "" end,
  normalizePath = function(p) return (p:gsub("//+", "/")) end,
  isDirectory = function(p) return F.dirs and F.dirs[p] ~= nil end,
  listFiles = function(p) return (F.dirs and F.dirs[p]) or {} end,
}

app.command = setmetatable({}, {
  __index = function(_, name)
    return function(params)
      app.commands[#app.commands + 1] = { name = name, params = params }
      if name == "ChangePixelFormat" and app.sprite then
        app.sprite.colorMode = params.format
      end
    end
  end,
})

-- Tests set this to control which button app.alert reports as pressed.
app.alertAnswer = 1
app.alerts = {}
function app.alert(t) app.alerts[#app.alerts + 1] = t; return app.alertAnswer end
function app.refresh() end
function app.tip() end

----------------------------------------------------------------- install

--- Publish the fake API as globals, the way Aseprite does.
function F.install()
  _G.ColorMode = ColorMode
  _G.AniDir = AniDir
  _G.Point = Point
  _G.Color = Color
  _G.app = app

  -- Timers never fire on their own here; tests drive watcher:tick() directly.
  _G.Timer = setmetatable({}, { __call = function(_, t)
    local timer = { interval = t.interval, ontick = t.ontick, isRunning = false }
    function timer:start() self.isRunning = true end
    function timer:stop() self.isRunning = false end
    return timer
  end })

  _G.Image = setmetatable({}, { __call = function(_, a, b, c)
    if type(a) == "table" then error("Image{fromFile=} is not stubbed") end
    return newImage(a, b, c or ColorMode.RGB)
  end })

  _G.Sprite = setmetatable({}, { __call = function(_, a, b, c)
    if type(a) == "table" and a.fromFile then
      return spriteFromFile(a.fromFile, a.oneFrame)
    elseif type(a) == "table" then
      -- duplicate
      local dup = newSprite(a.width, a.height, a.colorMode,
        { filename = a.filename, frameCount = #a.frames })
      return dup
    end
    return newSprite(a, b, c)
  end })

  F.ColorMode = ColorMode
  F.newSprite = newSprite
  F.newPalette = newPalette
  return F
end

function F.reset()
  F.files = {}
  F.dirs = {}
  app.sprite = nil
  app.sprites = {}
  app.transactions = {}
  app.commands = {}
  app.alerts = {}
  app.alertAnswer = 1
end

return F
