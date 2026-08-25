--- Gathering candidate frames, either from disk or from what is already open.

local naming = require("naming")

local M = {}

-- Formats Aseprite can open. Anything else in the folder is skipped silently
-- rather than reported as an unparseable name.
M.EXTENSIONS = {
  png = true, gif = true, jpg = true, jpeg = true, bmp = true, tga = true,
  webp = true, qoi = true, pcx = true, flc = true, fli = true, flh = true,
  aseprite = true, ase = true, psd = true, svg = true,
}

-- Windows path comparison is case-insensitive, so the same file can reach us as
-- C:\Art\hero_run_00.png from an open sprite and c:\art\Hero_run_00.png from
-- the directory listing. Comparing verbatim would treat them as two files and
-- add a duplicate frame. On Linux and macOS case is significant, so it is left
-- alone there.
function M.pathKey(path)
  local key = app.fs.normalizePath(path)
  if app.fs.pathSeparator == "\\" then key = key:lower() end
  return key
end

function M.isSupported(path)
  return M.EXTENSIONS[app.fs.fileExtension(path):lower()] == true
end

--- Every image file in `folder`, as { title, path } entries sorted by name.
function M.fromFolder(folder)
  local entries = {}
  if not folder or folder == "" or not app.fs.isDirectory(folder) then
    return entries
  end
  for _, name in ipairs(app.fs.listFiles(folder)) do
    local path = app.fs.joinPath(folder, name)
    if M.isSupported(path) and not app.fs.isDirectory(path) then
      entries[#entries + 1] = { title = app.fs.fileTitle(name), path = path }
    end
  end
  table.sort(entries, function(a, b) return a.title < b.title end)
  return entries
end

--- Open sprites that came from a file, as { title, sprite } entries.
-- `only` is an optional set of sprite ids to restrict the scan to.
function M.fromSprites(spriteList, only)
  local entries = {}
  for _, sprite in ipairs(spriteList) do
    if (not only or only[sprite.id]) and sprite.filename and sprite.filename ~= "" then
      entries[#entries + 1] = {
        title = app.fs.fileTitle(sprite.filename),
        sprite = sprite,
        path = sprite.filename,
      }
    end
  end
  table.sort(entries, function(a, b) return a.title < b.title end)
  return entries
end

--- Fill in the frames a drop lost on the way in.
--
-- Aseprite's X11 drag-and-drop concatenates the dropped paths into one string
-- without reading it in chunks, so past roughly 867 characters the list is cut
-- mid-path: drag twenty frames and about half of them never arrive. Nothing a
-- script can do about that -- the drop breaks before scripting sees it.
--
-- What a script can do is notice that everything which *did* arrive came from
-- one folder, and read the rest off disk. Modes:
--   "folder"  every matching file in that folder (fixes whole missing animations)
--   "gaps"    only files belonging to animations that already arrived
--   "off"     use exactly what was dropped
--
-- Returns the merged entries and how many were recovered. Entries already open
-- are kept as they are, so the user's own sprites are reused rather than
-- reopened from disk.
function M.completeFromFolder(entries, cfg, namingOpts)
  local mode = cfg.completeDrops or "folder"
  if mode == "off" or #entries == 0 then return entries, 0 end

  local folder = M.commonFolder(entries)
  if folder == "" then return entries, 0 end

  local have = {}
  local anims = {}
  for _, e in ipairs(entries) do
    if e.path then have[M.pathKey(e.path)] = true end
    local parsed = naming.parse(e.title, namingOpts)
    if parsed.ok then anims[naming.tagName(parsed, namingOpts)] = true end
  end

  local merged = {}
  for _, e in ipairs(entries) do merged[#merged + 1] = e end

  local added = 0
  for _, candidate in ipairs(M.fromFolder(folder)) do
    if not have[M.pathKey(candidate.path)] then
      local keep = (mode == "folder")
      if not keep then
        local parsed = naming.parse(candidate.title, namingOpts)
        keep = parsed.ok and anims[naming.tagName(parsed, namingOpts)] == true
      end
      if keep then
        merged[#merged + 1] = candidate
        added = added + 1
      end
    end
  end

  if added > 0 then
    table.sort(merged, function(a, b) return a.title < b.title end)
  end
  return merged, added
end

--- The folder shared by a set of entries, or "" when they are spread around.
function M.commonFolder(entries)
  local folder = nil
  for _, e in ipairs(entries) do
    if e.path and e.path ~= "" then
      local dir = app.fs.filePath(e.path)
      if folder == nil then folder = dir
      elseif folder ~= dir then return "" end
    end
  end
  return folder or ""
end

return M
