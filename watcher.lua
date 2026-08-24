--- Noticing that a batch of sprites just appeared.
--
-- Aseprite's scripting API has no drag-and-drop event and no "file opened"
-- event: app.events only offers sitechange, beforesitechange, fgcolorchange,
-- bgcolorchange, beforecommand and aftercommand, and dropping files onto the
-- editor is handled entirely in C++ without going through a named command.
-- So the only way to react to a drop is to watch app.sprites on a Timer.
--
-- A drop of N files opens N documents one after another, so the watcher waits
-- until the list stops growing for a few ticks before it calls back. That is
-- what keeps a 12-file drag from firing twelve times.

local M = {}

local Watcher = {}
Watcher.__index = Watcher

function M.new(opts)
  return setmetatable({
    getConfig = opts.getConfig,     -- function() -> cfg
    onBatch   = opts.onBatch,       -- function(sprites)
    known     = {},
    pending   = {},
    pendingCount = 0,
    quiet     = 0,
    busy      = false,
    held      = false,
    timer     = nil,
  }, Watcher)
end

--- Keep the watcher quiet until release() is called.
--
-- The callback puts up a non-modal dialog, so it returns long before the user
-- has decided anything. Without this the next tick would notice the same
-- situation and ask again.
function Watcher:hold()
  self.held = true
end

function Watcher:release()
  self.held = false
  -- Only now is it safe to resync: whatever the user just built exists.
  self:sync()
  self.busy = false
end

--- Treat everything currently open as already seen.
function Watcher:sync()
  self.known = {}
  for _, s in ipairs(app.sprites) do self.known[s.id] = true end
  self.pending, self.pendingCount, self.quiet = {}, 0, 0
end

function Watcher:tick()
  -- Re-entrancy guard: the callback may open a modal dialog, and the timer
  -- keeps ticking underneath it.
  if self.busy then return end

  local seenNow = {}
  local fresh = false

  for _, sprite in ipairs(app.sprites) do
    seenNow[sprite.id] = true
    if not self.known[sprite.id] then
      self.known[sprite.id] = true
      -- Only sprites backed by a file can carry a name to parse.
      if sprite.filename and sprite.filename ~= "" then
        self.pending[#self.pending + 1] = sprite
        self.pendingCount = self.pendingCount + 1
        fresh = true
      end
    end
  end

  for id in pairs(self.known) do
    if not seenNow[id] then self.known[id] = nil end
  end

  if fresh then
    self.quiet = 0
    return
  end
  if self.pendingCount == 0 then return end

  local cfg = self.getConfig()
  self.quiet = self.quiet + 1
  if self.quiet < math.max(1, cfg.watchQuietTicks) then return end

  local batch = self.pending
  self.pending, self.pendingCount, self.quiet = {}, 0, 0

  -- Drop anything the user closed again while we were waiting.
  local alive = {}
  for _, s in ipairs(batch) do
    if s.isValid then alive[#alive + 1] = s end
  end
  if #alive == 0 then return end

  self.busy = true
  self.held = false
  local ok, err = pcall(function() self.onBatch(alive) end)
  if not ok then
    print("Animation Auto-Tagger watcher error: " .. tostring(err))
    self.held = false
  end
  if not self.held then
    -- Whatever the callback created (the tagged sprite, for one) must not look
    -- like a fresh drop on the next tick.
    self:sync()
    self.busy = false
  end
end

function Watcher:start()
  local cfg = self.getConfig()
  self:stop()
  self:sync()
  self.timer = Timer {
    interval = math.max(0.05, (cfg.watchIntervalMs or 250) / 1000.0),
    ontick = function() self:tick() end,
  }
  self.timer:start()
end

function Watcher:stop()
  if self.timer then
    self.timer:stop()
    self.timer = nil
  end
  self.pending, self.pendingCount, self.quiet = {}, 0, 0
  self.busy, self.held = false, false
end

function Watcher:isRunning()
  return self.timer ~= nil
end

return M
