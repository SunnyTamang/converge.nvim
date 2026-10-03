---Options and recipe handling.
local log = require("converge.log")
local slices = require("converge.slices")
local store = require("converge.store")

local M = {}

---@type {recipe: table<string, string>}
M.options = { recipe = {} }

---Return a clean copy of `recipe`: only known slices with usable theme names.
---@param recipe any
---@param where string where the recipe came from, for warnings
---@return table<string, string>
function M.validate(recipe, where)
  local clean = {}
  if type(recipe) ~= "table" then
    log.warn(where .. ": recipe must be a table")
    return clean
  end
  local keys = vim.tbl_keys(recipe)
  table.sort(keys, function(a, b)
    return tostring(a) < tostring(b)
  end)
  for _, key in ipairs(keys) do
    local value = recipe[key]
    if not slices.is_slice(key) then
      log.warn(string.format("%s: unknown slice '%s' ignored", where, tostring(key)))
    elseif type(value) ~= "string" or value == "" then
      log.warn(string.format("%s: theme for '%s' must be a non-empty string", where, key))
    elseif value == "converge" then
      log.warn(string.format("%s: theme for '%s' cannot be 'converge'", where, key))
    else
      clean[key] = value
    end
  end
  return clean
end

---@param opts {recipe?: table}|nil
function M.setup(opts)
  opts = opts or {}
  M.options = { recipe = M.validate(opts.recipe or {}, "setup") }
end

---Fill every slice. A missing slice uses the ui theme; a missing ui uses "default".
---@param recipe table<string, string>
---@return table<string, string>
function M.complete(recipe)
  local ui = recipe.ui or "default"
  local full = {}
  for _, name in ipairs(slices.names) do
    full[name] = recipe[name] or ui
  end
  return full
end

---The active recipe, every slice filled. The saved recipe wins over setup().
---@return table<string, string>
function M.resolve()
  local saved, err = store.read()
  if err then
    log.warn(err)
  end
  local base = saved and M.validate(saved, "saved recipe") or M.options.recipe
  return M.complete(base)
end

---Recipe as Lua text, ready to paste into `setup({ ... })`.
---@param recipe table<string, string>
---@return string
function M.to_lua(recipe)
  local lines = { "recipe = {" }
  for _, name in ipairs(slices.names) do
    if recipe[name] then
      table.insert(lines, string.format("  %s = %q,", name, recipe[name]))
    end
  end
  table.insert(lines, "},")
  return table.concat(lines, "\n")
end

return M
