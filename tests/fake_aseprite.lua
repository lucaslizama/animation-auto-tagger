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

function Image:drawImage(image, pos)
  self.drawn[#self.drawn + 1] = { image = image, pos = pos }
end

function Image:isEmpty() return #self.drawn == 0 end

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
  -- Ranges are read before the insert and re-pointed after, because Aseprite
  -- moves tags along with the frames: one that starts later shifts down, and
  -- one whose last frame the insert lands on (or inside) grows to include it.
  local ranges = {}
  for i, tag in ipairs(self.tags) do
    ranges[i] = { tag.fromFrame.frameNumber, tag.toFrame.frameNumber }
  end

  table.insert(self.frames, n, { frameNumber = n, duration = 0.1, sprite = self })
  for i, f in ipairs(self.frames) do f.frameNumber = i end

  for i, tag in ipairs(self.tags) do
    local from, to = ranges[i][1], ranges[i][2]
    if n <= from then
      from, to = from + 1, to + 1
    elseif n <= to + 1 then
      to = to + 1
    end
    tag.fromFrame, tag.toFrame = self.frames[from], self.frames[to]
  end
  return self.frames[n]
end

function Sprite:newLayer()
  local layer = setmetatable(
    { name = "Layer " .. (#self.layers + 1), sprite = self, celsByFrame = {} }, Layer)
  self.layers[#self.layers + 1] = layer
  return layer
end

function Sprite:newCel(layer, frame, image, position)
  local cel = { layer = layer, frameNumber = frame, image = image,
                position = position or Point(0, 0), sprite = self }
  layer.celsByFrame[frame] = cel
  return cel
end

function Sprite:deleteCel(cel) cel.layer.celsByFrame[cel.frameNumber] = nil end

-- fromFrame/toFrame are Frame objects in Aseprite, not numbers, and assigning
-- either a Frame or a plain number to them is allowed.
function Sprite:newTag(from, to)
  local tag = setmetatable({ sprite = self, name = "", aniDir = AniDir.FORWARD }, {
    __newindex = function(t, k, v)
      if (k == "fromFrame" or k == "toFrame") and type(v) == "number" then
        v = t.sprite.frames[v]
      end
      rawset(t, k, v)
    end,
  })
  tag.fromFrame, tag.toFrame = self.frames[from], self.frames[to]
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
      -- CanvasSize takes padding per side and carries the existing cels along
      -- with it, which is what a script relies on when growing a sprite.
      if name == "CanvasSize" and app.sprite then
        local s = app.sprite
        local left, top = params.left or 0, params.top or 0
        s.width = s.width + left + (params.right or 0)
        s.height = s.height + top + (params.bottom or 0)
        for _, layer in ipairs(s.layers) do
          for _, cel in pairs(layer.celsByFrame) do
            cel.position = Point(cel.position.x + left, cel.position.y + top)
          end
        end
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
    if type(a) == "table" then
      -- Image{fromFile=} reads one still frame and opens no sprite, which is
      -- the whole point of it: nothing is added to F.app.sprites here.
      local spec = F.files[a.fromFile]
      if not spec then error("no such fake file: " .. tostring(a.fromFile)) end
      local img = newImage(spec.width, spec.height, spec.colorMode or ColorMode.RGB)
      img.fromFile = a.fromFile
      return img
    end
    return newImage(a, b, c or ColorMode.RGB)
  end })

  _G.Palette = setmetatable({}, { __call = function(_, a)
    if type(a) == "table" and a.fromFile then
      local spec = F.files[a.fromFile]
      return newPalette(spec and spec.paletteColors)
    end
    return newPalette()
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
