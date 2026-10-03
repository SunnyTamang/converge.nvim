---Snapshots on disk. An entry is valid while the theme's files keep the same newest mtime.
local jsonfile = require("converge.jsonfile")

local M = {}

---Bump when the snapshot shape changes.
M.VERSION = 3

---@return string
function M.dir()
  return vim.fs.joinpath(vim.fn.stdpath("cache"), "converge")
end

local function file(name, background)
  local safe = name:gsub("[^%w%-_.]", "_")
  return vim.fs.joinpath(M.dir(), safe .. "@" .. background .. ".json")
end

---@param path string
---@return {sec: integer, nsec: integer}|nil
function M.mtime(path)
  local stat = vim.uv.fs_stat(path)
  return stat and { sec = stat.mtime.sec, nsec = stat.mtime.nsec } or nil
end

local function newer(a, b)
  return a.sec > b.sec or (a.sec == b.sec and a.nsec > b.nsec)
end

-- Folders under a theme's root deeper than this are not looked at (guards odd layouts).
local MAX_DEPTH = 8

---Raise `newest` to the newest file mtime under `dir`. Does not follow linked folders.
local function scan(dir, depth, newest)
  local handle = vim.uv.fs_scandir(dir)
  if not handle then
    return newest
  end
  while true do
    local name, kind = vim.uv.fs_scandir_next(handle)
    if not name then
      return newest
    end
    local path = dir .. "/" .. name
    if kind == "directory" then
      if depth < MAX_DEPTH then
        newest = scan(path, depth + 1, newest)
      end
    else
      local stat = vim.uv.fs_stat(path)
      if stat and stat.type == "file" and newer(stat.mtime, newest) then
        newest = { sec = stat.mtime.sec, nsec = stat.mtime.nsec }
      end
    end
  end
end

---Newest mtime of a theme's files. Most themes keep a stub in `colors/` and the real colors
---in `lua/`, so this looks at every file under `colors/` and `lua/` of the folder that holds
---the theme's `colors/` folder. Never throws.
---@param path string the theme's colors/ file
---@return {sec: integer, nsec: integer}|nil nil when `path` is gone
function M.stamp(path)
  local ok, newest = pcall(function()
    local own = M.mtime(path)
    if not own then
      return nil
    end
    local root = vim.fs.dirname(vim.fs.dirname(path))
    for _, sub in ipairs({ "colors", "lua" }) do
      own = scan(vim.fs.joinpath(root, sub), 1, own)
    end
    return own
  end)
  return ok and newest or nil
end

---@param name string
---@param background string the 'background' the theme was loaded with
---@return table|nil snapshot nil when missing, broken, old or stale
function M.read(name, background)
  local snap = jsonfile.read(file(name, background))
  if
    type(snap) ~= "table"
    or snap.version ~= M.VERSION
    -- Different names can share a file name once sanitized.
    or snap.name ~= name
    or (snap.background ~= "dark" and snap.background ~= "light")
    or type(snap.groups) ~= "table"
    or type(snap.terminal) ~= "table"
    or type(snap.source) ~= "table"
    or type(snap.source.path) ~= "string"
    or type(snap.source.mtime) ~= "table"
  then
    return nil
  end
  local now = M.stamp(snap.source.path)
  if not now or now.sec ~= snap.source.mtime.sec or now.nsec ~= snap.source.mtime.nsec then
    return nil
  end
  return snap
end

---@param snap table
---@param background string the 'background' the theme was loaded with
function M.write(snap, background)
  jsonfile.write(file(snap.name, background), snap)
end

function M.clear()
  vim.fn.delete(M.dir(), "rf")
end

return M
