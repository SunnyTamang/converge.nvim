---One place to get a theme snapshot: session memo, then disk cache, then capture.
local cache = require("converge.cache")
local capture = require("converge.capture")
local log = require("converge.log")

local M = {}

-- "<name>@<background>" -> snapshot, or false when the theme failed this session.
local memo = {}

-- A cache that cannot be written fails for every theme: say it once.
local write_warned = false

---@param name string
---@param background string
---@param opts {capture: boolean}
---@return table|false|nil snapshot; false if the theme failed; nil if unknown and capture is off
function M.get(name, background, opts)
  local key = name .. "@" .. background
  if memo[key] ~= nil then
    return memo[key]
  end
  local snap = cache.read(name, background)
  if not snap and opts.capture then
    local err
    snap, err = capture.capture(name, background)
    if snap then
      if snap.source then
        -- The disk cache is optional: a failed write must not stop rendering.
        local ok, write_err = pcall(cache.write, snap, background)
        if not ok and not write_warned then
          write_warned = true
          log.warn("could not write the cache: " .. tostring(write_err))
        end
      end
    else
      log.warn(string.format("theme '%s' failed to load: %s", name, err))
      snap = false
    end
  end
  if snap ~= nil then
    memo[key] = snap
  end
  return snap
end

---Forget the session memo.
function M.clear()
  memo = {}
end

return M
